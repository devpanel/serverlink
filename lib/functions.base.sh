#!/bin/bash

is_word_in_string() {
  local word="$1"
  local string="$2"

	if [  "$string"  == "$word"     ] || \
     [[ "$string" == $word\ *    ]] || \
     [[ "$string" == *\ $word    ]] || \
     [[ "$string" == *\ $word\ * ]]; then

    return 0
  else
    return 1
	fi
}

bash_has_global_declare() {
  if [ -z "${BASH_VERSINFO[*]}" ]; then
    return 1
  fi

  if [ "${BASH_VERSINFO[0]}" -gt 4 \
      -o "${BASH_VERSINFO[0]}" == 4 -a "${BASH_VERSINFO[1]}" -ge 2 ]; then
    return 0
  else
    return 1
  fi
}

set_global_var() {
  local var="$1"
  local value="$2"
  local value_esc

  # this function is used to avoid using eval on eventually untrusted data.
  # It's just a security caution.

  if bash_has_global_declare ; then
    declare -g $var="$value"
  else
    # for older bash versions that don't have declare -g
    value_esc=$(printf '%q' "$value" )
    eval "$var"="$value_esc"
  fi
}

cleanup_namespace() {
  local namespace="$1"
  local var

  for var in $(eval echo -n "\${!${namespace}__*}"); do
    unset $var
  done

}

