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
  local removed_vhosts_dir archived_files_dir
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

  echo "Removing webenabled config dir"
  rm_rf_safer "$vhost_config_dir"

  if [ -d "$vhost_cache_dir" ]; then
    echo "Removing cache dir $vhost_cache_dir"
    rm_rf_safer "$vhost_cache_dir"
  fi

  if [ -d "$archived_files_dir" ]; then
    if [ ! -d "$removed_vhosts_dir" ]; then
      mkdir -p -m 700 "$removed_vhosts_dir"
    fi

    removed_archives_dir="$removed_vhosts_dir/$vhost--$date_ts.$RANDOM"
    if mv -v "$archived_files_dir" "$removed_archives_dir"; then
      chmod 700 "$removed_archives_dir"
      chown 0:0 "$removed_archives_dir"  # chown directory to root:root
      find "$removed_archives_dir" -type f -exec chmod 0600 "{}" \; \
                                           -exec chown 0:0 "{}" \;
    fi
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

  local config_dir root_cnf vhost_cnf mysqld_cnf
  local db_user db_pw cl_txt
  local mlx_user mlx_home_dir
  local mysql_ver mysql_ver_no
  local vh_config_dir="$lamp__paths__vhosts_config_dir/$vhost"

  db_user="$v__vhost__linux_user"
  db_pw=$(gen_random_str_az09_lower 16)
  mlx_user="b_${v__vhost__linux_user#w_}"
  mlx_home_dir="$lamp__mysql_paths__instances_homedir/$mlx_user"
  config_dir="$lamp__paths__mysql_instances_config_dir/$instance"
  mysqld_cnf="$config_dir/mysqld.cnf"
  root_cnf="$config_dir/root.client.cnf"
  vhost_cnf="$vh_config_dir/mysql/my.cnf"
  mysql_ver=$(get_mysql_version )
  mysql_ver_no=${mysql_ver//[^0-9]}

  if mysql_create_instance --user "$mlx_user" --home-dir "$mlx_home_dir" \
       "$instance"; then

    mysql_start_instance "$instance"
    sleep 3

    mysql_create_user --my-cnf "$root_cnf" --user "$db_user" \
                      --password "$db_pw"

    touch "$vhost_cnf"
    chmod 640 "$vhost_cnf"

    cl_txt+="!include $mysqld_cnf
[client]
user = $db_user
password = $db_pw
"

    if [ "$mysql_ver_no" -le 51 ]; then
      # mysql versions < 5.5 don't support !include lines, so we need to set
      # the socket for the vhost user to be able to access through the mysql
      # cli. Though we keep the !include line above for PHPMyadmin wrapper
      # to parse it (the mysql cli ignores it)
      cl_txt+="socket = $lamp__paths__mysql_socket_dir/$instance/mysql.sock"$'\n'
    fi

    echo -n "$cl_txt" >$vhost_cnf

    chgrp "$v__vhost__linux_user" "$vhost_cnf"

    mysql_grant_all_privs_to_user "$instance" \
      "$v__vhost__linux_user"
  else
    return 1
  fi
}

mysql_ping_instance() {
  local instance="$1"
  local config_dir config_file

  config_dir="$lamp__paths__mysql_instances_config_dir/$instance"
  config_file="$config_dir/root.client.cnf"

  mysqladmin --defaults-file="$config_file" ping
}

mysql_start_instance() {
  local instance="$1"

  local config_dir config_ini mysqld_bin mysqld_cnf

  mysqld_bin=$(get_mysqld_bin ) || return $?

  config_dir="$lamp__paths__mysql_instances_config_dir/$instance"
  config_ini="$config_dir/config.ini"
  mysqld_cnf="$config_dir/mysqld-inc.cnf"

  read_ini_file_into_namespace "$config_ini" conf__mysql || return $?
 
  mkdir -m 771 -p "$lamp__paths__mysql_socket_dir/$instance"
  chgrp "$conf__mysql__params__linux_user" \
    "$lamp__paths__mysql_socket_dir/$instance"

  run_as_user --shell /bin/bash "$conf__mysql__params__linux_user" \
    "( $mysqld_bin --defaults-extra-file="$mysqld_cnf" & )"
}

mysql_start_n_check_instance() {
  local instance="$1"

  if ! mysql_start_instance "$instance"; then
    echo "$FUNCNAME(): failed to start mysql for instance '$instance'" 1>&2
    return 1
  fi

  for i in {1..20}; do
    sleep 0.5
    if mysql_instance_is_running "$instance"; then
      # wait a bit to see if mysql is still running
      sleep 3
      if mysql_ping_instance "$instance">/dev/null; then
        return 0
      fi
    fi
  done

  echo "$FUNCNAME(): failed to verify whether mysql started" 1>&2
  return 1
}

mysql_stop_instance() {
  local instance="$1"
  local config_dir config_file

  config_dir="$lamp__paths__mysql_instances_config_dir/$instance"
  config_file="$config_dir/root.client.cnf"

  mysqladmin --defaults-file="$config_file" --verbose shutdown
}

mysql_restart_instance() {
  local instance="$1"

  mysql_ping_instance "$instance" >/dev/null && mysql_stop_instance "$instance"

  mysql_start_instance "$instance"
}

mysql_lock_instance_autostart() {
  touch "$conf__paths__lock_dir/mysql.$instance"
}

mysql_unlock_instance_autostart() {
  rm -f "$conf__paths__lock_dir/mysql.$instance"
}

mysql_is_instanced_autostart_locked() {
  test -e "$conf__paths__lock_dir/mysql.$instance"
}

mysql_instance_is_running() {
  local instance="$1"
  local config_file
  local ns port_ref socket_ref
  local -i st

  config_file="$lamp__paths__mysql_instances_config_dir/$instance/mysqld.cnf"
  ns="tmp_$BASHPID"

  # st=50 -> internal error (unable to determine port)
  read_ini_file_into_namespace "$config_file" $ns || return 50

  port_ref="${ns}__mysqld__port"
  socket_ref="${ns}__mysqld__socket"

  if [ -n "${!port_ref}"     ] && fuser -s "${!port_ref}/tcp" 2>/dev/null; then
    st=0
  elif [ -n "${!socket_ref}" ] && fuser -s "${!socket_ref}" 2>/dev/null; then
    st=0
  elif [ -z "${!port_ref}" -a -z "${!socket_ref}" ]; then
    echo "$FUNCNAME(): didn't find port nor socket defined" 1>&2
    st=50
  else
    st=1
  fi

  cleanup_namespace $ns

  return $st
}

mysql_force_instance_stop() {
  local instance="$1"
  local config_file
  local ns port_ref socket_ref
  local -i st

  config_file="$lamp__paths__mysql_instances_config_dir/$instance/mysqld.cnf"
  ns="tmp_$BASHPID"

  # st=50 -> internal error (unable to determine port)
  read_ini_file_into_namespace "$config_file" $ns || return 50

  port_ref="${ns}__mysqld__port"
  socket_ref="${ns}__mysqld__socket"

  if [ -n "${!socket_ref}" ] && fuser -s "${!socket_ref}" 2>/dev/null; then
    force_kill_proc_using_file "${!socket_ref}"
    st=$?
  elif [ -n "${!port_ref}" ] && fuser -s "${!port_ref}/tcp" 2>/dev/null; then
    force_kill_proc_using_file "${!port_ref}/tcp"
    st=$?
  elif [ -z "${!port_ref}" -a -z "${!socket_ref}" ]; then
    echo "$FUNCNAME(): didn't find port nor socket defined" 1>&2
    st=50
  else
    st=1
  fi

  cleanup_namespace $ns

  return $st
}
