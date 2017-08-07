#!/bin/bash

# defaults
email='no-reply@webenabled.com'

usage() {
  echo "Usage: ${0##*/} [options] <distribution> [install_profile]

  Options:
    -D version        use the specified drush version (e.g.: 6, 7, 8). By
                      default it tries to guess the best one for the
                      distribution

    -o file.tar.gz    file where to save the resulting archive

    -h                display the usage msg


  Builds a seedapp from the specified Drupal distribution.

  If the profile parameter is specified it does the initial install with it.

  Examples:
  
  \$ ${0##*/} drupal-7.50

  \$ ${0##*/} restaurant

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
[ "$1" == "-h" -o -z "$1" ] && usage

unset drush_ver output_file
getopt_flags='hD:o:'
while getopts $getopt_flags OPTN; do
  case $OPTN in
    h)
      usage
      ;;
    D)
      if [[ "$OPTARG" == [6-9] ]]; then
        drush_ver="$OPTARG"
      else
        echo "Error: unknown drush version. Valid ones are in range 6-9" 1>&2
        exit 1
      fi
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
sys_dir="${self_dir%/*/*/*}" # assuming src/seedapps/drupal

lib_f="$sys_dir/lib/functions"
if ! source "$lib_f"; then
  echo "Error: unable to import $lib_f" 1>&2
  exit 1
fi
distro="$1"

if [ -n "$2" ]; then
  inst_profile="$2"
else
  if [[ "$distro" == drupal* ]]; then
    inst_profile=standard # guessing...
  else
    if [[ "$distro" == *-[0-9]* ]]; then
      inst_profile="${distro%%-*}" # guessing again
    else
      inst_profile="$distro"
    fi
  fi
fi

if [ -z "$output_file" ]; then
  date_suffix=$(date +%b-%d-%Y-%Hh%Mm)
  if [ "$inst_profile" == "$distro" ]; then
    output_file="${distro}-${date_suffix}.tgz"
  else
    output_file="${distro}-${inst_profile}-${date_suffix}.tgz"
  fi
fi

if [ -f "$output_file" ]; then
  error "output file '$output_file' already exists."
fi

if [ -z "$drush_ver" ]; then
  # a bit more of guessing, now with drush
  if [[ "$distro" == drupal-8* ]]; then
    drush_ver=8
  elif [[ "$distro" == *-8.x-[0-9]* ]]; then
    drush_ver=8
  fi
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
set app:0:_:seed_app drupal
set app:0:_:db_name drupal
" | "$sys_dir/libexec/apache-metadata-handler" -q "$tmp_vhost"

mysql_host=$(get_vhost_key_value 'app:0:_:db_host'     $tmp_vhost)
mysql_port=$(get_vhost_key_value 'app:0:_:db_port'     $tmp_vhost)
mysql_user=$(get_vhost_key_value 'app:0:_:db_user'     $tmp_vhost)
mysql_pw=$(  get_vhost_key_value 'app:0:_:db_password' $tmp_vhost)

mysql_uri="mysql://$mysql_user:$mysql_pw@$mysql_host:$mysql_port/drupal"

su -l -s /bin/bash -c "
  set -ex
  cd ~/public_html

  rm -r $tmp_vhost/  # remove public_html/vhost
  
  drush dl --drupal-project-rename=$tmp_vhost $distro

  cd $tmp_vhost

  # if drush was passed by user input, or guessed
  if [ -n \"$drush_ver\" ]; then
    drush_cmd=\"drush-$drush_ver\"
    if hash "$drush_cmd" &>/dev/null; then
      drush_bin=\$(hash \"\$drush_cmd\"; hash -t \"\$drush_cmd\")
      hash -p \"\$drush_bin\" drush
    else
      error \"missing command $drush_cmd\"
    fi
  fi

  drush si $inst_profile --account-name=admin --account-pass=$admin_pw \
      --db-url=$mysql_uri -y

  # for drupal 6-7 set site name, e-mail, etc
  ver_str_d6_7='^[[:space:]]*Drupal[[:space:]]*version[[:space:]]*:[[:space:]]*[67]'
  if drush st | egrep -q \"\$ver_str_d6_7\"; then
    drush vset --exact --yes site_name $distro
    drush vset --exact --yes site_mail $email
    sql_mail_upd=\"UPDATE users SET mail = '$email' WHERE name = 'admin';\"
    mysql -D drupal -e \"\$sql_mail_upd\"
  else # for Drupal 8
    drush -y config-set system.site page.front $distro
    drush -y config-set update.settings notification.emails.0 $email
    sql_mail_upd=\"UPDATE users_field_data SET mail = '$email' WHERE name = 'admin';\"
    mysql -D drupal -e \"\$sql_mail_upd\"
  fi

  mysql -e 'DROP DATABASE test;' || true
  mysql -e 'DROP DATABASE scratch;'

  rm -rf ~/public_html/$tmp_vhost.[0-9]*
  rm -f ~/.*.passwd ~/*.passwd ~/.bash_* ~/.viminfo ~/.mysql_history ~/.ssh/* \
    ~/.emacs ~/.my.cnf ~/.profile
  unset HISTFILE
" "w_$tmp_vhost"

if [ $? -ne 0 ]; then
  error "unable to cleanely install drupal"
fi

"$sys_dir/libexec/archive-vhost" "$tmp_vhost" - >"$tmp_output_file"
if [ $? -eq 0 ]; then
  if mv -n "$tmp_output_file" "$output_file"; then
    chmod 644 "$output_file"
    echo "Successfully built Drupal distribution $distro"
    echo "Saved output file $output_file"
    exit 0
  else
    error "unable to move temp file $tmp_output_file to $output_file"
  fi
fi
