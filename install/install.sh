#!/bin/bash
umask 022

# default install dir.  can be overwritten with -I
webenabled_install_dir="/opt/webenabled"

# default websites base dir
homedir_base="${DP_HOMES_DIR:-/home/clients/websites}"

# default databases base dir, can be overwritten with -D
databasedir_base="${DP_DBS_DIR:-/home/clients/databases}"

usage() {
  local prog=`basename "$0"`
  echo "
Usage: $prog [ options ]

  Options:
    -L distro         Assume the specified distro, don't try to auto-detect
    -I directory      Install the software in the specified directory
    -H hostname       hostname to use on the network services
    -U server_uuid    UUID of the server to configure on devpanel.conf
    -K secret_key     Secret key of the server to configure on devpanel.conf
    -u api_url        URL of the user api
    -A tasks_url      URL of the tasks api
    -h                Displays this help message
    -d                print verbose debug messages
    -R                enable auto-register
    -b                from bootstrap (don't update devpanel.conf and don't
                      restart taskd)
    -V version        Specify the version of the linux distro (optional)
    -W                Webenabled v1.0 backwards compatibility

"

  if [ $EUID -ne 0 ]; then
    echo "This script requires ROOT privileges to be run."
    echo
  fi

  exit 1
}

set_global_variables() {
  local source_dir="$1"
  local target_dir="$2"
  local distro="$3"

  local -i st
  # initialize global variables used throughout this script

  local we_config_dir="$source_dir/config"

  # main config file to be used by DevPanel
  dp_config_file="$target_dir/etc/devpanel.conf"

  _apache_logs_dir=`deref_os_fs_path "$source_dir" \
    pathnames/var/log/apache_logs_dir` || return 1

  _apache_vhost_logs_dir=`deref_os_fs_path "$source_dir" \
    pathnames/var/log/apache_vhosts` || return 1

  _apache_base_dir=`deref_os_fs_path "$source_dir" \
    pathnames/etc/apache_base_dir` || return 1
  
  _apache_includes_dir=`deref_os_fs_path "$source_dir" \
    pathnames/etc/apache_includes_dir` || return 1

  _apache_vhosts=`deref_os_fs_path "$source_dir" \
    pathnames/etc/apache_vhosts` || return 1

  _apache_vhosts_removed=`deref_os_fs_path "$source_dir" \
    pathnames/etc/apache_vhosts_removed` || return 1

  _apache_main_config_file=`deref_os_fs_path "$source_dir" \
    pathnames/etc/apache_main_config_file` || return 1

  _apache_user=`deref_os_prop "$source_dir" names/apache.user` \
    || return 1

  _apache_group=`deref_os_prop "$source_dir" names/apache.group` \
    || return 1

  _apache_exec_group=`deref_os_prop "$source_dir" names/apache-exec.group` \
    || return 1

  _apache_main_include=`deref_os_prop "$source_dir" names/apache_main_include` \
    || return 1

  _apachectl_bin=`deref_os_prop "$source_dir" pathnames/sbin/apachectl` \
    || return 1

  [ -z "$homedir_base" ] && \
  { homedir_base=`deref_os_prop "$source_dir" apache_virtwww_homedir` || return 1; }

  [ -z "$databasedir_base" ] && \
  { databasedir_base=`deref_os_prop "$source_dir" mysql_instances_homedir` || return 1; }

  return 0
}

