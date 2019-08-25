#!/bin/bash

mysql_create_instance() {
  local socket_file config_dir config_ini tmp_init root_client_cnf
  local mysqld_cnf mysqld_cnf_inc mysqld_bin password_str
  local user group home_dir data_dir tcp_port server_uuid
  local mysql_version mysql_version_no
  local shared_st
  local -a adduser_args_ar=() init_cmd_ar=()
  local opt st tmp_output

  while [ -n "$1" -a "${1:0:1}" == - ]; do
    opt="$1"
    case "$opt" in
      --user)
        user="$2"
        shift 2
        ;;

      --home-dir)
        home_dir="$2"
        shift 2
        ;;

      --shared)
        if [[ "$2" != [Yy][Ee][Ss] && "$2" != [Nn][Oo] ]]; then
          echo "$FUNCNAME(): invalid value for $opt (expected: yes or no)" 1>&2
          return 1
        fi

        shared_st="${2,,}"
        shift 2
        ;;

      *)
        echo "$FUNCNAME(): unknown option '$1'" 1>&2
        return 1
        ;;
    esac
  done

  local name="$1"

  mysqld_bin=$(get_mysqld_bin ) || return $?

  mysql_is_valid_instance_name "$name" || return $?

  if ! tmp_output=$(mktemp ); then
    echo "$FUNCNAME(): failed to create temp file" 1>&2
    return 1
  fi

  if [ -z "$user" ]; then
    user=b_$(gen_random_str_az09_lower 6)
  fi

  if assign_available_port tcp; then
    tcp_port="$_dp_value"
  else
    echo "$FUNCNAME(): unable to get a free TCP port" 1>&2
    return 1
  fi

  shared_st=${shared_st:-no}
  home_dir=${home_dir:-$lamp__mysql_paths__instances_homedir/$user}
  data_dir="$home_dir/mysql"
  socket_file="$lamp__paths__mysql_socket_dir/$name/mysql.sock"
  config_dir="$lamp__paths__mysql_instances_config_dir/$name"
  config_ini="$config_dir/config.ini"
  mysqld_cnf="$config_dir/mysqld.cnf"
  mysqld_cnf_inc="$config_dir/mysqld-inc.cnf"
  mysql_version=$(get_mysql_version_two_dots )
  mysql_version_no=${mysql_version//[^0-9]/}

  adduser_args_ar=( --home "$home_dir" --shell /sbin/nologin )

  if [ "$conf__distro" == centos ]; then
    adduser_args_ar+=( -c "mysql $name,,," )
  else
    adduser_args_ar+=( --quiet --disabled-password --gecos "mysql $name,,," )
  fi
  adduser_args_ar+=( "$user" )

  if ! adduser "${adduser_args_ar[@]}" ; then
    echo "$FUNCNAME(): unable to create user '$user'" 1>&2
    return 1
  fi

  if ! mkdir -m 751 "$config_dir"; then
    echo "$FUNCNAME(): unable to create dir '$config_dir'" 1>&2
    return 1
  fi

  if  ! su -l -s /bin/bash -c \
           'mkdir -m 700 -p '"$home_dir/tmp" "$user"; then

    echo "Error: unable to create dirs on '$home_dir'" 1>&2
    return 1
  fi

  write_ini_file "$config_ini"        \
    "params.port       = $tcp_port"   \
    "params.data_dir   = $data_dir"   \
    "params.host_type  = local"       \
    "params.enabled    = yes"         \
    "params.shared     = $shared_st"  \
    "params.linux_user = $user"

  root_client_cnf="$config_dir/root.client.cnf"

  touch "$root_client_cnf"
  chmod 640 "$root_client_cnf"
  chgrp "$user" "$root_client_cnf"

  write_ini_file "$mysqld_cnf"                            \
    "mysqld.port        = $tcp_port"                      \
    "mysqld.datadir     = $data_dir"                      \
    "mysqld.log-error   = $data_dir/error.log"            \
    "mysqld.tmpdir      = $home_dir/tmp"                  \
    "mysqld.pid-file    = $data_dir/mysqld.pid"           \
    "mysqld.socket      = $socket_file"                   \
    "client.host        = 127.0.0.1"                      \
    "client.port        = $tcp_port"

  if tmp_init=$(mktemp $home_dir/tmp_init.XXXXXX); then
    temp_files_ar+=( "$tmp_init" )
    chgrp "$user" "$tmp_init"
    chmod 640 "$tmp_init"
    # SET PASSWORD works with mysql 5.5, 5.6 and 5.7
    password_str=$(gen_random_str_az09_lower 16)
    echo "
    SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$password_str');
    " >"$tmp_init"

    write_ini_file "$root_client_cnf"        \
      "client.socket    = $socket_file"      \
      "client.user      = root"              \
      "client.password  = $password_str"

    echo "!include $sys_dir/stacks/lamp/mysql/$mysql_version/mysqld.cnf" \
      >$mysqld_cnf_inc
    echo "!include $mysqld_cnf" >>$mysqld_cnf_inc
  else
    echo "$FUNCNAME(): failed to create temp file" 1>&2
    return 1
  fi

  mkdir -m 771 -p "${socket_file%/*}"
  chgrp "$user" "${socket_file%/*}"

  # check if mysqld supports --initialize 
  if "$mysqld_bin" --no-defaults -v --help 2>&1 | fgrep -q -- --initialize; then
    init_cmd_ar=( "$mysqld_bin" --no-defaults --initialize --datadir="$data_dir" \
                     --init-file="$tmp_init" )
    if [ "$mysql_version_no" -le 55 ]; then
      init_cmd_ar+=( --log-warnings=0 )
    else
      init_cmd_ar+=( --log-error-verbosity=1 )
    fi

    # initialize and set root password in one step, mysqld automatically
    # exits after initialization
    run_as_user --shell /bin/bash "$user" "${init_cmd_ar[@]}" &>$tmp_output
    st=$?
  else
    # initialize with mysql_install_db (before mysql 5.7)
    #
    # NOTE: on older mysql versions, mysql_install_db initializes mysqld
    # with option --bootstrap, what disables some functionality like CREATE
    # USER, SET PASSWORD and GRANT, so we can't initialize the server and
    # the password in one command (unlike newer versions). So we initialize
    # the server, start it temporarily with --init-file and protected
    # socket to set the password and then shut it down
    #
    local tmp_protected_socket="$data_dir/mysql.sock"

    init_cmd_ar=( mysql_install_db --no-defaults --log-warnings=0 \
                    --datadir="$data_dir" )

    run_as_user --shell /bin/bash "$user" "${init_cmd_ar[@]}" &>$tmp_output

    run_as_user --shell /bin/bash "$user" \
      \( "$mysqld_bin" --no-defaults --datadir="$data_dir" --skip-networking \
           --init-file="$tmp_init" --socket="$tmp_protected_socket" \& \)

    # TODO: fix this
    sleep 3

    mysqladmin --defaults-file="$root_client_cnf" \
      --socket="$tmp_protected_socket" shutdown
    st=$?

    rm -f "$tmp_protected_socket"
  fi

  if [ $st -ne 0 ]; then
    # show the error msgs
    #
    # NOTE: by default it's not displaying the output of the mysql
    # initialization because it shows several msgs with defaults that don't
    # apply to the mysql instances setup by this collection of scripts
    cat $tmp_output
    error "unable to initialize mysql instance" -
  fi
  rm -f $tmp_output

  return $st
}

