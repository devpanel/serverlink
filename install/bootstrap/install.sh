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

install_dir="${BASH_SOURCE[0]}"
if ! source "$current_dir/lib/functions"; then
  error "unable to import library '$current_dir/lib/functions'"
fi

getopt_flags='du:k:A:'
taskd_api="https://tasks.devpanel.com/"

unset dp_server_uuid dp_server_key
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
taskd_api=$(escape_sed "$taskd_api")

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
trap 'rm -f "$lock_file" ; trap - EXIT INT HUP TERM; exit 1' EXIT INT HUP TERM

dp_user="devpanel"
if ! getent passwd "$dp_user" &>/dev/null; then
  useradd -m -c "$comment" -d "/home/$dp_user" "$dp_user"
  if [ $? -ne 0 ]; then
    error "unable to create user '$dp_user'"
  fi
fi

( cd "$install_dir/webenabled-devpanel" && cp -a . "$DP_TARGET_DIR" )
if [ $? -ne 0 ]; then
  error "unable to copy files to '$DP_TARGET_DIR'"
fi

config_file="$DP_TARGET_DIR/config/devpanel.conf"
if [ -e "$config_file" ]; then
  old_suffix=`date +%b-%d-%Y-%H:%M`
  mv -f "$config_file" "$config_file.$old_suffix"
fi

mv -f "$config_file.template" "$config_file"
if [ $? -ne 0 ]; then
  error "unable to create the config file '$config_file'"
fi

chown root:"$dp_user" "$config_file"
chmod 660 "$config_file"
if [ $? -ne 0 ]; then
  echo "Warning: unable to set the permissions of config file '$config_file'" 1>&2
fi

if ! ini_section_replace_values "$config_file" taskd uuid "$dp_server_uuid"; then
  error "unable to set taskd uuid on file '$config_file'"
elif ! ini_section_replace_values "$config_file" taskd key "$dp_server_key"; then
  error "unable to set taskd key on file '$config_file'"
elif ! ini_section_replace_values "$config_file" taskd api_url "$taskd_api"; then
  error "unable to set taskd key on file '$config_file'"
fi

export DEBIAN_FRONTEND='noninteractive'
apt-get -y install libnet-ssleay-perl libjson-xs-perl

"$DP_TARGET_DIR/sbin/taskd"

status=$?
if [ $status -ne 0 ]; then
  error "unable to start taskd. Returned $status"
fi

echo "Successfully deployed taskd"
exit 0