install_ce_software() {
  local linux_distro="$1"
  local source_dir="$2"
  local webenabled_install_dir="$3"
  local machine_type=$(uname -m)

  local skel_base_dir="$webenabled_install_dir/install/skel/$linux_distro"
  local skel_dir_common="$skel_base_dir/common"
  local skel_dir_major="$skel_base_dir/$distro_ver_major"
  local skel_dir_major_minor="$skel_dir_major.$distro_ver_minor"

  local data_dir="${webenabled_install_dir}-data"
  local removed_vhosts_dir="$data_dir/removed_vhosts"

  mkdir -m 755 -p "$webenabled_install_dir" \
    "$homedir_base" "$databasedir_base" "$data_dir"
  
  if ! ( cd "$source_dir" && cp -a . "$webenabled_install_dir" ); then
    echo "Error: unable to copy installation files to target dir" >&2
    return 1
  fi

  local t_dir
  for t_dir in "$skel_dir_common" "$skel_dir_major" "$skel_dir_major_minor"; do
    if [ -d "$t_dir" ]; then
      cp -a "$t_dir/." /
      if [ $? -ne 0 ]; then
        echo -e "\n\nWarning: unable to copy distro skel files from $t_dir to /\n\n" 1>&2
        sleep 3
      fi
    fi
  done

  ln -snf "$webenabled_install_dir"/compat/w_ "$homedir_base"/w_
  chown -R w_:"$_apache_exec_group" "$webenabled_install_dir"/compat/w_

  if [ ! -e "$webenabled_install_dir/etc/devpanel.conf" ]; then
    cp -f "$source_dir/install/config/devpanel.conf.template" "$webenabled_install_dir/etc/devpanel.conf"
  fi

  "$webenabled_install_dir/libexec/create-vhost-archive-dirs" "$data_dir"

  ssl_certs_dir=`readlink "$webenabled_install_dir"/config/os/pathnames/etc/ssl/certs`
  ssl_keys_dir=`readlink "$webenabled_install_dir"/config/os/pathnames/etc/ssl/keys`
  [ ! -d "$ssl_certs_dir" ] && mkdir -m 755 -p "$ssl_certs_dir"
  [ ! -d "$ssl_keys_dir"  ] && mkdir -m 755 -p "$ssl_keys_dir"

  chmod 600 "$webenabled_install_dir/etc/devpanel.conf"

  # openssl req -subj "/C=--/ST=SomeState/L=SomeCity/O=SomeOrganization/OU=SomeOrganizationalUnit/CN=*.`hostname`" -new -x509 -days 3650 -nodes -out /opt/webenabled/config/os/pathnames/etc/ssl/certs/wildcard -keyout /opt/webenabled/config/os/pathnames/etc/ssl/keys/wildcard
  # cp -a "$source_dir"/install/old/cloudenabled/wildcard.cloudenabled.net.key "$webenabled_install_dir"/config/os/pathnames/etc/ssl/keys/wildcard
  # cp -a "$source_dir"/install/old/cloudenabled/wildcard.cloudenabled.net.crt "$webenabled_install_dir"/config/os/pathnames/etc/ssl/certs/wildcard

  # echo Vhost-simple-SSL-wildcard > "$webenabled_install_dir"/config/names/apache-macro

  if [ -e "$_apache_vhost_logs_dir" -a ! -d "$_apache_vhost_logs_dir" ]; then
    mv "$_apache_vhost_logs_dir" "$_apache_vhost_logs_dir".old
  fi

  if [ ! -d "$_apache_vhost_logs_dir" ]; then
    mkdir -m 755 -p "$_apache_vhost_logs_dir"
    if [ $? -ne 0 ]; then
      echo -e "\nWarning: unable to create apache log dir '$_apache_vhost_logs_dir'\n" 1>&2
      sleep 3
    fi
  fi
  chmod 751 "$_apache_logs_dir"

  if [ -d "$source_dir/install/skel/common" ]; then
    cp -fdR --preserve=mode,timestamps "$source_dir/install/skel/common/." /
  fi

  echo "DEVPANEL_HOME=\"$webenabled_install_dir\"" >/etc/default/devpanel

  local prof_d_file="$webenabled_install_dir/install/utils/profile.d/devpanel.sh"
  if [ -d /etc/profile.d -a -f "$prof_d_file" ]; then
    ln -sf "$prof_d_file" /etc/profile.d/devpanel.sh
  fi

  local d cron_file
  for d in cron.hourly cron.daily cron.weekly cron.monthly; do
    cron_file="$webenabled_install_dir/install/utils/crontab/$d"
    if [ -d "/etc/$d" -a -f "$cron_file" ]; then
      ln -sf "$cron_file" "/etc/$d/devpanel"
    fi
  done

  ln -s "$_apache_logs_dir" "$_apache_base_dir/webenabled-logs"

  ln -s "$webenabled_install_dir/compat/apache_include/global-includes" \
    "$_apache_base_dir/devpanel-global"

  ln -s "$webenabled_install_dir/compat/apache_include/virtwww" \
    "$_apache_base_dir/devpanel-virtwww"

  ln -sf "$webenabled_install_dir/compat/apache_include/$_apache_main_include" \
    "$_apache_includes_dir/devpanel.conf"

  return 0
}