mysql_delete_instance() {
  local instance="$1"
  local config_dir config_ini
  local inst_dir inst_port inst_user

  mysql_is_valid_instance_name "$instance" || return $?

  config_dir="$lamp__paths__mysql_instances_config_dir/$instance"
  config_ini="$config_dir/config.ini"

  read_ini_file_into_namespace "$config_ini" conf__mysql || return $?

  mysql_lock_instance_autostart "$instance"

  if ! mysql_stop_instance "$instance"; then
    echo "$FUNCNAME(): failed to stop mysql instance" 1>&2
    return 1
  fi

  release_port tcp $conf__mysql__params__port

  userdel -r "$conf__mysql__params__linux_user"

  mysql_lock_instance_autostart "$instance"

  rm -rf "$config_dir"
  rm -rf "$lamp__paths__mysql_socket_dir/$instance"
}

mysql_grant_all_privs_to_user() {
  local instance="$1"
  local user="$2"
  local config_file line

  config_file="$lamp__paths__mysql_instances_config_dir/$instance/root.client.cnf"
  line="GRANT ALL PRIVILEGES ON \`%\`.* TO '$user';"
  line+=$'\n'"GRANT ALL PRIVILEGES ON \`%\`.* TO '$user'@'localhost';"$'\n'

  # NOTE: mysql cli needs to parse two dashed options first
  mysql --defaults-file="$config_file" -B -N -e "$line"
}