read_ini_file_into_namespace() {
  local cleanup_env=yes
  local mysql_ext

  while [ -n "$1" -a "${1:0:1}" == - ]; do
    case "$1" in
      --no-cleanup)
        unset cleanup_env
        shift
        ;;

      --mysql-ext)
        # mysql extension (read a !include file) into the same namespace
        mysql_ext=yes
        shift
        ;;

      *)
        echo "$FUNCNAME(): unknown option '$1'" 1>&2
        return 1
        ;;
    esac
  done

  if [ $# -lt 2 -o -z "$1" -o -z "$2" ]; then
    echo "$FUNCNAME(): missing arguments" 1>&2
    return 1
  fi

  local file="$1"
  local ns="$2"

  if [ -n "$cleanup_env" ]; then
    cleanup_namespace "$ns"
  fi

  local prefix section line key key_len value var
  local section_name second_file
  local value_esc
  local -i line_n=0 line_len=0

  section=_
  while IFS=" " read line ; do
    line_n+=1
    [ -z "$line" ] && continue
    [ "${line:0:1}" == "#" ] && continue
    [ "${line:0:1}" == ";" ] && continue

    # mysql extension (read a !include file) into the same namespace
    if [ -n "$mysql_ext" ] && [ "${line:0:1}" == '!' ]; then
      if [ "${line%% *}" == "!include" ]; then
        second_file="${line#* }"
        read_ini_file_into_namespace --no-cleanup "$second_file" "$ns" || \
          return $?
        continue
      fi
    fi
    line_len=${#line}

    if [ "${line:0:1}" == "[" ]; then
      # found a new section

      # echo "Found section: $section"
      if [[ "$line" =~ ^\[[A-Za-z0-9_]+\ ?[A-Za-z0-9_]*\]$ ]]; then
        section=${line:1:$(( $line_len - 2 ))}
      fi
    elif [[ "$line" =~ ^[A-Za-z0-9_-]+\ *=\ *[^\ ].*$ ]]; then
      key=${line%%=*}
      key_len=${#key}

      # replace dashes with underscores (can't have variables with dashes)
      key=${key//-/_}

      # NOTE: can't use ${key: -1:1} because Centos 6 doesn't support the -1
      while [ -n "$key" -a "${key:$(( $key_len - 1 ))}" == " " ]; do
        # remove trailing spaces and tabs
        key=${key% }
        key_len=$(( $key_len - 1 ))
      done
      value=${line#*=}

      while [ -n "$value" -a "${value:0:1}" == " " ]; do
        # remove leading spaces and tabs
        value=${value# }
      done

      if [ "$section" == _ ]; then
        set_global_var "${ns}__${key}" "$value"
      else
        section_name=${section// /_}
        set_global_var "${ns}__${section_name}__${key}" "$value"
      fi
    else
      echo "$FUNCNAME(): Skipping malformed line $line_n: $line" 1>&2
    fi
  done < $file
}

load_devpanel_config() {
  local conf_def_dir="$DEVPANEL_HOME/config"
  local defaults_file="$conf_def_dir/defaults.ini"
  local publishers_file="$conf_def_dir/publishers.ini"

  local distro distro_version distro_ini local_ini_file
  distro=$(wedp_auto_detect_distro ) || return $?
  distro_version=$(devpanel_get_os_version "$distro") || return $?

  if [ "$distro" == centos -o "$distro" == debian ]; then
    distro_version=${distro_version%%.*}
  fi

  cleanup_namespace conf

  # this is the global file that has the defaults for devPanel
  read_ini_file_into_namespace --no-cleanup "$defaults_file" conf || return $?

  # distro specific configurations (e.g. service names, paths, etc)
  distro_ini="$conf_def_dir/distros/$distro/$distro_version/defaults.ini"
  if [ -f "$distro_ini" ]; then
    read_ini_file_into_namespace --no-cleanup "$distro_ini" conf || return $?
  fi

  # local installation specific configurations
  local_ini_file="$conf__paths__local_config_dir/config.ini"
  if [ -f "$local_ini_file" ]; then
    read_ini_file_into_namespace --no-cleanup "$local_ini_file" conf || return $?
  fi

  # load app publisher URLs
  if [ -f "$publishers_file" ]; then
    read_ini_file_into_namespace --no-cleanup "$publishers_file" conf || \
      return $?
  fi

  if [ -z "$conf__paths__run_dir" ]; then
    if [ -d /run ]; then
      conf__paths__run_dir=/run/devpanel
    else
      conf__paths__run_dir=/var/run/devpanel
    fi
  fi

  if [ $EUID -eq 0 -a ! -d "$conf__paths__run_dir" ]; then
    mkdir -m 0711 "$conf__paths__run_dir"
  fi
  conf__paths__lock_dir="$conf__paths__run_dir/lock"

  if [ $EUID -eq 0 -a ! -d "$conf__paths__lock_dir" ]; then
    mkdir -m 0711 "$conf__paths__lock_dir"
  fi

  conf__distro="$distro"
  conf__distro_version="$distro_version"
  conf__s3__default_config_file="$conf__paths__local_config_dir/provisioners/aws/.s3cfg/default"
  conf__paths__port_reservation_dir="$conf__paths__local_config_dir/ports"
  
  load_devpanel_lamp_config || return $?

  return 0
}

load_devpanel_lamp_config() {
  local distro distro_version
                            
  distro="$conf__distro"
  distro_version="$conf__distro_version"

  if [ "$distro" == centos ]; then
    distro_version=${distro_version%%.*}
  fi

  local stack_dir="$DEVPANEL_HOME/stacks/lamp"
  local distro_defs_dir="$stack_dir/distros/$distro/$distro_version"
  local distro_config_ini="$distro_defs_dir/defaults.ini"
  local lamp_defaults_ini="$stack_dir/defaults.ini"
  local local_lamp_dir="$conf__paths__local_config_dir/lamp"
  local local_lamp_file="$local_lamp_dir/config.ini"

  cleanup_namespace lamp

  # load the Lamp defaults
  if [ -f "$lamp_defaults_ini" ]; then
    read_ini_file_into_namespace "$lamp_defaults_ini" lamp || return $?
  fi

  # load the distro specific defaults
  read_ini_file_into_namespace --no-cleanup "$distro_config_ini" lamp || return $?

  lamp__paths__distro_defaults_dir="$distro_defs_dir"

  # load specific values for local installation
  if [ -f "$local_lamp_file" ]; then
    read_ini_file_into_namespace --no-cleanup "$local_lamp_file" lamp || return $?
  fi

  if [ -z "$lamp__php__default_version" ]; then
    lamp__php__default_version=$lamp__php__default_version_on_install
  fi

  lamp__paths__local_config_dir="$local_lamp_dir"
  lamp__paths__apache_local_virtwww_dir="$local_lamp_dir/apache/virtwww"
  lamp__paths__vhosts_config_dir="$local_lamp_dir/vhosts"

  lamp__paths__user_vhost_map="$local_lamp_dir/linuxuser-vhost-map"

  lamp__paths__mysql_instances_config_dir="$local_lamp_dir/mysql/instances"

  lamp__paths__mysql_socket_dir="$conf__paths__run_dir/mysql/instances"
  if [ $EUID -eq 0 -a ! -d "$lamp__paths__mysql_socket_dir" ]; then
    mkdir -m 711 -p "$lamp__paths__mysql_socket_dir"
  fi
 
  return 0
}

load_state_data() {
  local state_file="/var/spool/devpanel/state.ini"
  if [ -f "$state_file" ]; then
    read_ini_file_into_namespace "$state_file" state || return $?
  else
    echo "$FUNCNAME(): error, missing state file '$state_file'" 1>&2
    return 1
  fi
}

write_ini_file() {
  if [ $# -lt 2 ]; then
    echo "$FUNCNAME(): missing arguments" 1>&2
    return 1
  fi

  local file="$1"
  shift

  local txt=""
  while [ -n "$1" ]; do
    txt+="$1"$'\n'
    shift
  done

  echo "$txt" | "$DEVPANEL_HOME/bin/update-ini-file" -q -c "$file"
}

load_vhost_config() {
  local vhost="$1"
  local ns="${2:-v}"

  if [ -z "$vhost" ]; then
    echo "$FUNCNAME(): missing vhost name" 1>&2
    return 1
  fi

  if ! is_valid_vhost_string "$vhost"; then
    echo "$FUNCNAME(): got an invalid string as vhost name" 1>&2
    return 1
  fi

  local config_dir="$lamp__paths__vhosts_config_dir/$vhost"
  local ini_file="$config_dir/config.ini"
  local mysql_conf_dir="$lamp__paths__mysql_instances_config_dir"
  local var vhost_var lamp_var value_esc tmp_str
  local alias_domains

  read_ini_file_into_namespace "$ini_file" "$ns" || return 1

  for var in ip_addr http_port https_port; do
    vhost_var="${ns}__vhost__$var"
    lamp_var="lamp__apache_vhosts__$var"
    if [ -z "${!vhost_var}" -a -n "${!lamp_var}" ]; then
      set_global_var $vhost_var "${!lamp_var}"
    fi
  done

  set_global_var "${ns}__vhost__name" "$vhost"
  set_global_var "${ns}__vhost__config_dir" "$config_dir"
  set_global_var "${ns}__vhost__archives_dir" "$conf__paths__data_dir/vhost_archives/$vhost"
  set_global_var "${ns}__vhost__file" "$config_dir/apache/vhost.conf"
  set_global_var "${ns}__vhost__config_link" "$lamp__paths__apache_local_virtwww_dir/$vhost.conf"
  set_global_var "${ns}__ssl__dir" "$config_dir/ssl"

  local server_name_var
  local domains_var="${ns}__vhost__domains"

  for tmp_str in ${!domains_var}; do
    server_name_var="${ns}__vhost__server_name"
    if [ "$tmp_str" == "${!server_name_var}" ]; then
      continue
    else
      if [ -n "$alias_domains" ]; then
        alias_domains+=" "
      fi
      alias_domains+="$tmp_str"
    fi
  done

  if [ -n "$alias_domains" ]; then
    set_global_var "${ns}__vhost__server_alias" "$alias_domains"
  fi

  local raw_line home_dir linux_user
  local linux_user_var="${ns}__vhost__linux_user"
  if [ -n "${!linux_user_var}" ]; then
    linux_user="${!linux_user_var}"
    raw_line=$(getent passwd "$linux_user")
    if [ $? -eq 0 ]; then
      home_dir=$(echo "$raw_line" | cut -d: -f 6)
      if [ -n "$home_dir" ]; then
        set_global_var "${ns}__vhost__linux_user_home" "$home_dir"
      else
        echo "$FUNCNAME(): unable to get home dir for user $linux_user" 1>&2
      fi
    else
      echo "$FUNCNAME(): unable to get home dir for user $linux_user" 1>&2
      return 1
    fi
  fi

  set_global_var "${ns}__vhost__logs_dir" \
                 "$lamp__apache_paths__vhost_logs_dir/$linux_user"

  local user_include_var user_include_file file_include_var
  local user_include_var="${ns}__vhost__user_includes"
  if [ -n "${!user_include_var}" -a "${!user_include_var}" == yes ]; then
    user_include_file="$config_dir/apache/user_includes.inc"
    if [ -f "$user_include_file" ]; then
      file_include_var="${ns}__vhost__user_include_file"
      set_global_var "$file_include_var" "$user_include_file"
    else
      echo "$FUNCNAME(): missing include file '$user_include_file'" 1>&2
      return 1
    fi
  fi

  local ssl_enabled_var ssl_dir_var
  ssl_enabled_var="${ns}__ssl__enabled"
  ssl_dir_var="${ns}__ssl__dir"

  if [ -n "${!ssl_enabled_var}" -a \
          "${!ssl_enabled_var}" == yes ]; then

    if [ -f "${!ssl_dir_var}/ca-bundle.crt" ]; then
      set_global_var "${ns}__ssl__ca_bundle_file" "${!ssl_dir_var}/ca-bundle.crt"
    fi

    if [ -f "${!ssl_dir_var}/cert.crt" ]; then
      set_global_var "${ns}__ssl__certificate_file" "${!ssl_dir_var}/cert.crt"
    fi

    if [ -f "${!ssl_dir_var}/private-key.key" ]; then
      set_global_var "${ns}__ssl__private_key_file" "${!ssl_dir_var}/private-key.key"
    fi
  fi

  local mysql_inst_var="${ns}__mysql__instance"
  local mysql_config_file
  if [ -n "${!mysql_inst_var}" ]; then
    mysql_config_file="$config_dir/mysql/my.cnf"
    if [ -f "$mysql_config_file" ]; then
      read_ini_file_into_namespace --mysql-ext --no-cleanup \
        "$mysql_config_file" ${ns}__mysql
      set_global_var "${ns}__mysql__client_file" "$mysql_config_file"
    fi
  fi

  return 0
}

save_opts_in_devpanel_config() {
  if [ $# -eq 0 ]; then
    echo "$FUNCNAME(): missing arguments" 1>&2
    return 1
  fi

  local file="$conf__paths__local_config_dir/config.ini"

  write_ini_file "$file" "$@"
}

save_opts_in_lamp_config() {
  if [ $# -eq 0 ]; then
    echo "$FUNCNAME(): missing arguments" 1>&2
    return 1
  fi

  local file="$lamp__paths__local_config_dir/config.ini"

  write_ini_file "$file" "$@"
}

save_opts_in_vhost_config() {
  if [ $# -eq 0 ]; then
    echo "$FUNCNAME(): missing arguments" 1>&2
    return 1
  fi
  local vhost="$1"
  shift

  local file="$lamp__paths__local_config_dir/vhosts/$vhost/config.ini"

  write_ini_file "$file" "$@"
}

save_opts_in_state() {
  if [ $# -eq 0 ]; then
    echo "$FUNCNAME(): missing arguments" 1>&2
    return 1
  fi

  local state_dir="/var/spool/devpanel"
  local file="$state_dir/state.ini"

  if [ ! -d "$state_dir" ]; then
    mkdir -m 751 "$state_dir" || return $?
  fi

  write_ini_file "$file" "$@"
}
