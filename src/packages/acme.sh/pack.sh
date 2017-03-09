#!/bin/bash

usage() {
  echo "Usage: ${0##*/} <version>

  Downloads and packs acme.sh
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

temp_file="$temp_dir/acme.sh-$version.tar.gz"

pack_dir="$temp_dir/pack"

acme_url="https://github.com/Neilpang/acme.sh/archive/$version.tar.gz"

main_pkg_dir="$pack_dir/bin/packages/acme.sh"

umask 022

mkdir "$pack_dir"

curl -sS -o "$temp_file"   -L "$acme_url" || \
  { st=$?; echo "Curl returned $st"; exit $st; }

tar -zSxpf "$temp_file" -C "$pack_dir"

mkdir -p "$pack_dir/bin/packages"

cron_dir="$pack_dir/bin/packages/cron.d/cron.daily"
mkdir -p "$cron_dir"

mv "$pack_dir/acme.sh-$version" "$main_pkg_dir"

cp $self_dir/acme-cron "$cron_dir"

"$sys_dir/libexec/pack-package" -d "$pack_dir" "acme.sh-$version.tar.gz" .
