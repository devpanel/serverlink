#!/bin/bash

usage() {
  echo "Usage: ${0##*/} <version>

  Compiles and packs suexec binaries.
"
  exit 1
}

[ -z "$1" ] && usage

# exit on any error
set -e

version="$1"

self_bin=$(readlink -e "$0")
if [ $? -ne 0 ]; then
  echo "Error: unable to determine self path" 1>&2
  exit 1
fi
self_dir=${self_bin%/*}
sys_dir=${self_dir%/*/*/*}

temp_dir=$(mktemp -d)

pack_dir="$temp_dir/pack"

main_pkg_dir="$pack_dir/compat/suexec"

src_dir="$sys_dir/compat/src/suexec/suexec-$version"
if [ ! -d "$src_dir" ]; then
  echo "Error: didn't find directory '$src_dir'" 1>&2
  exit 1
fi

umask 022

mkdir -p "$path_dir"
mkdir -p "$main_pkg_dir"

( cd "$src_dir" && make && make install-all DESTDIR="$pack_dir" )
if [ $? -ne 0 ]; then
  echo
  echo "Error: failed to compile suexec binaries" 1>&2
fi

"$sys_dir/libexec/pack-package" -d "$pack_dir" "suexec-$version.tar.gz" .

echo "Inspect: $temp_dir"