mysql_grant_privs_to_user() {
  local opt user
  local cnf_file sql_line
  local db_prefix db_prefix_esc

  while [ -n "$1" -a "${1:0:1}" == - ]; do
    opt="$1"

    case $opt in
      --my-cnf)
        cnf_file="$2"
        shift 2
        ;;

      --db-prefix)
        db_prefix="$2"
        shift 2
        ;;

      --user)
        user="$2"
        shift 2
        ;;

      *)
        error "unknown option '$opt'" -
        return $?
        ;;
    esac
  done

  # NOTE: mysql treats underscore(_) as a wildcard, so it's needed to escape
  #       it with a backslash for it to handle the underscore literally
  #       (otherwise it'll apply the privileges to all databases that have a
  #        similar prefix before the underscores)
  db_prefix_esc=${db_prefix//_/\\_}
  
  line="GRANT ALL PRIVILEGES ON \`$db_prefix_esc%\`.* TO '$user';"

  # NOTE: mysql cli needs to parse two dashed options first
  mysql --defaults-file="$cnf_file" -B -N -e "$line"
}

mysql_create_user() {
  local db
  local opt db_user db_password _host
  local instance config_dir my_cnf_file
  local -a args_ar=()
  while [ -n "$1" -a "${1:0:1}" == - ]; do
    opt="$1"
    case "$opt" in
      --my-cnf)
        my_cnf_file="$2"
        shift 2
        ;;

      --instance)
        instance="$2"
        config_dir="$lamp__paths__mysql_instances_config_dir/$instance"
        my_cnf_file="$config_dir/root.client.cnf"
        shift 2
        ;;

      --user)
        db_user="$2"
        shift 2
        ;;

      --password)
        db_password="${2//\'/\\\'}"
        shift 2
        ;;

      *)
        echo "$FUNCNAME(): unknown option '$opt'" 1>&2
        return 1
        ;;
    esac
  done

  if [ -n "$instance" ]; then
    mysql_is_valid_instance_name "$instance" || return $?
  fi

  if [ -n "$my_cnf_file" ]; then
    if [ -f "$my_cnf_file" ]; then
      args_ar+=( --defaults-file="$my_cnf_file" )
    else
      echo "$FUNCNAME(): error, missing my_cnf file '$my_cnf_file'" 1>&2
      return 1
    fi
  else
    echo "$FUNCNAME(): either --instance of --my-cnf needs to be specified" 1>&2
    return 1
  fi

  {
    for _host in '%' 'localhost'; do
      printf "CREATE USER '%s'@'%s' IDENTIFIED BY '%s';\n" \
        "$db_user" "$_host" "$db_password"
    done
  } | mysql "${args_ar[@]}" -BN
}

mysql_is_valid_instance_name() {
  local name="$1"

  if [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] ; then
    return 0
  else
    echo "$FUNCNAME(): invalid name format for mysql instance" 1>&2
    return 1
  fi
}

mysql_instance_exists() {
  local name="$1"

  mysql_is_valid_instance_name "$name" || return $?

  if [ -d "$lamp__paths__mysql_instances_config_dir/$name" ]; then
    return 0
  else
    return 1
  fi
}

mysql_database_exists() {
  local db
  local opt
  local -a args_ar=()
  while [ -n "$1" -a "${1:0:1}" == - ]; do
    opt="$1"
    case "$opt" in
      --my-cnf)
        args_ar+=( --defaults-file="$2" )
        shift 2
        ;;

      *)
        echo "$FUNCNAME(): unknown option '$opt'" 1>&2
        return 1
        ;;
    esac
  done

  db="$1"

  if mysql "${args_ar[@]}" -B -D "$db" -e "SHOW TABLES" &>/dev/null; then
    return 0
  else
    return $?
  fi
}

