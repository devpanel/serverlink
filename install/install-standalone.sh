#!/bin/bash
#set -x

# To install devpanel on your server, start with a fresh server install of Ubuntu, Debian, CentOS or RedHat
# login and use the following commands:
# $ wget https://www.devpanel.com/install.sh
# $ chmod 755 install
# $ sudo ./install

usage() {
  echo "Usage: ${0##*/} [options]

  Options:
    -b <branch>           clone the code from the specified git branch
    -H <hostname>         hostname of the server (used as the base domain
                          for virtual hosts)
    -2                    enable extensions for platform version 2
    -3                    enable extensions for platform version 3
    -h                    show this help message
"
  exit 1
}

bootstrap_ubuntu() {
  export DEBIAN_FRONTEND='noninteractive'
  apt-get -y install git libcrypt-ssleay-perl libjson-xs-perl liburi-perl
}

bootstrap_debian() {
  export DEBIAN_FRONTEND='noninteractive'
  apt-get -y install git libcrypt-ssleay-perl libjson-xs-perl liburi-perl
}

bootstrap_redhat() {
  yum -y install git perl-Crypt-SSLeay perl-URI
}

bootstrap_centos() {
  yum -y install git perl-Crypt-SSLeay perl-URI
}

download_file() {
  local url="$1"
  local temp_file="$2"
  local retries=${3:-3}
  local wait_before_retry=${4:-20}

  if hash curl &>/dev/null; then
    curl -sS -f -L --retry $retries --retry-delay $wait_before_retry -o "$temp_file" "$url"
    status=$?
  elif hash wget &>/dev/null; then
    wget -t $retries -w $wait_before_retry -O "$temp_file" "$url"
    status=$?
  fi

  return $status
}

devpanel_auto_detect_distro() {
  local distro=""

  # can't use local -l below because of systems with bash 3
  local lsb_distro_str="" lsb_distro_raw=""

  # first try to detect the Linux distro using lsb_release
  if hash lsb_release &>/dev/null; then
    lsb_distro_raw=`lsb_release -si 2>/dev/null`
    if [ $? -eq 0 -a -n "$lsb_distro_raw" ]; then
      lsb_distro_str=`echo -n "$lsb_distro_raw" | tr A-Z a-z`
      if [ -n "$lsb_distro_str" ]; then
        # found distro with lsb_release
        echo -n "$lsb_distro_str"
        return 0
      fi
    fi
  fi

  # detection through lsb_release failed, 
  # use the installed package names
  local has_apt has_yum
  hash apt-cache &>/dev/null && has_apt=1
  hash yum       &>/dev/null && has_yum=1

  if [ -n "$has_apt" ]; then
    if apt-cache show base-files | egrep -q '^Maintainer:.+@.*debian\.org>'; then
      distro=debian
    elif apt-cache show base-files | egrep -q '^Maintainer:.+@.*ubuntu\.com>'; then
      distro=ubuntu
    fi
  elif [ -n "$has_yum" ]; then
    if yum info centos-release &>/dev/null; then
      distro=centos
    elif yum info redhat-release-server &>/dev/null; then
      distro=redhat
    fi
  elif [[ "$OSTYPE" =~ ^darwin ]]; then
    distro=macosx
  fi

  if [ -n "$distro" ]; then
    echo -n "$distro"
    return 0
  else
    return 1
  fi
}

# IMPORTANT: please keep the lines below!!!
#
# Variables below are used in the friendly URL install, to avoid having the
# user to pass parameters in the command line.
#
# These values are to be filled and uncommented out by the install server
#tasks_url='%%TASKS_URL%%'
#server_hostname='%%SERVER_HOSTNAME%%'
#server_uuid='%%SERVER_UUID%%'
#server_key='%%SECRET_KEY%%'
#from_bootstrap='%%FROM_BOOTSTRAP%%'

install_dir="/opt/webenabled"
git_url="https://github.com/devpanel/serverlink.git"

# main

unset git_branch has_tty platform_version
autogen_hostname=1
getopt_flags='23hGb:H:'
while getopts $getopt_flags OPTN; do
  case $OPTN in
    h)
      usage
      ;;
    b)
      git_branch="$OPTARG"
      ;;
    H)
      server_hostname="$OPTARG"
      ;;
    [23])
      platform_version="$OPTN"
      ;;
    *)
      exit 1
      ;;
  esac
done
[ $OPTIND -gt 1 ] && shift $(( $OPTIND - 1 ))

if [ $EUID -ne 0 ]; then
  echo "Error: this script needs to be run with ROOT privileges." >&2
  exit 1
fi

git_branch=${git_branch:-master}
if [ -n "$server_hostname" ]; then
  unset autogen_hostname
fi

if tty -s &>/dev/null; then
  has_tty=1
fi

if hash apt-get &>/dev/null; then
  # for distros based on apt-get, run apt-get update to update apt's
  # internal cache before trying to install any package (otherwise when the
  # cache is outdated and it's attempted to install a package that was
  # updated, the install fails)
  export DEBIAN_FRONTEND='noninteractive'
  if ! apt-get update; then
    echo "Error: apt-get update failed." 1>&2
  fi
fi

# install lsb_release to more precisely detect distro
if ! hash lsb_release &>/dev/null && hash apt-get &>/dev/null; then
  apt-get -y install lsb-release
elif ! hash lsb_release &>/dev/null && hash yum &>/dev/null; then
  yum -y install redhat-lsb-core
fi

distro=`devpanel_auto_detect_distro`
if [ $? -ne 0 ]; then
  echo "Error: unable to auto detect linux distribution." 1>&2
  exit 1
fi

if ! type -t "bootstrap_$distro" &>/dev/null; then
  echo "Error: missing function bootstrap_$distro" 1>&2
  exit 1
fi

if ! "bootstrap_$distro"; then
  echo "Error: failed to install the minimal required software for devPanel installation." 1>&2
  exit 1
fi

temp_dir=$(mktemp -d "$install_dir.XXXXXX")
status=$?
if [ $status -ne 0 ]; then
  echo "Error: unable to create temporary directory. mktemp returned $status" >&2
  exit 1
fi

trap 'cd / ; rm -rf "$temp_dir"' EXIT INT TERM

echo
echo
echo "Starting DevPanel install. Cloning installation files..."
echo
echo

source_dir="$temp_dir/serverlink"
git clone -b "$git_branch" "$git_url" "$source_dir"
if [ $? -ne 0 ]; then
  echo "Error: failed cloning base install from '$git_url'" 1>&2
  exit 1
fi

"$source_dir/install/install.sh" -I "$install_dir" \
 ${from_bootstrap:+-b} ${tasks_url:+-A "$tasks_url"} \
 ${server_hostname:+-H "$server_hostname"} \
 ${platform_version:+-$platform_version} \
 ${server_uuid:+-U "$server_uuid"} ${server_key:+-K "$server_key"}

status=$?

devpanel init config ${autogen_hostname:+--gen-hostname-from-ip} \
  ${server_hostname:+--hostname "$server_hostname"}

if [ $status -eq 0 -a -n "$has_tty" ]; then
  devpanel help --section intro
fi

exit $status
