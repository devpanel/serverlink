#!/bin/bash

usage() {
  echo "Usage: ${0##*/} <distro> [output_file]

  Builds a new VM based on the specified distribution and packages it into
  the specified output file.
"
  exit 1
}

error() {
  local msg="$1"
  local exit_code="${2:-1}"

  [ -n "$msg" ] && echo "Error: $msg" 1>&2

  if [ "$exit_code" == - ]; then
    return 1
  else
    exit $exit_code
  fi
}

cleanup() {
  local ex=$?

  cd /

  if [ -d "$temp_dir" ]; then
    if [ -d "$temp_dir/.vagrant" ]; then
      vagrant destroy -f
    fi

    rm -rf "$temp_dir"
  fi

  if [ $ex -eq 0 ]; then
    echo
    echo
    echo "Successfully created box file at $box_file."
  fi
}

# main

trap cleanup EXIT

self_bin=`readlink -e "$0"`
if [ $? -ne 0 ]; then
  echo "Error: unable to get self path" 1>&2
  exit 1
fi

self_dir="${self_bin%/*}"

[ -z "$1" -o -z "$2" ] && usage

distro="$1"
box_file="${2:-$distro-$(date +%b-%d-%Y)-$RANDOM.box}"

vgr_build_file="$self_dir/Vagrantfile.build.$distro"
vgr_package_file="$self_dir/Vagrantfile.package.$distro"

if [ ! -f "$vgr_build_file" ]; then
  error "missing build file '$vgr_build_file'"
elif [ ! -f "$vgr_package_file" ]; then
  error "missing package file '$vgr_package_file'"
fi

if [ -e "$box_file" ]; then
  error "box file '$box_file' already exists."
fi

if ! temp_dir=$(mktemp -d); then
  error "unable to create temporary directory"
fi

if ! cp -f "$vgr_build_file" "$temp_dir/Vagrantfile"; then
  error "unable to copy '$vgr_build_file' to $temp_dir"
fi

export VAGRANT_CWD="$temp_dir"

vagrant up
if [ $? -ne 0 ]; then
  error "unable to create vagrant VM"
fi

vagrant ssh -- 'curl -sS -L https://www.devpanel.com/install.sh | sudo -i bash -s'
if [ $? -ne 0 ]; then
  error "unable to make a clean install of devPanel software"
fi

vagrant package --vagrantfile "$vgr_package_file" --output "$box_file"
if [ $? -ne 0 ]; then
  error "failed to create box file."
fi
