#!/bin/bash

usage() {
  echo "Usage: ${0##*/} <version>

  Downloads and packs phpmyadmin.
"
  exit 1
}

[ -z "$1" ] && usage

pkg_name="phpmyadmin"

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

main_pkg_dir="$pack_dir/compat/w_/public_html/cgi/phpmyadmin"

tar_ball_url="https://files.phpmyadmin.net/phpMyAdmin/$version/phpMyAdmin-$version-all-languages.tar.gz"
target_file="${tar_ball_url##*/}"

umask 022

mkdir -p "$main_pkg_dir"

curl -sS -o "$target_file"   -L "$tar_ball_url" || \
  { st=$?; echo "Curl returned $st"; exit $st; }

tar -zxvf "$target_file" --strip-components 1 -C "$main_pkg_dir"

cp "$self_dir/config.inc.php" "$self_dir/devpanel_auth.php" "$main_pkg_dir"

"$sys_dir/libexec/pack-package" -s "$self_dir/setup-package" \
  -d "$pack_dir" "$pkg_name-$version.tar.gz" .

echo "Inspect: $temp_dir"
