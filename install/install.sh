#!/bin/bash
umask 022

# default install dir.  can be overwritten with -I
webenabled_install_dir="/opt/webenabled"

usage() {
  local prog=`basename "$0"`
  echo "
Usage: $prog [ options ] -Y

  Options:
    -2                this host will connect to platform version 2
    -3                this host will connect to platform version 3
    -L distro         Assume the specified distro, don't try to auto-detect
    -I directory      Install the software in the specified directory
    -H hostname       hostname to use on the network services
    -U server_uuid    UUID of the server to configure on devpanel.conf
    -K secret_key     Secret key of the server to configure on devpanel.conf
    -u api_url        URL of the user api
    -A tasks_url      URL of the tasks api
    -h                Displays this help message
    -d                print verbose debug messages
    -b                from bootstrap (don't update devpanel.conf and don't
                      restart taskd)
    -W                Webenabled v1.0 backwards compatibility
    -Y                confirm the intent to install (just to avoid
                      accidental start of installs)

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

  _apache_logs_dir="$lamp__apache_paths__logs_dir"

  _apache_vhost_logs_dir="$lamp__apache_paths__vhost_logs_dir"

  _apache_base_dir="$lamp__apache_paths__base_dir"

  _apache_includes_dir="$lamp__apache_paths__includes_dir"

  _apache_vhosts="$lamp__apache_paths__vhosts_include_dir"

  _apache_main_config_file="$lamp__apache_paths__main_config_file"

  _apache_main_include="$lamp__apache_includes__main"

  _apachectl_bin="$lamp__apache_paths__apachectl"


  _apache_user="$lamp__apache__user"

  _apache_group="$lamp__apache__group"

  _apache_exec_group="$lamp__apache__exec_group"

  homedir_base="$lamp__apache_paths__virtwww_homedir"

  databasedir_base="$lamp__mysql_paths__instances_homedir"

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

  mkdir -m 755 -p "$webenabled_install_dir" \
    "$homedir_base" "$databasedir_base" "$data_dir"
  
  if ! cp -dR --preserve=mode,timestamps "$source_dir/." \
        "$webenabled_install_dir"; then

    echo "Error: unable to copy installation files to target dir" >&2
    return 1
  fi

  local t_dir
  for t_dir in "$skel_dir_common" "$skel_dir_major" "$skel_dir_major_minor"; do
    if [ -d "$t_dir" ]; then
      cp -dRn --preserve=mode,timestamps "$t_dir/." /
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

  ln -s /etc/devpanel/lamp/apache/virtwww "$lamp__apache_paths__vhosts_include_dir"

  ln -sf "$webenabled_install_dir/compat/apache_include/$_apache_main_include" \
    "$_apache_includes_dir/devpanel.conf"

  # link to /usr/bin to have devpanel cli in the $PATH
  # NOTE: not using /usr/local/bin because CentOS doesn't have it in the
  #       $PATH by default
  ln -sf "$webenabled_install_dir/bin/devpanel" /usr/bin

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

  # See : https://help.webstandard.com/issues/7421
  if [ `grep -c apache /etc/passwd` -eq 0 ]; then
    useradd -m apache
  fi

  usermod -a -G virtwww "$_apache_user"

}

post_software_install() {
  local linux_distro="$1"
  local source_dir="$2"
  local target_dir="$3"

  local status

  if [ -n "$dp_server_hostname" ]; then
    devpanel init config --hostname "$dp_server_hostname"
  else
    devpanel init config --gen-hostname-from-ip
  fi

  local custom_conf_d="$target_dir/install/utils"

  # choose the additional  my.cnf file for MySQL
  local mysql_version=$(get_mysql_version)
  if [ $? -eq 0 ]; then
    local mysql_ver_reduced=${mysql_version%.*}
    local my_cnf_src_dir="$custom_conf_d/my.cnf.d"

    my_cnf_dir="$conf__mysql_paths__conf_d"
    if [ -d "$my_cnf_dir" ]; then
      # special lines for VPSs running on OpenVZ
      local openvz_cnf openvz_cnf_full_ver openvz_cnf_reduced_ver
      openvz_cnf_full_ver="$my_cnf_src_dir/$mysql_version--openvz.cnf"
      openvz_cnf_reduced_ver="$my_cnf_src_dir/$mysql_ver_reduced--openvz.cnf"
      if [ -f "$openvz_cnf_full_ver" ]; then
        openvz_cnf="$openvz_cnf_full_ver"
      elif [ -f "$openvz_cnf_reduced_ver" ]; then
        openvz_cnf="$openvz_cnf_reduced_ver"
      fi

      if [ -d /proc/vz -a -n "$openvz_cnf" ]; then
        openvz_cnf_target="$my_cnf_dir/zzz-devpanel-openvz.cnf"
        cp "$openvz_cnf" "$openvz_cnf_target"
      fi
    fi
  else
    sleep 3; # show the warning from the function
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

  "$webenabled_install_dir/libexec/package-mgr" update-all -y

  "$webenabled_install_dir/compat/suexec/chcgi" w_ +7
  
  if [ -n "$lamp__php__default_version_on_install" ]; then
    devpanel set default php --version "$lamp__php__default_version_on_install"
  fi

  #Install Zabbix Agent
  if [ -n "$platform_version" -a "$platform_version" == 2 ]; then
    $webenabled_install_dir/install/install-zabbix on $dp_server_hostname
  fi

  return 0
}

