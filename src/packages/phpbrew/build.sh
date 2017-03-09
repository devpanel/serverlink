#!/bin/bash
trap_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo
    echo "Error: compilation failed: $phase_desc"
  fi
}

usage() {
  echo "Usage: ${0##*/} <version>

  Compiles the specified PHP version. Where version can be either the
  series (e.g. 5.5, 5.6) or a specific version in the series (e.g. 5.6.19).
"
  exit 1
}

get_series_from_version() {
  local ver="$1"
  local series

  series=${ver%.*}

  echo "$series"
}

escape_series_str() {
  local orig="$1"
  local escaped

  escaped=${orig//./\\.}

  echo "$escaped"
}

get_latest_version_on_series() {
  local series="$1"
  local series_esc raw_line first_ver_raw version

  series_esc=$(escape_series_str "$series")
  raw_line=$(phpbrew known -o | egrep ^$series_esc:)
  first_ver_raw=$(echo "$raw_line" | cut -d ' ' -f 2)
  version=${first_ver_raw%,}

  echo "$version"
}

series_regex='^[0-9]\.[0-9]$'
version_regex='^[0-9]\.[0-9]\.[0-9][0-9]$'

# main

[ $# -eq 0 -o -z "$1" ] && usage

self_bin=$(readlink -e "$0")
if [ $? -ne 0 ]; then
  echo "Error: unable to determine self path." 1>&2
  exit 1
fi
self_dir=${self_bin%/*}
sys_dir=${self_dir%/*/*/*}

unset build_type series version

input_version="$1"
if [[ "$input_version" =~ $series_regex ]]; then
  build_type="series"
  series="$input_version"
elif [[ "$input_version" =~ $version_regex ]]; then
  build_type="specific_version"
  series=$(get_series_from_version "$input_version")
  version="$input_version"
else
  echo "Error: unknown version format specified." 1>&2
  exit 1
fi

trap trap_exit EXIT

set -e

umask 022

phase_desc="installing phpbrew"
phpbrew_root="/opt/webenabled/bin/packages/phpbrew"
if [ ! -d "$phpbrew_root" ]; then
  mkdir -p "$phpbrew_root"
fi

if ! hash phpbrew &>/dev/null; then
  # git clone https://github.com/phpbrew/phpbrew.git
  curl -sS -L -o /usr/local/bin/phpbrew \
    https://github.com/phpbrew/phpbrew/raw/master/phpbrew

  chmod 755 /usr/local/bin/phpbrew
fi

phpbrew_init_file="$HOME/.phpbrew/init"
if [ ! -f "$phpbrew_init_file" ]; then
  phpbrew init
  echo export PHPBREW_ROOT=$phpbrew_root >~/.phpbrew/init
fi

phpbrew_bashrc="$HOME/.phpbrew/bashrc"
[ -f "$phpbrew_bashrc" ] && source "$phpbrew_bashrc"

phase_step="updating PHP brew database"
phpbrew update --old

if [ "$build_type" == series ]; then
  version=$(get_latest_version_on_series "$series")
fi

opts_file_for_series="$self_dir/phpbrew-opts-$series.txt"
opts_file_for_version="$self_dir/phpbrew-opts-$version.txt"

declare -a compile_args_ar=()
if [ -f "$opts_file_for_version" ]; then
  opts_file="$opts_file_for_version"
elif [ -f "$opts_file_for_series" ]; then
  opts_file="$opts_file_for_series"
else
  compile_args_ar+=( +default )
fi

# TODO: deal with build dir
# TODO: deal with empty compile file
if [ -n "$opts_file" ]; then
  while read option_line; do
    [ -z "$option_line" -o "${option_line:0:1}" == "#" ] && continue

    compile_args_ar+=( $option_line )
  done <"$opts_file"
fi

#phase_step="creating temp build_dir"
#tmp_build_dir=$(mktemp -d)
#
#phase_step="populating \$tmp_build_dir"
#mkdir "$tmp_build_dir/build"
#mkdir "$tmp_build_dir/tmp"
#ln -s $PHPBREW_ROOT/distfiles $tmp_build_dir

if [ ! -e /usr/include/freetype2/freetype ]; then
  phase_step="fixing freetype2 path for ./configure"
  ln -s /usr/include/freetype2 /usr/include/freetype2/freetype # 5.3
fi

phase_step="compiling PHP"

phpbrew install $version "${compile_args_ar[@]}"

phase_step="stripping binaries"

php_version_dir="$phpbrew_root/php/php-$version"
php_fpm="$php_version_dir/sbin/php-fpm"
strip "$php_version_dir/bin/php" 
strip "$php_version_dir/bin/php-cgi"

[ -x "$php_fpm" ] && strip "$php_fpm"

phpbrew use php-$version

if [ "${version:0:1}" == 5 ]; then
  phase_step="installing imagemagick extension"
  phpbrew ext install imagick

  phase_step="installing memcached extension"
  phpbrew ext install memcached -- --disable-memcached-sasl
fi

# bin/packages/phpbrew/php/php-$version/var/db
php_ini_dir="$php_version_dir/var/db"
phase_step="creating PHP ini dir..."
[ ! -d "$php_ini_dir" ] && mkdir "$php_ini_dir"

ln -s ../../../install/utils/php.ini.d/$series--php.ini \
  "$php_ini_dir/devpanel.ini"

phase_step="creating dir \$pkg_tmp_dir"
pkg_tmp_dir=$(mktemp -d)

phase_step="creating dirs pkg-files/ and setup/ on \$pkg_tmp_dir"
mkdir $pkg_tmp_dir/{pkg-files,setup}

phase_step="copying $php_version_dir to pkg-files/"
tar -cSpf - -C "$sys_dir" ${php_version_dir#$sys_dir/} | tar -xpf - \
  -C "$pkg_tmp_dir/pkg-files"

final_pkg_file="php-$version.tar.gz"
phase_step="creating final package $final_pkg_file"
tar -zpScf "$final_pkg_file" -C "$pkg_tmp_dir" ./pkg-files ./setup
if [ $? -eq 0 ]; then
  echo "Successfully created file $final_pkg_file ."
fi

exit 0
