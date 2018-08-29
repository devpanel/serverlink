#!/bin/bash

# defaults
email='no-reply@webenabled.com'

usage() {
  echo "Usage: ${0##*/} [options] <grav_url>

  Options:
    -h                display the usage msg
    -o file.tgz       output file where to save the app


  For the grav_url parameter use url of the Grav Core + admin plugin
  package, e.g. https://getgrav.org/download/core/grav-admin/1.y.x

  Builds a seedapp from Grav.

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
app_name=grav
app_subsystem=grav

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

grav_url="$1"

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
  --from webenabled://blank --skip-mysql; then

  error "unable to create temporary vhost"
fi
vhost_created=1
trap 'cleanup' EXIT

if ! save_opts_in_vhost_config "$tmp_vhost"     \
     "app.subsystem     = $app_subsystem" ; then

  error "failed to update vhost config"
fi

su -l -s /bin/bash -c "
  set -ex

  cd ~/public_html

  rm -r $tmp_vhost/  # remove public_html/vhost

  temp_grav_dir=\$(mktemp -d)

  trap 'rm -rf \$temp_grav_dir' EXIT

  temp_grav_file=\"\$temp_grav_dir/grav.zip\"

  # download_file $grav_url \$temp_grav_file

  curl -L -o \$temp_grav_file $grav_url

  unzip -q \$temp_grav_file

  mv grav-admin $tmp_vhost

  find $tmp_vhost -type f -iname \*.php -exec chmod 644 {} \;

  find $tmp_vhost -type d -exec chmod 711 {} \;

  $sys_dir/bin/restore-vhost-subsystem -s $app_subsystem -n \
    -O config_function=setup_from_cli

  rm -rf ~/public_html/$tmp_vhost.[0-9]*
  rm -f ~/.*.passwd ~/*.passwd ~/.bash_* ~/.viminfo ~/.mysql_history ~/.ssh/* \
    ~/.emacs ~/.my.cnf ~/.profile
  unset HISTFILE
" "w_$tmp_vhost"

if [ $? -ne 0 ]; then
  error "unable to cleanely setup environment"
fi

devpanel backup vhost --vhost "$tmp_vhost" --file - >"$tmp_output_file"
if [ $? -eq 0 ]; then
  if mv -n "$tmp_output_file" "$output_file"; then
    chmod 644 "$output_file"
    echo "Successfully built Grav distribution $distro"
    echo "Saved output file to $output_file"
    exit 0
  else
    error "unable to copy $tmp_output_file to $output_file"
  fi
fi
