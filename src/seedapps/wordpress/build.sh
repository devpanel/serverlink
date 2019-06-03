#!/bin/bash

# defaults
email='no-reply@webenabled.com'

usage() {
  echo "Usage: ${0##*/} [options]

  Options:
    -o file.tar.gz    file where to save the resulting archive
    -h                display the usage msg


  Builds a seedapp from the latest stable Wordpress.

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
app_type=wordpress

unset archive_file
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

self_bin=`readlink -e "$0"`
if [ $? -ne 0 ]; then
  echo "Error: unable to get self path" 1>&2
  exit 1
fi

self_dir="${self_bin%/*}"
sys_dir="${self_dir%/*/*/*}" # assuming src/seedapps/<app>

if [ -z "$output_file" ]; then
  date_suffix=$(date +%b-%d-%Y-%Hh%mm)
  output_file="${app_type}-${date_suffix}.tgz"
fi

if [ -f "$output_file" ]; then
  error "output file '$output_file' already exists."
fi

lib_f="$sys_dir/lib/functions"
if ! source "$lib_f"; then
  echo "Error: unable to import $lib_f" 1>&2
  exit 1
fi

passgen_bin="$sys_dir/bin/passgen"
if [ ! -f "$passgen_bin" -o ! -x "$passgen_bin" ]; then
  error "missing executable $passgen_bin"
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
       --from webenabled://blank --dedicated-mysql; then

  error "unable to create temporary vhost"
fi
vhost_created=1
trap 'cleanup' EXIT

if ! save_opts_in_vhost_config "$tmp_vhost"     \
     "app.subsystem     = $app_type"            \
     "app.database_name = $app_type"; then

  error "failed to update vhost config"
fi

if ! load_vhost_config "$tmp_vhost"; then
  error "failed to load configuration of new vhost"
fi

su -l -s /bin/bash -c "
  umask 022
  set -e

  . $sys_dir/lib/functions

  load_devpanel_config 

  load_vhost_config $tmp_vhost

  doc_root=\"\$v__vhost__document_root\"

  rm -rf \$doc_root

  mysql -e 'DROP DATABASE scratch;'
  mysql -e 'DROP DATABASE test;'
  mysql -e 'CREATE DATABASE wordpress;'

  mkdir -m 751 \$doc_root

  $sys_dir/bin/restore-vhost-subsystem -n -F -O config_function=download_from_cli

  $sys_dir/bin/restore-vhost-subsystem -n -F -O config_function=setup_from_cli

  rm -rf \$doc_root.[0-9]*
  rm -f ~/.*.passwd ~/*.passwd ~/.bash_* ~/.viminfo ~/.mysql_history ~/.ssh/* \
    ~/.emacs ~/.my.cnf ~/.profile
  unset HISTFILE

" "$v__vhost__linux_user"

if [ $? -ne 0 ]; then
  error "unable to cleanely setup environment"
fi

devpanel backup vhost --vhost "$tmp_vhost" --file - >"$tmp_output_file"
if [ $? -eq 0 ]; then
  if mv -n "$tmp_output_file" "$output_file"; then
    chmod 644 "$output_file"
    echo "Successfully built Wordpress seed app."
    exit 0
  else
    error "unable to copy temp file $tmp_output_file to $output_file"
  fi
fi
