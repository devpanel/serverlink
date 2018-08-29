#!/bin/bash

apache_vhost_create() {
  local arg
  local vhost vhost_home doc_root linux_user linux_group
  local config_dir vhost_cache_dir vhost_log_dir
  local domains_txt base_domain
  local -a adduser_args_ar=()

  while [ -n "$1" -a "${1:0:1}" == - ]; do
    arg="$1"
    case "$arg" in
      --domain)
        [ -z "$2" ] && { error_missing_value "$arg" ; return $?; }
        if ! is_valid_domain_string "$2"; then
          echo "$FUNCNAME(): error, invalid domain string '$2'" 1>&2
          return 1
        fi

        if ! is_word_in_string "$2" "$domains_txt"; then
          [ -n "$domains_txt" ] && domains_txt+=" "
          domains_txt+="$2"
        fi

        shift 2
        ;;

      *)
        echo "$FUNCNAME(): error, unknown option '$arg'" 1>&2
        return 1
        ;;
    esac
  done

  if [ -z "$1" ]; then
    echo "$FUNCNAME(): error, missing vhost name" 1>&2
    return 1
  fi

  vhost="$1"

  if vhost_exists "$vhost"; then
    echo "$FUNCNAME(): vhost already exists" 1>&2
    return 1
  fi

  if generate_linux_username_for_vhost "$vhost"; then
    linux_user="$_dp_value"
    linux_group="$linux_user"
    vhost_home="$lamp__apache_paths__virtwww_homedir/$linux_user"
    doc_root="$vhost_home/public_html/$vhost"

    # Create a new user dedicated for the vhost files
    #
    # set the apache exec group as the user's primary group, so that all
    # executable files get the right group ownership for suexec execution
    adduser_args_ar=( --home "$vhost_home" )
    if [ "$conf__distro" == centos ]; then
      adduser_args_ar+=( -c "vhost $vhost,,," -g "$lamp__apache__exec_group" )
    else
      adduser_args_ar+=( --disabled-password --gecos "vhost $vhost,,," \
                          --ingroup "$lamp__apache__exec_group" )
    fi
    adduser_args_ar+=( "$linux_user" )

    adduser "${adduser_args_ar[@]}"
    if [ $? -eq 0 ]; then
      ln -s "$vhost" "$lamp__paths__user_vhost_map/$linux_user"
    else
      echo "$FUNCNAME(): failed to add user '$linux_user'" 1>&2
      return 1
    fi

    if [ "$conf__distro" == centos ]; then
      # for CentOS, set a hash value for it not to block the account
      # and break vhost re-enablings (after a disable) when the user didn't
      # setup a password for the account (shadow-utils complains about
      # password-less accounts)
      echo "${linux_user}:x" | chpasswd -c NONE
    fi

    if groupadd "$linux_group"; then
      usermod -G "$linux_group" "$linux_user"
    else
      error "failed to create group '$linux_group'" -
      return $?
    fi
  else
    echo "$FUNCNAME(): unable to generate username" 1>&2
    return 1
  fi

  config_dir="$lamp__paths__vhosts_config_dir/$vhost"
  if ! mkdir -m 750 "$config_dir"; then
    echo "$FUNCNAME(): unable to create directory '$config_dir'"
    return 1
  fi

  if ! mkdir -m 750 "$config_dir/"{apache,mysql,ssl}; then
    echo "$FUNCNAME(): unable to create auxiliary dirs" 1>&2
    return 1
  fi

  touch "$config_dir/config.ini"
  chmod 640 "$config_dir/config.ini"
  chgrp -R "$linux_group" "$config_dir"

  vhost_cache_dir="$sys_dir/var/cache/vhost/$vhost"
  mkdir -m 2750 $vhost_cache_dir
  chown root:$linux_group $vhost_cache_dir

  # apache log dir setup
  vhost_log_dir="$lamp__apache_paths__vhost_logs_dir/$linux_user"
  mkdir -p -m 0750 "$vhost_log_dir"
  touch "$vhost_log_dir/"{access,error}_log
  touch "$vhost_log_dir/$vhost-"{access,error}_log
  chmod 0640 "$vhost_log_dir/"{access,error}_log
  chmod 0640 "$vhost_log_dir/$vhost-"{access,error}_log
  chgrp -R "$linux_group" "$vhost_log_dir"
  # // apache log dir setup

  # suexec cgi permissions
  {
    "$sys_dir/compat/suexec/chcgi" "$linux_user" +0
    "$sys_dir/compat/suexec/chcgi" "$linux_user" +2
    "$sys_dir/compat/suexec/chcgi" "$linux_user" +7
  } >/dev/null

  # initialize quota (for shared systems)
  hash edquota &>/dev/null && edquota -p w_ "$linux_user"

  # create the basic directory structure
  chgrp -- $lamp__apache__group "$vhost_home"
  su - -c "
    chmod 0710 \"$vhost_home\"
    mkdir -m 0711 ~/.webenabled ~/.webenabled/private
    mkdir -p \"$vhost_home/bin\"
    chmod 0700 \"$vhost_home/bin\"
    mkdir -p -m 0711 \"$vhost_home/public_html\"
    chmod 0711 \"$vhost_home/public_html\"
    mkdir -m 0755 -p \"$doc_root\"
    mkdir -m 0755 -p \"$vhost_home/public_html/gen\"
    mkdir -m 0711 -p \"$vhost_home/public_html/gen/archive\"
    rm -f \"$vhost_home/logs\"
    ln -s \"$vhost_log_dir\" \"$vhost_home/logs\"

    [ ! -d ~/.ssh ] && mkdir -m 700 ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys

    $sys_dir/bin/gen-vhost-ssh-priv-key -q -o

    mkdir -m 700 ~/.devpanel
        " -s /bin/bash "$linux_user"
  # // create the basic directory structure

  base_domain="$vhost.$lamp__apache_vhosts__virtwww_domain"
  if [ -n "$domains_txt" ]; then
    domains_txt="$base_domain $domains_txt"
  else
    domains_txt="$base_domain"
  fi

  local -a vhost_opts_ar=(
    "vhost.base_domain = $base_domain"     \
    "vhost.domains = $domains_txt"         \
    "vhost.document_root = $doc_root"      \
    "vhost.linux_user = $linux_user"         \
    "vhost.enabled = yes"                  \
    "vhost.server_name = $base_domain"
  )

  save_opts_in_vhost_config "$vhost" "${vhost_opts_ar[@]}"
  if [ $? -eq 0 ]; then
    set_global_var v__vhost__linux_user "$linux_user"
    echo "Successfully created apache vhost $vhost."
  else
    echo "$FUNCNAME(): failed to save config for '$vhost'"
    return 1
  fi
}

