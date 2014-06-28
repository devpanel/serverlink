#!/bin/bash

bootstrap_ubuntu() {
  export DEBIAN_FRONTEND='noninteractive'
  apt-get -y install git
}

bootstrap_debian() {
  export DEBIAN_FRONTEND='noninteractive'
  apt-get -y install git
}

bootstrap_redhat() {
  yum -y install git
}

bootstrap_centos() {
  yum -y install git
}

download_file() {
  local url="$1"
  local temp_file="$2"
  local retries=${3:-3}
  local wait_before_retry=${4:-20}

  if hash curl &>/dev/null; then
    curl -f -L --retry $retries --retry-delay $wait_before_retry -o "$temp_file" "$url"
    status=$?
  elif hash wget &>/dev/null; then
    wget -t $retries -w $wait_before_retry -O "$temp_file" "$url"
    status=$?
  fi

  return $status
}

devpanel_auto_detect_distro() {
  local distro=""

  if hash rpm &>/dev/null && rpm -ql centos-release &>/dev/null; then
    distro=centos
  elif hash rpm &>/dev/null && rpm -ql redhat-release-server &>/dev/null; then
    distro=redhat
  elif hash rpm &>/dev/null && rpm -ql owl-hier >/dev/null 2>&1; then
    distro=owl
  elif hash lsb_release &>/dev/null && [ "`lsb_release -si 2>/dev/null`" == "Debian" ]; then
    distro=debian
  elif hash lsb_release &>/dev/null && [ "`lsb_release -si 2>/dev/null`" == "Ubuntu" ]; then
    distro=ubuntu
  fi

  if [ -n "$distro" ]; then
    echo $distro
    return 0
  else
    return 1
  fi
}

# main
if [ $EUID -ne 0 ]; then
  echo "Error: this script needs to be run with ROOT privileges." >&2
  exit 1
fi

# giving a chance to Proxmox that doesn't have lsb-release installed
# by default (installing lsb_release for the distro detection not to fail)
if ! hash lsb_release &>/dev/null && hash apt-get &>/dev/null; then
  export DEBIAN_FRONTEND='noninteractive'
  apt-get -y install lsb-release
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

temp_dir=$(mktemp -d)
status=$?
if [ $status -ne 0 ]; then
  echo "Error: unable to create temporary directory. mktemp returned $status" >&2
  exit 1
fi

trap 'cd / ; rm -rf "$temp_dir"' EXIT INT TERM

if ! cd "$temp_dir" ; then
  echo "Error: unable to enter into temp dir" >&2
  exit 1
fi

install_dir="/opt/webenabled"
if ! cd "$install_dir"; then
  echo "Error: unable to change to '$install_dir'" 1>&2
  exit 1
fi

git_url="https://github.com/devpanel/paas-provisioner.git"

echo
echo
echo "Cloning DevPanel Paas Provisioner..."
echo
echo

git clone "$git_url"
if [ $? -ne 0 ]; then
  echo "Error: failed cloning base install from '$git_url'" 1>&2
  exit 1
fi

echo
echo "Successfully cloned pass-provisioner repository."
exit 0