add_custom_users_n_groups() {
  local source_dir="$1"
  local webenabled_install_dir="$2"

  for group in w_ virtwww weadmin; do
    if ! getent group "$group" &>/dev/null; then
      echo "Adding group $group..."; sleep 0.5;
      groupadd "$group" || true
    fi
  done

  if [ -z "$WEBENABLED_DONT_CHANGE_SHELL" ]; then
    useradd -D -s /bin/bash
  fi

  local skel_ssh="/etc/skel/.ssh"
  local skel_auth_keys="$skel_ssh/authorized_keys"
  if [ ! -d "$skel_ssh" ] && mkdir -m 700 "$skel_ssh" ; then
    cp /dev/null "$skel_auth_keys"
    chmod 600 "$skel_auth_keys"
  fi

  local comment="required by DevPanel service. Please don't remove."
  if ! getent passwd w_ &>/dev/null; then
    echo "Adding user w_ ..."
    useradd -M -c "$comment" -d "$homedir_base"/w_ -G w_ \
      -g "$_apache_exec_group" w_
  fi

  if ! getent passwd devpanel &>/dev/null; then
    echo "Adding user devpanel ..."; sleep 0.5
    useradd -m -c "$comment" -d "/home/devpanel" devpanel
  fi

  usermod -a -G virtwww "$_apache_user"

}

