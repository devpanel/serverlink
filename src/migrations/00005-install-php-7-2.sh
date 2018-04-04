#!/bin/bash

if [ -d /etc/php/7.2 -o -d /etc/opt/remi/php72 ]; then
  exit 0
fi

tmp_pkg_list=$(mktemp) || exit $?
trap 'rm -f "$tmp_pkg_list"' EXIT

in_pkg_list="$lamp__paths__distro_defaults_dir/distro-packages.txt"

if egrep 'php7\.?2' "$in_pkg_list" > "$tmp_pkg_list"; then
  install_distro_pkgs "$conf__distro" "$conf__distro_version" "$tmp_pkg_list"
  skel_dir="$sys_dir/install/skel/$conf__distro/$conf__distro_version"
  if [ "$conf__distro" == ubuntu -o "$conf__distro" == debian ]; then
    php_dir="$skel_dir/etc/php/7.2"
    if [ -d "$php_dir" ]; then
      cp -r "$php_dir" /etc/php/
    fi
  elif [ "$conf__distro" == centos ]; then
    php_dir="$skel_dir/etc/opt/remi/php72"
    if [ -d "$php_dir" ]; then
      cp -r "$php_dir"  /etc/opt/remi/
    fi
  fi
fi

exit 0