is_this_distro_version_supported() {
  local i_dir="$1"
  local distro="$2"
  local major="$3"
  local minor="$4"

  local dir_1="$i_dir/stacks/lamp/distros/$distro/$major"
  local dir_2="$i_dir/stacks/lamp/distros/$distro/$major.$minor"

  local t_dir found_config_dir
  for t_dir in $dir_1 $dir_2; do
    if [ -d "$t_dir" ]; then
      found_config_dir=1
      break
    fi
  done

  if [ -n "$found_config_dir" ]; then
    return 0
  else
    return 1
  fi
}

# main

[ $# -eq 0 ] && usage

if [ $EUID -ne 0 ]; then
  echo "Error: This script needs to run with ROOT privileges." 1>&2
  exit 1
fi

shopt -s expand_aliases

[ -n "${BASH_SOURCE[0]}" ] && self_bin=`readlink -e "${BASH_SOURCE[0]}"`
if [ $? -ne 0 ]; then
  error "unable to determine self path"
fi
install_source_dir="${self_bin%/*/*}"

getopt_flags="I:L:H:U:K:u:A:hdbW23Y"

unset from_bootstrap we_v1_compat platform_version confirmed
while getopts $getopt_flags OPTS; do
  case "$OPTS" in
    2|3)
      if [ -n "$platform_version" -a "$platform_version" != $OPTS ]; then
        error "only one platform version can be specified at a time."
      fi
      platform_version=$OPTS
      ;;
    d)
      set -x
      ;;
    L)
      linux_distro="$OPTARG"
      ;;
    I)
      webenabled_install_dir="$OPTARG"
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
    b)
      from_bootstrap=1
      ;;
    W)
      platform_version=1
      we_v1_compat=1
      ;;
    Y)
      confirmed=yes
      ;;
    h|*)
      usage
      ;;
  esac
done
[ -n "$OPTIND" -a $OPTIND -gt 1 ] && shift $(( $OPTIND - 1 )) 

# load some utility functions required by the install
. "$install_source_dir"/lib/functions || \
  { echo "Error. Unable to load auxiliary functions" 1>&2; exit 1; }

# set the platform version if none was specified above
platform_version=${platform_version:-3}

if [ -z "$confirmed" ]; then
  error "please add the -Y option to confirm the intent to install."
fi

# create a lock file to avoid multiple install attempts running at the same
# time
lock_file="/var/run/devpanel_install.lock"
if ! ln -s /dev/null "$lock_file"; then
  error "there seems to have another installation running. Cannot create lock file '$lock_file'."
fi
trap 'ex=$?; rm -f "$lock_file" ; trap - EXIT INT HUP TERM; exit $ex' EXIT INT HUP TERM

if [ -n "$webenabled_install_dir" ]; then
  if real_dir=$(readlink -m "$webenabled_install_dir"); then
    if [ "$real_dir" == / ]; then
      error "the install directory can't be equal to /"
    fi
  else
    error "unable to dereference path '$webenabled_install_dir'"
  fi
else
  error "please specify the target installation directory with the -I option"
fi

if [ -n "$from_bootstrap" -a -e "$webenabled_install_dir" ]; then
  rm -rf "$webenabled_install_dir"
elif [ -z "$from_bootstrap" ] && [ -L "$webenabled_install_dir" -o -e "$webenabled_install_dir" ]; then
  error "destination directory '$webenabled_install_dir' already exists"
fi

echo -e "\nStarting DevPanel installation from '$install_source_dir'\n" 1>&2

if [ -z "$linux_distro" ]; then
  linux_distro=$(wedp_auto_detect_distro)
  status=$?
  if [ $status -ne 0 ]; then
    error "unable to detect linux distribution. If you know the distro, try using the -L option"
  fi
fi

distro_version=$(wedp_auto_detect_distro_version "$linux_distro") || exit 1
distro_ver_major=$(devpanel_get_os_version_major "$distro_version" )
distro_ver_minor=$(devpanel_get_os_version_minor "$distro_version" )

if ! is_this_distro_version_supported "$install_source_dir" \
      "$linux_distro" "$distro_ver_major" "$distro_ver_minor"; then
  error "linux distribution not supported."
fi

load_devpanel_config || exit $?

if [ -d "$lamp__paths__local_config_dir" ]; then
  error "this software seems to be already installed." \
"To reinstall, please clean up the previous installation."
fi

set_global_variables "$install_source_dir" "$webenabled_install_dir" \
  "$linux_distro" "$distro_version" "$distro_ver_major" "$distro_ver_minor"
if [ $? -ne 0 ]; then
  error "unable to properly set global variables"
fi

# the linking to config/os/ below is almost obsolete. Though it's still used
# by a few critical software like the suexec binary. So have to keep it.
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
apache_configtest
if [ $? -ne 0 ]; then
  echo
  echo "Warning: apache configuration test failed. Please verify!" >&2
  sleep 3
else
  reload_or_start_apache
fi

if [ -n "$we_v1_compat" ]; then
  # WE v1.0 backwards compatibility
  devpanel enable webenabled compat --yes
fi

if [ -n "$platform_version" ]; then
  devpanel set platform version --version $platform_version
  if [ "$platform_version" == 3 ]; then
    devpanel enable long vhost names --yes
  fi
fi

state_file=/var/spool/devpanel/state.ini
if [ -n "$conf__migrations__latest_step" -a -f "$state_file" ]; then
  write_ini_file "$state_file" \
    "migrations.latest_step = $conf__migrations__latest_step"
fi

echo
echo "Installation completed successfully"