post_software_install() {
  local linux_distro="$1"
  local source_dir="$2"
  local target_dir="$3"

  local status

  if [ -n "$dp_server_hostname" ]; then
    "$webenabled_install_dir/libexec/config-vhost-names-default" \
      "$dp_server_hostname"

    # add the hostname to the apache main file, in case it's not configured
    # to avoid the warning when restarting Apache
    if ! egrep -qs '^[[:space:]]*ServerName' "$_apache_main_config_file"; then
      sed -i -e "0,/^#[[:space:]]*ServerName[[:space:]]\+[A-Za-z0-9:.-]\+$/ {
      /^#[[:space:]]*ServerName[[:space:]]\+[A-Za-z0-9:.-]\+$/ {
      a\
ServerName $dp_server_hostname
;
      }  }" "$_apache_main_config_file"
    fi

    "$webenabled_install_dir/bin/add-to-known-hosts" \
      -a "$dp_server_hostname" localhost

    "$webenabled_install_dir/bin/update-dot-ssh-config" /etc/ssh/ssh_config \
      add_section "*.$dp_server_hostname" "Hostname=$dp_server_hostname"

    "$target_dir/bin/template-tool" \
      -o "$target_dir/compat/apache_include/global-includes/admin-ctl.conf" \
      "$target_dir/compat/apache_include/admin-ctl.conf.template"

  else
    "$webenabled_install_dir/bin/add-to-known-hosts" localhost
  fi

  local custom_conf_d="$target_dir/install/utils"
  # choose the additional  my.cnf file for MySQL
  local mysql_version=$(get_mysql_version)
  if [ $? -eq 0 ]; then
    local mysql_ver_reduced=${mysql_version%.*}
    local my_cnf_src=""
    local my_cnf_src_dir="$custom_conf_d/my.cnf.d"
    local my_cnf_src_full="$my_cnf_src_dir/$mysql_version--my.cnf"
    local my_cnf_src_short="$my_cnf_src_dir/$mysql_ver_reduced--my.cnf"

    if [ -f "$my_cnf_src_full" ]; then
      my_cnf_src="$my_cnf_src_full"
    elif [ -f "$my_cnf_src_short" ]; then
      my_cnf_src="$my_cnf_src_short"
    fi

    if [ -n "$my_cnf_src" -a -f "$my_cnf_src" ]; then
      local my_cnf_dir
      my_cnf_dir=$(deref_os_prop "$target_dir" pathnames/etc/mysql_conf_d)
      if [ $? -eq 0 -a -d $my_cnf_dir ]; then
        local my_cnf_lnk="$my_cnf_dir/devpanel.cnf"
        ln -s "$my_cnf_src" "$my_cnf_lnk"

        # special lines for OpenVZ
        local openvz_cnf=""
        local openvz_cnf_full_ver="$my_cnf_src_dir/$mysql_version--openvz.cnf"
        local openvz_cnf_reduced_ver="$my_cnf_src_dir/$mysql_ver_reduced--openvz.cnf"
        if [ -f "$openvz_cnf_full_ver" ]; then
          openvz_cnf="$openvz_cnf_full_ver"
        elif [ -f "$openvz_cnf_reduced_ver" ]; then
          openvz_cnf="$openvz_cnf_reduced_ver"
        fi

        if [ -d /proc/vz -a -n "$openvz_cnf" -a -f "$openvz_cnf" ]; then
          ln -s "$openvz_cnf" "$my_cnf_dir"
        fi
      fi
    fi
  else
    sleep 3; # show the warning from the function
  fi

  local php_version=$(get_php_version)
  if [ $? -eq 0 ]; then
    local php_ver_reduced=${php_version%.*}
    local php_ini_src=""
    local php_ini_src_dir="$custom_conf_d/php.ini.d"
    local php_ini_src_full="$php_ini_src_dir/$php_version--php.ini"
    local php_ini_src_short="$php_ini_src_dir/$php_ver_reduced--php.ini"

    if [ -f "$php_ini_src_full" ]; then
      php_ini_src="$php_ini_src_full"
    elif [ -f "$php_ini_src_short" ]; then
      php_ini_src="$php_ini_src_short"
    fi
    
    local php_ini_d=$(deref_os_prop "$target_dir" pathnames/etc/php_ini_d)
    if [ -n "$php_ini_src" -a -d "$php_ini_d" -a -f "$php_ini_src" ]; then
      ln -s "$php_ini_src" "$php_ini_d/99-devpanel.ini"
    fi
  fi

  # if the installation is not run from bootstrap then update devpanel.conf
  # when running from bootstrap, the values have already been filled
  dp_config_file="$webenabled_install_dir/etc/devpanel.conf"
  if [ -n "$dp_server_uuid" -a -n "$dp_server_secret_key" ]; then

    ini_section_replace_key_value "$dp_config_file" taskd uuid "$dp_server_uuid"
    status=$?

    if [ $status -ne 0 ]; then
      echo
      echo "Warning: unable to set uuid in taskd.conf. Please " \
  "correct it manually in '$dp_config_file'. " \
  "Or your install will not work." >&2
      sleep 3
    fi

    ini_section_replace_key_value "$dp_config_file" taskd key "$dp_server_secret_key"
    status=$?

    if [ $status -ne 0 ]; then
      echo
      echo "Warning: unable to set key in taskd.conf. Please " \
  "correct it manually in '$dp_config_file'. " \
  "Or your install will not work." >&2
      sleep 3
    fi
  fi

  # if set, fill the api_url on the user_api section
  if [ -n "$dp_user_api_url" ]; then
    ini_section_replace_key_value "$dp_config_file" user_api api_url "$dp_user_api_url"
    if [ $? -ne 0 ]; then
      echo -e "\n\nWarning: unable to set user api url\n\n"
      sleep 3
    fi
  fi

  if [ -n "$dp_auto_register" ]; then
    ini_section_add_key_value "$dp_config_file" global auto_register 1
    if [ $? -ne 0 ]; then
      echo -e "\n\nWarning: unable to set auto_register on '$dp_config_file'\n\n"
      sleep 3
    fi
  fi

  if [ -n "$dp_tasks_api_url" ]; then
    ini_section_replace_key_value "$dp_config_file" taskd api_url "$dp_tasks_api_url"
    if [ $? -ne 0 ]; then
      echo -e "\n\nWarning: unable to set taskd api url\n\n"
      sleep 3
    fi
  fi

  local dbmgr_conf_dir="$webenabled_install_dir/compat/dbmgr/config"
  cp -f "$dbmgr_conf_dir/db-daemons.conf"{.template,}
  cp -f "$dbmgr_conf_dir/db-shadow.conf"{.template,}
  chmod 600 "$dbmgr_conf_dir/db-shadow.conf"

  chown root:"$_apache_exec_group" "$webenabled_install_dir/var/tokens"
  chmod 711 "$webenabled_install_dir/var/tokens"

  # when running manually (not from the automated install), we need to
  # (re-)start taskd.
  #
  # when running from the front-end install (and installing from the
  # bootstrap pkg), we don't restart taskd because it needs to notify the
  # status of the installation script
  if [ -z "$from_bootstrap" -a \
      -n "$dp_tasks_api_url" -a -n "$dp_server_uuid" -a \
      -n  "$dp_server_secret_key"  ]; then

    "$webenabled_install_dir/libexec/system-services" devpanel-taskd stop

    "$webenabled_install_dir/libexec/system-services" devpanel-taskd start
    if [ $? -ne 0 ]; then
      echo -e "\n\nError: unable to start taskd.\n\n"
      sleep 3
    fi
  fi

  "$webenabled_install_dir/libexec/update-packages" -y

  "$webenabled_install_dir/compat/suexec/chcgi" w_ +7
  
  #Install Zabbix Agent
  if [ -z "$we_v1_compat" ]; then
    $webenabled_install_dir/install/install-zabbix on $dp_server_hostname
  fi

  return 0
}

