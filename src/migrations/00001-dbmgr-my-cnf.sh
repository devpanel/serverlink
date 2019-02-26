#!/bin/bash

old_deref_contents() {
  local path="$1"

  local value=""

  if [ -L "$path" ]; then
    value=`readlink "$path"`
  elif [ -f "$path" ]; then
    value=`cat "$path"`
  elif [ ! -e "$path" ]; then
    echo "$FUNCNAME(): path doesn't exist $path" 1>&2
    return 1
  else
    echo "$FUNCNAME(): don't know how to de-reference path $path" 1>&2
    return 1
  fi

  echo -n "$value"
}

old_get_key_value_from_vhost() {
  local key="$1"
  local vhost="${2:-$_dp_vhost}"

  old_deref_contents \
    "$DEVPANEL_HOME/config/vhosts/$vhost/$key" 2>/dev/null
}

old_get_linux_username_from_vhost() {
  local vhost="$1"

  local user

  if user=$(old_get_key_value_from_vhost \
              apache_vhost:_:linux_user "$vhost"); then
    :
  else
    user="w_$vhost"
  fi

  echo "$user"
}

get_mysql_root_password() {
  local instance="$1"
  local output

  output=$(egrep -m 1 "^$instance:" "$dbmgr_dir/config/db-shadow.conf" )
  if [ $? -ne 0 ]; then
    echo "$FUNCNAME(): unable to get root password for '$instance'" 1>&2
    return 1
  fi

  echo "$output" | cut -d: -f 9
}

old_get_list_of_vhosts() {
  local vhost_config_dir="$DEVPANEL_HOME/config/vhosts"
  local vhost vhost_dir
  local -a vhosts_ar=()

  if [ ! -d "$vhost_config_dir" ]; then
    echo "$FUNCNAME(): missing config dir $vhost_config_dir" 1>&2
    return 1
  fi

  for vhost_dir in "$vhost_config_dir/"*; do
    [ ! -d "$vhost_dir" ] && continue
    vhost=${vhost_dir##*/}
    vhosts_ar+=( "$vhost" )
  done

  if [ ${#vhosts_ar[*]} -le 0 ]; then
    return 0
  else
    echo "${vhosts_ar[@]}"
  fi
}

update_ini_bin="$sys_dir/bin/update-ini-file"
if [ -f "$update_ini_bin" -a -x "$update_ini_bin" ]; then
  hash -p "$update_ini_bin" update-ini-file
else
  echo "Error: missing executable file '$update_ini_bin'" 1>&2
  exit 1
fi

dbmgr_dir="$sys_dir/compat/dbmgr"
dbmgr_bin_dir="$dbmgr_dir/current/bin"
dbmgr_my_cnf_dir="$dbmgr_dir/config/mysql"

for vhost in $(old_get_list_of_vhosts); do
  if w_user=$(old_get_linux_username_from_vhost "$vhost"); then
    b_user="b_${w_user#w_}"
  else
    continue
  fi

  my_cnf_dir="$dbmgr_my_cnf_dir/$b_user"
  if [ ! -d "$my_cnf_dir" ]; then
    mkdir -p -m 750 "$my_cnf_dir"
  fi
  chgrp "$w_user" "$my_cnf_dir"
  usermod -a -G "$w_user" "$b_user"

  host="127.0.0.1"
  port=$(get_mysql_db_port_from_vhost "$vhost" )
  root_password=$(get_mysql_root_password "$b_user" )
  socket="/home/clients/databases/$b_user/mysql/mysql.sock"

  root_my_cnf="$my_cnf_dir/root.client.cnf"
  root_cnf_str=""
  if [ ! -f "$root_my_cnf" ]; then
    root_cnf_str+="client.socket = $socket"$'\n'
    root_cnf_str+="client.user = root"$'\n'
    root_cnf_str+="client.password = $root_password"$'\n'

    touch "$root_my_cnf"
    chgrp "$b_user" "$root_my_cnf"
    chmod 640 "$root_my_cnf"

    echo "$root_cnf_str" | update-ini-file "$root_my_cnf"
  fi

  w_pass=$(get_mysql_db_password_from_vhost "$vhost" )
  web_my_cnf="$my_cnf_dir/web.client.cnf"
  web_cnf_str=""
  if [ ! -f "$web_my_cnf" ]; then
    web_cnf_str+="client.host = $host"$'\n'
    web_cnf_str+="client.port = $port"$'\n'
    web_cnf_str+="client.user = $w_user"$'\n'
    web_cnf_str+="client.password = $w_pass"$'\n'

    touch "$web_my_cnf"
    chgrp "$w_user" "$web_my_cnf"
    chmod 640 "$web_my_cnf"

    echo "$web_cnf_str" | update-ini-file "$web_my_cnf"
  fi
done
