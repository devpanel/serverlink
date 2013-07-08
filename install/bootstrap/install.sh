#!/bin/bash

DP_TARGET_DIR=${DP_TARGET_DIR:-"/opt/webenabled"}

usage() {
  local prog=$(basename "$0")

  echo "
Usage: $prog [ options ] <-u server_uuid> <-k server_key>

  Options:
    -u server_uuid    the server uuid to use on taskd
    -k server_key     the server secret key to use on taskd
    -A taskd_api      the api url to use on taskd
    -U api_url        the address of the user api url
    -d                enable debug mode
"

  if [ $EUID -ne 0 ]; then
    echo 
    echo "This script requires ROOT privileges to run"
    echo
  fi

  exit 1
}

error() {
  local msg="$1"
  local ret=$2

  echo "Error: $msg" 1>&2
  [ -n "$ret" ] && exit $ret
  exit 1
}

# main

[ $# -lt 2 ] && usage

if [ $EUID -ne 0 ]; then
  error "this script requires ROOT privileges to run successfully"
fi

umask 022

source_dir=`dirname "${BASH_SOURCE[0]}"`
if ! source "$source_dir/root/lib/functions"; then
  error "unable to import library '$source_dir/root/lib/functions'"
fi

getopt_flags='du:k:A:U:'
taskd_api="https://tasks.devpanel.com/"

unset dp_server_uuid dp_server_key dp_server_hostname
while getopts $getopt_flags OPT; do
  case "$OPT" in
    u)
      dp_server_uuid="$OPTARG"
      ;;
    k)
      dp_server_key="$OPTARG"
      ;;
    A)
      taskd_api="$OPTARG"
      ;;
    d)
      set -x
      ;;
    U)
      dp_user_api_url="$OPTARG"
      ;;
    *)
      exit 1
  esac
done
[ -n $OPTIND -a $OPTIND -gt 1 ] && shift $(( $OPTIND - 1 ))

if [ -z "$dp_server_uuid" ]; then
  error "the server uuid was not provided. Please pass it with the option -u"
elif [ -z "$dp_server_key" ]; then
  error "the server key was not provided. Please pass it with the option -k"
elif [ -z "$taskd_api" ]; then
  error "the taskd_api was not provided. Please pass it with the option -A"
fi

linux_distro=$(wedp_auto_detect_distro)
if [ $? -ne 0 -o -z "$linux_distro" ]; then
  error "unable to detect linux distro"
fi

distro_bootstrap_file="$source_dir/bootstrap.$linux_distro.sh"
if ! source "$distro_bootstrap_file"; then
  error "unable to load bootstrap file '$distro_bootstrap_file' for distro '$linux_distro'"
fi

if ! type -t "bootstrap_${linux_distro}" >/dev/null; then
  error "missing function 'bootstrap_${linux_distro}'"
elif ! "bootstrap_$linux_distro" "$source_dir" "$DP_TARGET_DIR"; then
  error "failed running function 'bootstrap_$linux'"
fi

skel_dir="$source_dir/skel/$linux_distro"
if [ ! -d "$skel_dir" ]; then
  error "missing skel dir '$skel_dir'"
fi

(cd "$skel_dir" && cp -a . /)
if [ $? -ne 0 ]; then
  error "unable to copy files from skel dir '$skel_dir'"
fi

# config/os is a link set after a successful installation
# if it's there it means that a previous installation was successful
config_dir="$DP_TARGET_DIR/config/os"
if [ -e "$config_dir" ]; then
  error "this server seems already configured. Bailing out."
fi

lock_file="/var/run/devpanel_install.lock"
if ! ln -s /dev/null "$lock_file"; then
  error "there seems to have another installation running. Cannot create lock file '$lock_file'."
fi
trap 'ex=$?; rm -f "$lock_file" ; trap - EXIT INT HUP TERM; exit $ex' EXIT INT HUP TERM

dp_user="devpanel"
if ! getent passwd "$dp_user" &>/dev/null; then
  useradd -m -c "$comment" -d "/home/$dp_user" "$dp_user"
  if [ $? -ne 0 ]; then
    error "unable to create user '$dp_user'"
  fi
fi

( cd "$source_dir/root" && cp -a . "$DP_TARGET_DIR" )
if [ $? -ne 0 ]; then
  error "unable to copy files to '$DP_TARGET_DIR'"
fi

config_file="$DP_TARGET_DIR/etc/devpanel.conf"
if [ -e "$config_file" ]; then
  old_suffix=`date +%b-%d-%Y-%H:%M`
  cp -f "$config_file" "$config_file.$old_suffix"
fi

chown root:"$dp_user" "$config_file"
chmod 660 "$config_file"
if [ $? -ne 0 ]; then
  echo "Warning: unable to set the permissions of config file '$config_file'" 1>&2
fi

if ! ini_section_replace_key_value "$config_file" taskd uuid "$dp_server_uuid"; then
  error "unable to set taskd uuid on file '$config_file'"
elif ! ini_section_replace_key_value "$config_file" taskd key "$dp_server_key"; then
  error "unable to set taskd key on file '$config_file'"
elif ! ini_section_replace_key_value "$config_file" taskd api_url "$taskd_api"; then
  error "unable to set taskd key on file '$config_file'"
fi

if [ -n "$dp_user_api_url" ]; then
  ini_section_replace_key_value "$config_file" user_api api_url "$dp_user_api_url"
fi

"$DP_TARGET_DIR/libexec/system-services" devpanel-taskd start
status=$?
if [ $status -ne 0 ]; then
  error "unable to start taskd. Returned $status"
fi

echo "Successfully deployed taskd"
exit 0