# main

[ $# -eq 0 ] && usage

if [ $EUID -ne 0 ]; then
  echo "Error: This script needs to run with ROOT privileges." 1>&2
  exit 1
fi

shopt -s expand_aliases

current_dir=`dirname "${BASH_SOURCE[0]}"`
install_source_dir=`readlink -e "$current_dir/.."`
if [ $? -ne 0 ]; then
  error "unable to determine local source dir"
fi

echo -e "\nStarting DevPanel installation from '$install_source_dir'\n" 1>&2

# load some utility functions required by the install
. "$install_source_dir"/lib/variables || \
  { echo "Error. Unable to load auxiliary variables" 1>&2; exit 1; }

. "$install_source_dir"/lib/functions || \
  { echo "Error. Unable to load auxiliary functions" 1>&2; exit 1; }


# create a lock file to avoid multiple install attempts running at the same
# time
lock_file="/var/run/devpanel_install.lock"
if ! ln -s /dev/null "$lock_file"; then
  error "there seems to have another installation running. Cannot create lock file '$lock_file'."
fi
trap 'ex=$?; rm -f "$lock_file" ; trap - EXIT INT HUP TERM; exit $ex' EXIT INT HUP TERM


getopt_flags="I:L:V:H:U:K:u:A:hdRbW"

unset from_bootstrap we_v1_compat
while getopts $getopt_flags OPTS; do
  case "$OPTS" in
    d)
      set -x
      ;;
    L)
      linux_distro="$OPTARG"
      ;;
    I)
      webenabled_install_dir="$OPTARG"
      ;;
    V)
      distro_version="$OPTARG"
      ;;
    H)
      dp_server_hostname="$OPTARG"
      ;;
    U)
      dp_server_uuid="$OPTARG"
      ;;
    K)
      dp_server_secret_key="$OPTARG"
      ;;
    u)
      dp_user_api_url="$OPTARG"
      ;;
    A)
      dp_tasks_api_url="$OPTARG"
      ;;
    R)
      dp_auto_register=1
      ;;
    b)
      from_bootstrap=1
      ;;
    W)
      we_v1_compat=1
      ;;
    h|*)
      usage
      ;;
  esac
done
[ -n "$OPTIND" -a $OPTIND -gt 1 ] && shift $(( $OPTIND - 1 )) 

if [ -z "$webenabled_install_dir" ]; then
  error "please specify the target installation directory with the -I option"
fi

if [[ "$webenabled_install_dir" =~ ^(/+\.*)+$ ]]; then
  error "the install directory can't be equal /"
fi

if [ -n "$from_bootstrap" -a -e "$webenabled_install_dir" ]; then
  rm -rf "$webenabled_install_dir"
elif [ -z "$from_bootstrap" ] && [ -L "$webenabled_install_dir" -o -e "$webenabled_install_dir" ]; then
  error "directory '$webenabled_install_dir' already exists"
fi

if [ -e "$webenabled_install_dir/config/os" ]; then
  error "this software seems to be already installed. To reinstall, please clean up the previous installation."
fi

# TODO: lsb_release install

if [ -z "$linux_distro" ]; then
  linux_distro=$(wedp_auto_detect_distro)
  status=$?
  if [ $status -ne 0 ]; then
    error "unable to detect linux distribution. If you know the distro, try using the -L option"
  fi
fi

source_config_dir="$install_source_dir/config/os.$linux_distro"
source_config_shortcut=`dirname "$source_config_dir"`/os
if [ ! -e "$source_config_dir" ]; then
  error "missing the configuration directory for distro '$linux_distro'.
There seems to be a problem in this installation package."
  exit 1
