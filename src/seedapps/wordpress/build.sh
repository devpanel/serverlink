#!/bin/bash

# defaults
email='no-reply@webenabled.com'

usage() {
  echo "Usage: ${0##*/} [options]

  Options:
    -h                display the usage msg


  Builds a seedapp from the latest stable Wordpress.

"
  exit 1
}

cleanup() {
  if [ -n "$vhost_created" ]; then
    temp_rm_file=$(mktemp)
    if [ $? -ne 0 ]; then
      error "unable to create temporary file"
    fi

    echo "Removing temporary vhost used ($tmp_vhost) ..."
    "$sys_dir/libexec/remove-vhost" "$tmp_vhost" - &>"$temp_rm_file"
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

getopt_flags='h'
while getopts $getopt_flags OPTN; do
  case $OPTN in
    h)
      usage
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

unset vhost_created
if ! "$sys_dir/libexec/restore-vhost" "$tmp_vhost" we://blank; then
  error "unable to create temporary vhost"
fi
vhost_created=1
trap 'cleanup' EXIT

# app:0:_:db_host $mysql_host
# app:0:_:db_port $mysql_port
# app:0:_:db_user $mysql_user
# app:0:_:db_password $mysql_password
# app:0:_:seed_app $subsystem
# app:0:_:db_name $subsystem

echo "
set app:0:_:seed_app $app_type
set app:0:_:db_name  $app_type
" | "$sys_dir/libexec/apache-metadata-handler" -q "$tmp_vhost"

su -l -s /bin/bash -c "
  set -ex

  # . $lib_f

  mysql -e 'DROP DATABASE scratch;'
  mysql -e 'DROP DATABASE test;'
  mysql -e 'CREATE DATABASE wordpress;'

  cd ~/public_html

  rm -r $tmp_vhost/  # remove public_html/vhost

  $sys_dir/bin/restore-vhost-subsystem -n -F -O config_function=download_from_cli

  $sys_dir/bin/restore-vhost-subsystem -n -F -O config_function=setup_from_cli

  rm -rf ~/public_html/$tmp_vhost.[0-9]*
  rm -f ~/.*.passwd ~/*.passwd ~/.bash_* ~/.viminfo ~/.mysql_history ~/.ssh/* \
    ~/.emacs ~/.my.cnf ~/.profile
  unset HISTFILE

" "w_$tmp_vhost"

if [ $? -ne 0 ]; then
  error "unable to cleanely setup environment"
fi

archive_file="$app_type-@archive_template_str@"
"$sys_dir/libexec/archive-vhost" "$tmp_vhost" "$archive_file"
if [ $? -eq 0 ]; then
  echo "Successfully built Wordpress seed app."
  exit 0
fi
