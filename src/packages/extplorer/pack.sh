#!/bin/bash

usage() {
  echo "Usage: ${0##*/} <version> <src_zip_url>

  Downloads and packs extplorer.
"
  exit 1
}

[ -z "$1" -o -z "$2" ] && usage

version="$1"
tar_ball_url="$2"

pkg_name="extplorer"

self_bin=$(readlink -e "$0")
if [ $? -ne 0 ]; then
  echo "Error: unable to determine self path" 1>&2
  exit 1
fi
self_dir=${self_bin%/*}
sys_dir=${self_dir%/*/*/*}

temp_dir=$(mktemp -d)

pack_dir="$temp_dir/pack"

main_pkg_dir="$pack_dir/compat/w_/public_html/cgi/$pkg_name"

src_tar_file="$temp_dir/$pkg_name-$version.tar.gz"

umask 022

mkdir -p "$main_pkg_dir"

curl -sS -o "$src_tar_file"   -L "$tar_ball_url" || \
  { st=$?; echo "Curl returned $st"; exit $st; }

# tar -zxvf "$src_tar_file" --strip-components 1 -C "$main_pkg_dir"
unzip "$src_tar_file" -d "$main_pkg_dir"

tar -zxf "$main_pkg_dir/scripts.tar.gz" -C "$main_pkg_dir"
find "$main_pkg_dir/scripts" -type d -exec chmod 711 {} \;
find "$main_pkg_dir/scripts" -type f -exec chmod 644 {} \;
rm -f "$main_pkg_dir/scripts.tar.gz"

echo 'include("devpanel_auth.php");' >> "$main_pkg_dir/config/conf.php"

cp "$self_dir/devpanel_auth.php" "$main_pkg_dir/config/"

"$sys_dir/libexec/pack-package" -s "$self_dir/setup-package" \
  -d "$pack_dir" "$pkg_name-$version.tar.gz" .

echo "Inspect: $temp_dir"
