#!/bin/bash

mysql_create_instance() {
  local socket_file config_dir config_ini tmp_init root_client_cnf
  local mysqld_cnf mysqld_cnf_inc mysqld_bin password_str
  local user group home_dir data_dir tcp_port server_uuid
  local mysql_version mysql_version_no
  local -a adduser_args_ar=() init_cmd_ar=()
  local st

  while [ -n "$1" -a "${1:0:1}" == - ]; do
    case "$1" in
      --user)
        user="$2"
        shift 2
        ;;

      --home-dir)
        home_dir="$2"
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

  if assign_available_port tcp; then
    tcp_port="$_dp_value"
  else
    echo "$FUNCNAME(): unable to get a free TCP port" 1>&2
    return 1
  fi

  data_dir="$home_dir/mysql"
  socket_file="$lamp__paths__mysql_socket_dir/$name/mysql.sock"
  config_dir="$lamp__paths__mysql_instances_config_dir/$name"
  config_ini="$config_dir/config.ini"
  mysqld_cnf="$config_dir/mysqld.cnf"
  mysqld_cnf_inc="$config_dir/mysqld-inc.cnf"
  mysql_version=$(get_mysql_version_two_dots )
  mysql_version_no=${mysql_version//[^0-9]/}

  if ! mkdir -m 751 "$config_dir"; then
    echo "$FUNCNAME(): unable to create dir '$config_dir'" 1>&2
    return 1
  fi

  adduser_args_ar=( --home "$home_dir" --shell /sbin/nologin )

  if [ "$conf__distro" == centos ]; then
    adduser_args_ar+=( -c "mysql $name,,," )
  else
    adduser_args_ar+=( --disabled-password --gecos "mysql $name,,," )
  fi
  adduser_args_ar+=( "$user" )

  if ! adduser "${adduser_args_ar[@]}" ; then
    echo "$FUNCNAME(): unable to create user '$user'" 1>&2
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
    "params.type       = local"       \
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
    run_as_user --shell /bin/bash "$user" "${init_cmd_ar[*]}"
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

    run_as_user --shell /bin/bash "$user" "${init_cmd_ar[*]} >/dev/null"

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
    error "unable to initialize mysql instance" -
  fi

  return $st
}

mysql_delete_instance() {
  local instance="$1"
  local config_dir config_ini
  local inst_dir inst_port inst_user

  config_dir="$lamp__paths__mysql_instances_config_dir/$instance"
  config_ini="$config_dir/config.ini"

  read_ini_file_into_namespace "$config_ini" conf__mysql || return $?

  mysql_stop_instance "$instance"

  release_port tcp $conf__mysql__params__port

  userdel -r "$conf__mysql__params__linux_user"

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

mysql_create_user() {
  local db
  local opt db_user db_password _host
  local -a args_ar=()
  while [ -n "$1" -a "${1:0:1}" == - ]; do
    opt="$1"
    case "$opt" in
      --my-cnf)
        args_ar+=( --defaults-file="$2" )
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

  {
    for _host in '%' 'localhost'; do
      printf "CREATE USER '%s'@'%s' IDENTIFIED BY '%s';\n" \
        "$db_user" "$_host" "$db_password"
    done
  } | mysql "${args_ar[@]}" -BN
}

mysql_instance_exists() {
  local name="$1"

  if ! [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] ; then
    echo "$FUNCNAME(): invalid mysql name" 1>&2
    return 1
  fi

  if [ -d "$DEVPANEL_HOME/compat/dbmgr/config/mysql/$name" ]; then
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

mysql_list_databases() {
  local instance="$1"
  local my_cnf

  my_cnf="$lamp__paths__mysql_instances_config_dir/$instance/root.client.cnf"

  mysql --defaults-file="$my_cnf" -BN -e "SHOW DATABASES"
}

mysql_dump_database() {
  local instance="$1"
  local database="$2"
  local my_cnf

  my_cnf="$lamp__paths__mysql_instances_config_dir/$instance/root.client.cnf"

  mysqldump --defaults-file="$my_cnf" --extended-insert=false "$database"
}

get_mysql_version() {
  if ! hash mysql &>/dev/null; then
    echo "$FUNCNAME(): missing mysql command" 1>&2
    return 1
  fi

  local tmp_str
  tmp_str=$(mysql -V 2>/dev/null | egrep -o 'Distrib [0-9]\.[0-9]+(\.[0-9]+)?')
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
