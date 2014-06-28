#!/bin/bash

usage() {
  local prog=$(basename "$0")

  echo "
Usage: $prog
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

download_file() {
  local url="$1"
  local temp_file="$2"
  local retries=${3:-3}
  local wait_before_retry=${4:-20}

  if hash curl &>/dev/null; then
    curl -s -f -L --retry $retries --retry-delay $wait_before_retry -o "$temp_file" "$url"
    status=$?
  elif hash wget &>/dev/null; then
    wget -t $retries -w $wait_before_retry -O "$temp_file" "$url"
    status=$?
  fi

  return $status
}

# main

if [ $EUID -ne 0 ]; then
  error "this script requires ROOT privileges to run successfully"
fi

umask 022

unset dp_server_uuid dp_server_key is_provisioner

# the lines below are to be uncommented out when this script is served
# through the install URL
#dp_server_uuid=""
#dp_server_key=""
#taskd_api=""
#is_provisioner=1

provisioner_repo="https://github.com/devpanel/paas-provisioner"
target_dir="/opt/webenabled"
bootstrap_url="https://install.devpanel.com/bootstrap.tar"

if [ -z "$dp_server_uuid" ]; then
  error "the server uuid is not set."
elif [ -z "$dp_server_key" ]; then
  error "the server key is not set."
elif [ -z "$taskd_api" ]; then
  error "the taskd_api is not set."
fi

tmp_bootstrap_dir=`mktemp -d /tmp/bootstrap_provisioner.XXXXXXXXXXXXXX`
if [ $? -ne 0 ]; then
  error "unable to create temporary dir"
fi
trap 'ex=$?; rm -rf "$tmp_bootstrap_dir"; exit $ex' HUP INT TERM EXIT

tmp_tar=`mktemp "$tmp_bootstrap_dir/bootstrap.tar.XXXXXXXXXXX"`
if [ $? -ne 0 ]; then
  error "unable to create temporary file"
fi

if ! download_file "$bootstrap_url" "$tmp_tar"; then
  error "unable to download the bootstrap tar file from '$bootstrap_url'"
fi

if ! tar -xf "$tmp_tar" -C "$tmp_bootstrap_dir"; then
  error "unable to extract bootstrap tar file '$tmp_tar'"
fi

"$tmp_bootstrap_dir/bootstrap/install.sh" -u "$dp_server_uuid" \
  -k "$dp_server_key" -A "$taskd_api"

if [ $? -ne 0 ]; then
  exit 1
fi

if [ -n "$is_provisioner" -a "$is_provisioner" != 0 ]; then
  ( cd "$target_dir" && git clone "$provisioner_repo" )
  if [ $? -ne 0 ]; then
    error "failed to clone the provisioner repository"
  fi
fi

exit 0
