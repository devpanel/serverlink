#!/bin/bash

usage() {
  echo "Usage: ${0##*/} <version>

  Downloads and packs the phar file of wp-cli.
"
  exit 1
}

[ -z "$1" ] && usage

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

path_dir="$pack_dir/bin/.path"

phar_url="https://github.com/wp-cli/wp-cli/releases/download/v$version/wp-cli-$version.phar"

main_pkg_dir="$pack_dir/bin/packages/wp-cli"

target_file="$main_pkg_dir/wp-cli.phar"

umask 022

mkdir -p "$path_dir"
mkdir -p "$main_pkg_dir"

curl -sS -o "$target_file"   -L "$phar_url" || \
  { st=$?; echo "Curl returned $st"; exit $st; }

chmod 755 "$target_file"

ln -s "${target_file##*/}" "$main_pkg_dir/wp-cli"

ln -s "../${main_pkg_dir#$pack_dir/bin/}/wp-cli" "$path_dir/wp-cli"
ln -s "../${main_pkg_dir#$pack_dir/bin/}/wp-cli" "$path_dir/wp"

"$sys_dir/libexec/pack-package" -d "$pack_dir" "wp-cli-$version.tar.gz" .

echo "Inspect: $temp_dir"