apache_vhost_remove() {
  local vhost="$1"

  local apache_log_dir vhost_config_dir vhost_cache_dir
  local removed_vhosts_dir removed_dir archived_files_dir
  local user_web
  local date_ts

  apache_base_log_dir="$lamp__apache_paths__vhost_logs_dir"

  user_web="$v__vhost__linux_user"

  date_ts=`date  +'%b-%d-%Y-%Hh%Mmin'`
  if [ $? -ne 0 -o -z "$date_ts" ]; then
    error "unable to get current date" -
    return $?
  fi

  vhost_config_dir="$v__vhost__config_dir"
  vhost_cache_dir="$sys_dir/var/cache/vhost/$vhost"
  archived_files_dir="$v__vhost__archives_dir"
  apache_log_dir="$apache_base_log_dir/$user_web"
  removed_vhosts_dir="$conf__paths__data_dir/removed_vhosts"
 
  # Removing web related stuff
  echo "Removing web things..."

  if [ -n "$apache_log_dir" -a -d "$apache_log_dir" ]; then
    echo "Removing apache log files"
    rm_rf_safer "$apache_log_dir"
  fi

  if [ -d "$vhost_cache_dir" ]; then
    echo "Removing cache dir $vhost_cache_dir"
    rm_rf_safer "$vhost_cache_dir"
  fi

  if [ -d "$archived_files_dir" ]; then
    if [ ! -d "$removed_vhosts_dir" ]; then
      mkdir -p -m 700 "$removed_vhosts_dir"
    fi

    removed_dir="$removed_vhosts_dir/$vhost--$date_ts.$RANDOM"
    echo "Removing vhost config dir"
    if mv "$vhost_config_dir" "$removed_dir"; then
      chmod 700 "$removed_dir"
      chown 0:0 "$removed_dir"  # chown directory to root:root
      find "$removed_dir" -type f -exec chmod 0600 "{}" \; \
                                           -exec chown 0:0 "{}" \;

      mv "$archived_files_dir" "$removed_dir/archives"

      crontab -l -u "$user_web" >$removed_dir/crontab

      chown -R 0:0 "$removed_dir"  # chown directory recursively to root:root
    else
      echo "Warning: failed to remove config dir '$removed_dir'" 1>&2
      [ -t 0 ] && sleep 2
    fi
  else
    rm -rf "$vhost_config_dir"
  fi

  rm -f "$v__vhost__config_link"
  rm -f "$lamp__paths__user_vhost_map/$user_web"

  echo "Removing cron for $user_web"
  crontab -u "$user_web" -r

  echo "Removing the user $user_web"
  "$sys_dir/libexec/remove-user" "$user_web"

  echo "Removing the group $user_web"
  groupdel "$user_web" || true

}

