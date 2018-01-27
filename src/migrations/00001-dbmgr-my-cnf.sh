#!/bin/bash

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

for vhost in $(get_list_of_vhosts); do
  get_linux_username_from_vhost "$vhost" && \
  w_user="$_dp_value" || continue
  b_user="b_${w_user#w_}"

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
