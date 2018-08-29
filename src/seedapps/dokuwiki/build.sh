#!/bin/bash

usage() {
  echo "Usage: ${0##*/} [options] <source-file.tar.gz>

  Options:
    -h                display the usage msg
    -o output.tar.gz  output file with the seed app


  This script creates the seed app for Dokuwiki from the source-file.tar.gz
  file containing the source code for Dokuwiki's website.

"
  exit 1
}

cleanup() {
  [ -f "$tmp_output_file" ] && rm -f "$tmp_output_file"

  if [ -n "$vhost_created" ]; then
    temp_rm_file=$(mktemp)
    if [ $? -ne 0 ]; then
      error "unable to create temporary file"
    fi

    echo "Removing temporary vhost used ($tmp_vhost) ..."
    devpanel remove vhost --vhost "$tmp_vhost" --file - &>"$temp_rm_file"
    if [ $? -eq 0 ]; then
      rm -f "$temp_rm_file"
      exit 0
    else
      echo "Warning: unable to cleanup temp vhost. Msgs logged to $temp_rm_file" 1>&2
    fi
  fi
}

# main
app_name=dokuwiki
app_subsystem=dokuwiki

unset output_file
getopt_flags='ho:'
while getopts $getopt_flags OPTN; do
  case $OPTN in
    h)
      usage
      ;;
    o)
      output_file="$OPTARG"
      ;;
    *)
      exit 1
      ;;
  esac
done
[ $OPTIND -gt 1 ] && shift $(( $OPTIND - 1 ))

[ -z "$1" ] && usage

source_file="$1"

self_bin=`readlink -e "$0"`
if [ $? -ne 0 ]; then
  echo "Error: unable to get self path" 1>&2
  exit 1
fi

self_dir="${self_bin%/*}"
sys_dir="${self_dir%/*/*/*}" # assuming src/seedapps/<app>

lib_f="$sys_dir/lib/functions"
if ! source "$lib_f"; then
  echo "Error: unable to import $lib_f" 1>&2
  exit 1
fi

if [ -f "$source_file" ]; then
  if ! tar -ztf "$source_file" >/dev/null; then
    error "failed to validate file '$source_file' as a .tar.gz file"
  fi
else
  error "missing file '$source_file'"
fi

passgen_bin="$sys_dir/bin/passgen"
if [ ! -f "$passgen_bin" -o ! -x "$passgen_bin" ]; then
  error "missing executable $passgen_bin"
fi

if [ -z "$output_file" ]; then
  date_suffix=$(date +%b-%d-%Y-%Hh%mm)
	output_file="${app_name}-${date_suffix}.tgz"
fi

if [ -f "$output_file" ]; then
  error "output file '$output_file' already exists."
fi

tmp_vhost_str1=$($passgen_bin)
if [ $? -ne 0 ]; then
  error "unable to generate vhost string"
fi
tmp_vhost_str2="${tmp_vhost_str1:0:6}"
tmp_vhost="${tmp_vhost_str2,,}"

admin_pw=$( $passgen_bin )
if [ $? -ne 0 ]; then
  error "unable to generate admin password"
fi

tmp_output_file=$(mktemp)
if [ $? -ne 0 ]; then
  error "unable to create temporary file"
fi

load_devpanel_config || exit $?

unset vhost_created
if ! devpanel create vhost --vhost "$tmp_vhost" \
       --from webenabled://blank --skip-mysql ; then
  error "unable to create temporary vhost"
fi
vhost_created=1
trap 'cleanup' EXIT

load_vhost_config "$tmp_vhost" || exit $?

doc_root=$(get_docroot_from_vhost "$tmp_vhost")
get_linux_username_from_vhost "$tmp_vhost" && \
web_user="$_dp_value"
web_group="virtwww"
rm -rf "$doc_root"
mkdir -m 751 "$doc_root"
tar -zxf "$source_file" --no-same-owner --strip-components 1 -C "$doc_root"
cp -r -v "$self_dir/conf/." "$doc_root/conf/"
chmod 600 "$doc_root/conf/"*auth*.php

chown -R "$web_user":"$web_group" "$doc_root"

if ! save_opts_in_vhost_config "$tmp_vhost"     \
      "app.subsystem     = $app_subsystem" ; then

  error "failed to update vhost config"
fi

su -l -s /bin/bash -c "
  set -ex

  find $doc_root -type f -iname \*.php -exec chmod 644 {} \;

  find $doc_root -type d -exec chmod 711 {} \;

  rm -rf ~/public_html/$tmp_vhost.[0-9]*
  rm -f ~/.*.passwd ~/*.passwd ~/.bash_* ~/.viminfo ~/.mysql_history ~/.ssh/* \
    ~/.emacs ~/.my.cnf ~/.profile
  unset HISTFILE
" "$web_user"

if [ $? -ne 0 ]; then
  error "unable to cleanely setup environment"
fi

devpanel backup vhost --vhost "$tmp_vhost" --file - >"$tmp_output_file"
if [ $? -eq 0 ]; then
  if mv -n "$tmp_output_file" "$output_file"; then
    chmod 644 "$output_file"
    echo "Successfully built $app_subsystem distribution $distro"
    echo "Saved output file to $output_file"
    exit 0
  else
    error "unable to copy $tmp_output_file to $output_file"
  fi
fi