mysql_create_instance_for_vhost() {
  local vhost="$1"

  local instance="$vhost"

  local -a my_cnf_args_ar=()

  local config_dir root_cnf vhost_cnf mysqld_cnf socket_file
  local db_user db_pw cl_txt
  local mlx_user

  db_user="$v__vhost__linux_user"
  db_pw=$(gen_random_str_az09_lower 16)
  mlx_user="b_${v__vhost__linux_user#w_}"

  if mysql_create_instance --user "$mlx_user" --shared no "$instance"; then

    save_opts_in_mysql_instance "$mysql_instance" \
              "params.vhosts +=w $vhost"

    mysql_start_n_check_instance "$instance" || return $?

    mysql_create_user --instance "$instance" --user "$db_user" \
                      --password "$db_pw"

    mysql_create_vhost_cnf --vhost "$vhost" --user "$db_user"    \
                           --password "$db_pw"                   \
													 --instance "$instance"                \
                           --group-owner "$v__vhost__linux_user"

    mysql_grant_all_privs_to_user "$instance" \
      "$v__vhost__linux_user"
  else
    return 1
  fi
}

mysql_create_vhost_cnf() {
  local opt vhost user password group_owner socket mysql_version
  local cnf_file mysqld_cnf config_dir socket vh_config_dir socket_file
  local cl_txt instance
  local write_home_my_cnf=yes

  while [ -n "$1" -a "${1:0:1}" == - ]; do
    opt="$1"
    case $opt in
      --vhost)
        vhost="$2"
        shift 2
        ;;

      --instance)
        instance="$2"
        shift 2
        ;;

      --user)
        user="$2"
        shift 2
        ;;

      --password)
        password="$2"
        shift 2
        ;;

      --my-cnf)
        # specify an alternate path for my.cnf file
        cnf_file="$2"
        shift 2
        ;;

      --mysql-version)
        mysql_version="$2"
        shift 2
        ;;

      --group-owner)
        group_owner="$2"
        shift 2
        ;;

      --skip-home-my-cnf)
        unset write_home_my_cnf
        shift
        ;;

      *)
        echo "$FUNCNAME(): unknown option '$opt'" 1>&2
        return 1
        ;;
    esac
  done

  config_dir="$lamp__paths__mysql_instances_config_dir/$instance"
  mysqld_cnf="$config_dir/mysqld.cnf"

  vh_config_dir="$lamp__paths__vhosts_config_dir/$vhost"
  cnf_file="${cnf_file:-$vh_config_dir/mysql/my.cnf}"
  socket_file="$lamp__paths__mysql_socket_dir/$instance/mysql.sock"

  if [ -z "$mysql_version" ]; then
    mysql_ver=$(get_mysql_version )
    mysql_ver=${mysql_ver//[^0-9]}
  fi

  touch "$cnf_file"
  chmod 640 "$cnf_file"
  chgrp "$v__vhost__linux_user" "$cnf_file"

  cl_txt+="!include $mysqld_cnf
[client]
user = $user
password = $password
"

  if [ "$mysql_ver" -le 51 ]; then
    # mysql versions < 5.5 don't support !include lines, so we need to set
    # the socket for the vhost user to be able to access through the mysql
    # cli. Though we keep the !include line above for PHPMyadmin wrapper
    # to parse it (the mysql cli ignores it)
    cl_txt+="socket = $socket"$'\n'
  fi

  echo -n "$cl_txt" >$cnf_file

  if [ -n "$write_home_my_cnf" ]; then
    run_as_user "$v__vhost__linux_user" \
                  rm -f \~/.my.cnf \&\& ln -s $cnf_file \~/.my.cnf
  fi

  if [ -n "$group_owner" ]; then
    chgrp "$group_owner" "$cnf_file"
  fi

  return 0
}

mysql_run_query_with_vhost_privs() {
  local vhost="$1"
  local query="$2"

  local ns st cnf_key query_double_esc
  local l_user l_user_key

  if [ -z "${!v__vhost__*}" -o "$v__vhost__name" != "$vhost" ]; then
    ns=_tmp_$RANDOM
    cnf_key="${ns}__mysql__client_file"
    l_user_key="${ns}__vhost__linux_user"

    load_vhost_config "$vhost" "$ns" || return $?
  else
    l_user_key="v__vhost__linux_user"
    cnf_key="v__mysql__client_file"
  fi

  l_user="${!l_user_key}"

  run_as_user "$l_user" mysql --defaults-file="${!cnf_key}" -BN -e "$query"
  st=$?

  [ -n "$ns" ] && cleanup_namespace $ns

  return $st
}