mysql_rename_database() {
  local -a args_ar=()
  local opt
  while [ -n "$1" -a "${1:0:1}" == - ]; do
    opt="$1"
    case "$opt" in
      --my-cnf)
        args_ar+=( --defaults-file="$2" )
        shift 2
        ;;

      *)
        echo "$FUNCNAME(): unknown option '$opt'" 1>&2
        return 1
        ;;
    esac
  done

  local old_name="$1"
  local new_name="$2"
  local sql_l
  local sql_rename

  sql_l="SELECT CONCAT('RENAME TABLE ',table_schema,'.',table_name,"
  sql_l+=" ' TO ','$new_name.',table_name,';') FROM information_schema.TABLES"
  sql_l+=" WHERE table_schema LIKE '$old_name';"
          

  if sql_rename=$(mysql "${args_ar[@]}" -B -N -e "$sql_l" ); then
    if [ -n "$sql_rename" ]; then
      echo "$sql_rename" | mysql "${args_ar[@]}" -B -D "$new_name"
      return $?
    else
      # ok, no tables (empty db)
      return 0
    fi
  else
    echo "$FUNCNAME(): failed to rename '$old_name' to '$new_name'" 1>&2
    return 1
  fi

}

mysql_import_databases_from_dir() {
  local file database opt safer_overwrite tmp_db import_name
  local file_type my_cnf grant_user db_name_prefix
  local -a args_ar=()
  local db_regex='^[A-Za-z0-9_-]+$'

  while [ -n "$1" -a "${1:0:1}" == - ]; do
    opt="$1"
    case "$opt" in
      --safer-overwrite)
        safer_overwrite=1
        shift
        ;;

      --my-cnf)
        my_cnf="$2"
        args_ar+=( --defaults-file="$2" )
        shift 2
        ;;

      --grant-user)
        grant_user="$2"
        shift 2
        ;;

      --db-name-prefix)
        db_name_prefix="$2"
        shift 2
        ;;

      *)
        echo "$FUNCNAME(): unknown option '$opt'" 1>&2
        return 1
        ;;
    esac
  done

  local dir="$1"

  if [ ! -d "$dir" ]; then
    echo "$FUNCNAME(): path '$dir' is not a directory" 1>&2
    return 1
  elif [ ! -r "$dir" ]; then
    echo "$FUNCNAME(): path '$dir' is not readable" 1>&2
    return 1
  fi

  for file in "$dir"/*.sql "$dir"/*.sql.gz; do
    [ ! -f "$file" ] && continue

    if [[ "$file" == *.sql ]]; then
      database=${file%.*}
      database=${database##*/}
      file_type=sql
    elif [[ "$file" == *.sql.gz ]]; then
      database=${file%.*.*}
      database=${database##*/}
      file_type=sql_gz
    fi

    if [ -n "$db_name_prefix" ]; then
      database="${db_name_prefix}${database}"
    fi

    [[ ! "$database" =~ $db_regex ]] && continue

    if in_array "$database" mysql information_schema performance_schema sys; then
      continue
    fi

    if mysql_database_exists ${my_cnf:+--my-cnf "$my_cnf"} "$database"; then
      if [ -n "$safer_overwrite" ]; then
        random_str="${BASH_PID}${RANDOM}${RANDOM}"
        tmp_db="${database}_$random_str"
        import_name="$tmp_db"

        if ! mysql "${args_ar[@]}" -B -e "CREATE DATABASE \`$tmp_db\`"; then
          echo "$FUNCNAME(): failed to create tmp database '$tmp_db',"
                 "skipping importing database '$database'..." 1>&2
          continue
        fi
      else
        import_name="$database"
        if ! mysql "${args_ar[@]}" -B -e "DROP DATABASE \`$database\`"; then
          echo "$FUNCNAME(): failed to drop database '$database', skipping..." 1>&2
          continue
        fi

        if ! mysql "${args_ar[@]}" -B -e "CREATE DATABASE \`$database\`"; then
          echo "$FUNCNAME(): failed to re-create database '$database', skipping..." 1>&2
          continue
        fi
      fi
    else
      import_name="$database"

      if ! mysql "${args_ar[@]}" -B -e "CREATE DATABASE \`$import_name\`"; then
        echo "$FUNCNAME(): failed to re-create database '$import_name', skipping..." 1>&2
        continue
      fi
    fi

    [ "$import_name" == "$database" ] && \
      echo "Importing database $database..."

    case $file_type in
      sql)
        if ! mysql "${args_ar[@]}" -B -D "$import_name" < $file; then
          echo "$FUNCNAME(): failed to import database '$database'" 1>&2
          continue
        fi
        ;;

      sql_gz)
        if ! zcat $file | mysql "${args_ar[@]}" -B -D "$import_name"; then
          echo "$FUNCNAME(): failed to import database '$database'" 1>&2
          continue
        fi
        ;;
    esac

    if [ -n "$grant_user" ]; then
      mysql "${args_ar[@]}" -B -e \
        "GRANT ALL PRIVILEGES ON \`$database\`.* TO '$grant_user'@'%'"
    fi

    # if the import name is not equal to the import database, rename the
    # temporary database to the new name
    if [ -n "$safer_overwrite" -a "$database" != "$import_name" ]; then
      if mysql_database_exists ${my_cnf:+--my-cnf "$my_cnf"} "$database" 2>/dev/null; then
        echo "Dropping old database '$database'..."
        mysql "${args_ar[@]}" -B -e "DROP DATABASE \`$database\`;"
      fi

      echo "Re-creating database '$database'..."
      mysql "${args_ar[@]}" -B -e "CREATE DATABASE \`$database\`;"

      echo "Importing backup data into '$database'..."
      if mysql_rename_database ${my_cnf:+--my-cnf "$my_cnf"} "$import_name" "$database"; then
        mysql "${args_ar[@]}" -B -e "DROP DATABASE \`$import_name\`;"
      else
        echo "$FUNCNAME(): failed renaming tmp database." \
               "Skipping import of '$database..." 1>&2
        continue
      fi
    fi
  done

  return 0
}