else
  # link the source dir /os/ link to be used by function set_variables
  if ! ln -sf $(basename "$source_config_dir") "$source_config_shortcut"; then
    error "unable to link source config shortcut $source_config_shortcut"
  fi
fi

distro_version=$(wedp_auto_detect_distro_version "$linux_distro") || exit 1
distro_ver_major=$(devpanel_get_os_version_major)
distro_ver_minor=$(devpanel_get_os_version_minor)

set_global_variables "$install_source_dir" "$webenabled_install_dir" \
  "$linux_distro" "$distro_version" "$distro_ver_major" "$distro_ver_minor"
if [ $? -ne 0 ]; then
  error "unable to properly set global variables"
fi

distro_install_script="$install_source_dir/install/install.$linux_distro.sh"
if [ ! -e "$distro_install_script" ]; then
  error "install script '$distro_install_script' is missing"
elif [ ! -f "$distro_install_script" ]; then
  error "'$distro_install_script' is not a regular file"
fi

. "$distro_install_script"
status=$?
if [ $status -ne 0 ]; then
  error "problems in script '$distro_install_script'"
fi

for func in set_variables pre_run; do
  if [ "$(type -t ${linux_distro}_$func)" == "function" ]; then
    ${linux_distro}_$func "$install_source_dir" "$webenabled_install_dir" \
      "$linux_distro" "$distro_version" "$distro_ver_major" \
      "$distro_ver_minor"
    status=$?
    [ $status -ne 0 ] && error "${linux_distro}_$func returned $status"
  fi
done

if type -t "${linux_distro}_install_distro_packages" >/dev/null; then
  "${linux_distro}_install_distro_packages" "$install_source_dir" \
    "$webenabled_install_dir" "$linux_distro" "$distro_version"   \
    "$distro_ver_major" "$distro_ver_minor"
  if [ $? -ne 0 ]; then
    error "failed to install required packages"
  fi
fi

add_custom_users_n_groups "$install_source_dir" "$webenabled_install_dir"

if type -t "${linux_distro}_post_users_n_groups" >/dev/null; then
  "${linux_distro}_post_users_n_groups" "$webenabled_install_dir"
fi

if ! install_ce_software "$linux_distro" "$install_source_dir" \
  "$webenabled_install_dir"; then
  error "unable to run the main software install routine"
fi

if ! post_software_install "$linux_distro" "$install_source_dir" \
  "$webenabled_install_dir"; then
  error "failed to execute the post install routine"
fi

if type -t "${linux_distro}_post_software_install" >/dev/null; then
  "${linux_distro}_post_software_install" "$install_source_dir" "$webenabled_install_dir"
fi

if type -t "${linux_distro}_adjust_system_config" >/dev/null; then
  "${linux_distro}_adjust_system_config" "$webenabled_install_dir"
fi

# reload Apache just before the end of the installation
"$_apachectl_bin" configtest
if [ $? -ne 0 ]; then
  echo
  echo "Warning: apache configuration test failed. Please verify!" >&2
  sleep 3
else
  "$_apachectl_bin" stop &>/dev/null
  sleep 2 # on Debian if we don't sleep the start gets port already in use
  "$_apachectl_bin" start
fi

# WE v1.0 backwards compatibility changes
if [ -n "$we_v1_compat" ]; then
  if ! getent passwd r_we &>/dev/null; then
    shell_escaped=$(escape_sed "$webenabled_install_dir/libexec/server")
    sed -i -e '/^root:/ { s/^root:\(.\+\)$/&\
r_we:\1/;
  s/:[^:]\+:[^:]\+$/:\/home\/r_we:'"$shell_escaped"'/;
   }' /etc/passwd

    sed -i -e '/^root:/ { s/^root:[^:]\+:\(.*\)/&\
r_we:x:\1/}' /etc/shadow
  fi

  [ ! -d /home/r_we ] && \
    cp -a "$webenabled_install_dir/install/skel/home/r_we/" \
      /home/r_we

  chown -R 0:0 /home/r_we
  chmod 700 /home/r_we
  chmod 700 /home/r_we/.ssh
  chmod 600 /home/r_we/.ssh/authorized_keys

  ln -s . "$webenabled_install_dir/current"

  echo "set-local webenabled_backwards 1" | "$webenabled_install_dir/libexec/system-metadata-handler"
fi

echo
echo "Installation completed successfully"
