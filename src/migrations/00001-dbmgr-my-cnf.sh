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

old_get_linuxuser_vhost_dir() {
  echo "$DEVPANEL_HOME/config/key_value/linuxuser-vhost"
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

old_is_valid_vhost_string() {
  local string="$1"

  if [ -z "$string" ]; then
    echo "$FUNCNAME(): received an empty vhost string" 1>&2
    return 1
  fi

  local vhost_regex='^[a-z0-9]+[a-z0-9-]+$'

  if [[ "$string" =~ $vhost_regex ]]; then
    return 0
  else
    return 1
  fi
}

old_vhost_exists() {
  local test_str="$1"

  if [ -z "$test_str" ]; then
    echo "$FUNCNAME(): received an empty vhost string" 1>&2
    return 1
  fi

  if ! old_is_valid_vhost_string "$test_str"; then
    echo "$FUNCNAME(): invalid format of vhost name" 1>&2
    return 1
  fi

  local config_dir="$DEVPANEL_HOME/config/vhosts/$test_str"
  if [ -d "$config_dir" ]; then
    return 0
  else
    return 1
  fi
}

old_get_vhost_from_linuxuser() {
  local user="${1:-$USER}"
  local vhost

  if [ -z "$user" ]; then
    echo "$FUNCNAME(): unable to get username information" 1>&2
    return 1
  fi

  local map_dir map_link
  map_dir=$(old_get_linuxuser_vhost_dir)
  map_link="$map_dir/$user"
  if [ -L "$map_link" ]; then
    old_deref_contents "$map_link"
    return $?
  else
    # for servers installed before the $map_link was created
    if [ ${#user} -gt 2 -a "${user:0:2}" == w_ ]; then
      vhost=${user#w_}
      if old_vhost_exists "$vhost"; then
        echo "$vhost"
        return 0
      fi
    fi
  fi

  return 1
}

old_get_vhost_key_value() {
  local key="$1"
  local vhost="$2"
  local value=""

  if [ -z "$vhost" ]; then
    if ! vhost=$(old_get_vhost_from_linuxuser); then
      echo "$FUNCNAME(): missing vhost, please specify it" 1>&2
      return 1
    fi
  fi

  local key_link="$DEVPANEL_HOME/config/vhosts/$vhost/$key"

  old_deref_contents "$key_link"
}

old_get_1st_level_field_value_from_app() {
  local vhost="$1"
  local field="$2"
  local prefix="app:0:_"
  local value

  value=$(old_get_vhost_key_value "$prefix:$field" "$vhost" 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo -n "$value"
    return 0
  else
    return 1
  fi
}

old_get_mysql_db_port_from_vhost() {
  local vhost="$1"

  old_get_1st_level_field_value_from_app "$vhost" db_port
}

old_get_mysql_db_password_from_vhost() {
  local vhost="$1"

  old_get_1st_level_field_value_from_app "$vhost" db_password
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
  port=$(old_get_mysql_db_port_from_vhost "$vhost" )
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

  w_pass=$(old_get_mysql_db_password_from_vhost "$vhost" )
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