mysql_run_privileged_query() {
  local instance="$1"
  local sql_query="$2"

  mysql_is_valid_instance_name "$instance" || return $?

  local my_cnf sql_query

  my_cnf="$lamp__paths__mysql_instances_config_dir/$instance/root.client.cnf"

  # NOTE: run query on stdin to avoid leaking the query to 'ps'
  mysql --defaults-file="$my_cnf" -BN <<< "$sql_query"
}

mysql_list_databases() {
  local instance="$1"
  local prefix=${2:-}

  local sql_query prefix_esc

  sql_query="SHOW DATABASES"
  if [ -n "$prefix" ]; then
    prefix_esc=${prefix//_/\\_}
    sql_query+=" LIKE '$prefix_esc%';"
  fi

  mysql_run_privileged_query "$instance" "$sql_query"
}

mysql_dump_database() {
  local instance="$1"
  local database="$2"
  local my_cnf

  mysql_is_valid_instance_name "$instance" || return $?

  my_cnf="$lamp__paths__mysql_instances_config_dir/$instance/root.client.cnf"

  mysqldump --defaults-file="$my_cnf" --extended-insert=false "$database"
}

get_mysql_version() {
  if ! hash mysql &>/dev/null; then
    echo "$FUNCNAME(): missing mysql command" 1>&2
    return 1
  fi

  local tmp_str
  tmp_str=$(mysql -V 2>/dev/null | egrep -o '(Ver|Distrib) [0-9]\.[0-9]+(\.[0-9]+)?')
  if [ $? -ne 0 -o -z "$tmp_str" ]; then
    echo "$FUNCNAME(): unable to get mysql version from mysql command" 1>&2
    return 1
  fi

  local junk version_str
  IFS=" " read junk version_str <<< "$tmp_str"

  echo -n "$version_str"
}

get_mysql_version_two_dots() {
  local ver_raw ver
  
  ver_raw=$(get_mysql_version ) || return $?

  if [[ "$ver_raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # if the mysql version is in the format x.y.z then remove the last
    # number
    ver=${ver_raw%.*}
  elif [[ "$ver_raw" =~ ^[0-9]+\.[0-9]+$ ]]; then
    ver="$ver_raw"
  else
    echo "$FUNCNAME(): don't know how to got 2 dotted version from '$ver_raw'" 1>&2
    return 1
  fi
 
  echo "$ver"
}

get_mysqld_bin() {
  if [ -n "$lamp__mysql_paths__mysqld_bin" ]; then
    echo "$lamp__mysql_paths__mysqld_bin"
  elif hash mysqld &>/dev/null; then
    hash -t mysqld
  else
    echo "$FUNCNAME(): couldn't find mysqld in \$PATH" 1>&2
    return 1
  fi
}

mysql_ping_instance() {
  local instance="$1"
  local config_dir config_file

  mysql_is_valid_instance_name "$instance" || return $?

  config_dir="$lamp__paths__mysql_instances_config_dir/$instance"
  config_file="$config_dir/root.client.cnf"

  mysqladmin --defaults-file="$config_file" ping
}

mysql_start_instance() {
  local instance="$1"

  mysql_is_valid_instance_name "$instance" || return $?

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
    \( $mysqld_bin --defaults-extra-file="$mysqld_cnf" \& \)
}

mysql_start_n_check_instance() {
  local instance="$1"

  mysql_is_valid_instance_name "$instance" || return $?

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

  mysql_is_valid_instance_name "$instance" || return $?

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

  mysql_is_valid_instance_name "$instance" || return $?

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

  mysql_is_valid_instance_name "$instance" || return $?

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

mysql_drop_user() {
  local instance="$1"
  local username="$2"

  local sql_query="DROP USER '$username';
                   DROP USER IF EXISTS '$username'@'localhost';"

  mysql_run_privileged_query "$instance" "$sql_query"
}

mysql_drop_database() {
  local instance="$1"
  local database="$2"

  local sql_query="DROP DATABASE '$database';"

  mysql_run_privileged_query "$instance" "$sql_query"
}

mysql_change_user_password() {
  local opt
  local instance user host password password_esc
  local mysql_ver_two_dots mysql_ver_three_dots
  local sql_query_older sql_query_newer sql_query

  while [ -n "$1" -a "${1:0:1}" == - ]; do
    opt="$1"

    case "$opt" in
      --instance)
        if mysql_is_valid_instance_name "$2"; then
          instance="$2"
          shift 2
        else
          echo "$FUNCNAME(): invalid instance name" 1>&2
          return 1
        fi
        ;;

      --user)
        user="$2"
        shift 2
        ;;

      --password)
        password="$2"
        shift 2
        ;;

      --host)
        host="$2"
        shift 2
        ;;

      *)
        echo "$FUNCNAME(): unknown option '$opt'" 1>&2
        return 1
        ;;
    esac
  done

  host=${host:-%}

  password_esc=$(escape_quotes "$password" )

  # mysql version 5.7.5 or older
  sql_query_older="SET PASSWORD FOR '$user'@'$host' = PASSWORD('$password_esc');"

  # mysql 5.7.6 or newer
  sql_query_newer="ALTER USER '$user'@'$host' IDENTIFIED BY '$password_esc';"

  mysql_ver_two_dots=$(get_mysql_version_two_dots )
  if [ $? -ne 0 ]; then
    echo "$FUNCNAME(): failed to get mysql version" 1>&2
    return 1
  fi

  if [ "${mysql_ver_two_dots%%.*}" -eq 5 -a "${mysql_ver_two_dots#*.}" -lt 7 ]; then
    sql_query="$sql_query_older"
  elif [ "${mysql_ver_two_dots%%.*}" -eq 5 -a "${mysql_ver_two_dots#*.}" -ge 7 ]; then
    mysql_ver_three_dots=$(get_mysql_version )
    if [ $? -ne 0 ]; then
      echo "$FUNCNAME(): failed to get mysql version" 1>&2
      return 1
    fi

    if [ "${mysql_ver_three_dots##*.}" -ge 6 ]; then
      sql_query="$sql_query_newer"
    else
      sql_query="$sql_query_older"
    fi
  else
    echo "$FUNCNAME(): don't know how to change password on this mysql version" 1>&2
    return 1
  fi
 
  mysql_run_privileged_query "$instance" "$sql_query"
}