mysqldump_with_vhost_privs() {
  local vhost="$1"
  shift

  local ns st cnf_key
  local l_user
  ns=_tmp_$RANDOM
  cnf_key="${ns}__mysql__client_file"

  load_vhost_config "$vhost" "$ns" || return $?

  l_user="$v__vhost__linux_user"

  run_as_user "$l_user" mysqldump --defaults-file="${!cnf_key}" "$@"
  st=$?

  cleanup_namespace $ns

  return $st
}

mysql_list_databases_as_vhost() {
  local vhost="$1"

  mysql_run_query_with_vhost_privs "$vhost" "SHOW DATABASES;"
}

mysqldump_vhost_databases() {
  local opt db_list ns db_prefix db_prefix_key _db file
  local compress=yes

  while [ -n "$1" -a "${1:0:1}" == - ]; do
    opt="$1"
    case $opt in
      --dont-compress)
        unset compress
        shift
        ;;

      *)
        echo "$FUNCNAME(): unknown option '$opt'" 1>&2
        return 1
        ;;
    esac
  done

  local vhost="$1"
  local dir="$2"
  
  if [ -z "$v__vhost__name" -o "$v__vhost__name" != "$vhost" ]; then
    ns=_tmp_$RANDOM
    db_prefix_key="${ns}__mysql__database_prefix"
    load_vhost_config "$vhost" "$ns" || return $?
  else
    db_prefix_key=v__mysql__database_prefix
  fi

  db_list=$(mysql_list_databases_as_vhost "$vhost")
  if [ $? -ne 0 ]; then
    echo "$FUNCNAME(): failed to get list of mysql databases" 1>&2
    return 1
  fi

  if [ -n "${!db_prefix_key}" ]; then
    db_prefix="${!db_prefix_key}"
  fi

  if [ -n "$ns" ]; then
    cleanup_namespace "$ns"
  fi

  for _db in $db_list; do
    if in_array "$_db" mysql information_schema performance_schema sys; then
      continue
    fi

    if [ -n "$db_prefix" ]; then
      file="$dir/${_db#$db_prefix}.sql"
    else
      file="$dir/$_db.sql"
    fi

    mysqldump_with_vhost_privs "$vhost" "$_db" >$file
    if [ -n "$compress" ]; then
      if ! gzip "$file"; then
        echo "$FUNCNAME(): error, failed to compress file '$file'" 1>&2
        return 1
      fi
    fi
  done
}

mysql_drop_vhost_dbs_with_prefix() {
  local vhost="$1"
  local instance="$2"
  local prefix="$3"

  local _db _sql_query
  for _db in $(mysql_list_databases_as_vhost "$vhost"); do
    if in_array "$_db" mysql information_schema performance_schema sys; then
      continue
    fi

    _sql_query="DROP DATABASE \`$_db\`;"
    mysql_run_query_with_vhost_privs "$vhost" "$_sql_query"
  done
}

mysql_create_unpriv_user_for_vhost() {
  local opt
  local instance user password db_prefix root_cnf vhost
  local write_my_cnf

  while [ -n "$1" -a "${1:0:1}" == - ]; do
    opt="$1"
    case $opt in
      --instance)
        instance="$2"
        shift 2
        ;;

      --user)
        user="$2"
        shift 2
        ;;

      --password)
        password="$2"
        shift 2
        ;;

      --db-prefix)
        db_prefix="$2"
        shift 2
        ;;

      --vhost)
        vhost="$2"
        shift 2
        ;;

      --write-my-cnf)
        write_my_cnf=yes
        shift
        ;;

      *)
        echo "$FUNCNAME(): unknown option '$opt'" 1>&2
        return 1
        ;;
    esac
  done

  instance=${instance:-$vhost}
  root_cnf="$lamp__paths__mysql_instances_config_dir/$instance/root.client.cnf"
  db_prefix="${db_prefix:-${vhost}__}"

  mysql_create_user --my-cnf "$root_cnf" --user "$user" \
    --password "$password" || return $?

  if [ "$write_my_cnf" == yes ]; then
    mysql_create_vhost_cnf --vhost "$vhost" --user "$user"        \
                           --password "$password"                 \
													 --instance "$instance"                 \
                           --group-owner "$v__vhost__linux_user"

  fi

  mysql_grant_privs_to_user --my-cnf "$root_cnf" --user "$user" \
    --db-prefix "$db_prefix"
}

mysql_unpriv_import_vhost_dbs_from_dir() {
  local lnx_user="$v__vhost__linux_user"

  if [ -z "$lnx_user" ]; then
    echo "$FUNCNAME(): undefined variable \$v__vhost__linux_user" 1>&2
    return 1
  fi

  run_as_user "$lnx_user" "$sys_dir/bin/import-databases-from-dir" "$@"
}
