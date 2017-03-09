#!/bin/bash

usage() {
  echo "Usage: ${0##*/} <version>

  Downloads and packs Drush 7.
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

temp_file="$temp_dir/drush-$version.tar.gz"

pack_dir="$temp_dir/pack"

drush_url="https://github.com/drush-ops/drush/archive/$version.tar.gz"

# composer is only used to install Drush dependencies, as for Drush 7
# there's no drush.phar file distributed. composer is not installed along
# with this package, it's kept outside of the pack directory
composer_url="https://getcomposer.org/download/1.1.2/composer.phar"

compose_bin="$temp_dir/composer.phar"

drush_ver_major="${version%%.*}"

main_pkg_dir="$pack_dir/bin/packages/drush-$drush_ver_major"

umask 022

mkdir "$pack_dir"

curl -sS -o "$compose_bin" -L "$composer_url"

curl -sS -o "$temp_file"   -L "$drush_url" || \
  { st=$?; echo "Curl returned $st"; exit $st; }

chmod 755 "$compose_bin"

tar -zSxpf "$temp_file" -C "$pack_dir"

path_dir="$pack_dir/bin/.path"

mkdir -p "$pack_dir/bin/packages"
mkdir -p "$path_dir"

mv "$pack_dir/drush-$version" "$main_pkg_dir"

( cd "$main_pkg_dir" && "$compose_bin" update )

ln -s "../${main_pkg_dir#$pack_dir/bin/}/drush" "$path_dir/drush-$drush_ver_major"

"$sys_dir/libexec/pack-package" -d "$pack_dir" "drush-7-$version.tar.gz" .

echo "Inspect: $temp_dir"
