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

  return 0
}

install_ce_software() {
  local linux_distro="$1"
  local source_dir="$2"
  local webenabled_install_dir="$3"
  local machine_type=$(uname -m)
  local distro_skel_dir="$webenabled_install_dir/install/skel/$linux_distro"

  mkdir -m 755 -p "$webenabled_install_dir" \
    "$homedir_base" "$databasedir_base"

  if ! ( cd "$source_dir" && cp -a . "$webenabled_install_dir" ); then
    echo "Error: unable to copy installation files to target dir" >&2
    return 1
  fi

  if [ -d "$distro_skel_dir" ]; then
    (cd "$distro_skel_dir" && cp -a . /)
    if [ $? -ne 0 ]; then
      echo -e "\n\nWarning: unable to copy distro skel files to /\n\n" 1>&2
      sleep 3
    fi
  fi

  # links shortcut to linux distribution specific files
  ln -snf os.$linux_distro "$webenabled_install_dir"/config/os

  ln -snf "$webenabled_install_dir"/compat/w_ "$homedir_base"/w_
  chown -R w_:"$_apache_exec_group" "$webenabled_install_dir"/compat/w_

  if [ ! -e "$webenabled_install_dir/etc/devpanel.conf" ]; then
    cp -f "$source_dir/install/config/devpanel.conf.template" "$webenabled_install_dir/etc/devpanel.conf"
  fi

  ssl_certs_dir=`readlink "$webenabled_install_dir"/config/os/pathnames/etc/ssl/certs`
  ssl_keys_dir=`readlink "$webenabled_install_dir"/config/os/pathnames/etc/ssl/keys`
  [ ! -d "$ssl_certs_dir" ] && mkdir -m 755 -p "$ssl_certs_dir"
  [ ! -d "$ssl_keys_dir"  ] && mkdir -m 755 -p "$ssl_keys_dir"

  # openssl req -subj "/C=--/ST=SomeState/L=SomeCity/O=SomeOrganization/OU=SomeOrganizationalUnit/CN=*.`hostname`" -new -x509 -days 3650 -nodes -out /opt/webenabled/config/os/pathnames/etc/ssl/certs/wildcard -keyout /opt/webenabled/config/os/pathnames/etc/ssl/keys/wildcard
  # cp -a "$source_dir"/install/old/cloudenabled/wildcard.cloudenabled.net.key "$webenabled_install_dir"/config/os/pathnames/etc/ssl/keys/wildcard
  # cp -a "$source_dir"/install/old/cloudenabled/wildcard.cloudenabled.net.crt "$webenabled_install_dir"/config/os/pathnames/etc/ssl/certs/wildcard

  # echo Vhost-simple-SSL-wildcard > "$webenabled_install_dir"/config/names/apache-macro
  echo Vhost-simple > "$webenabled_install_dir"/config/names/apache-macro

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

  ln -s "$_apache_logs_dir" "$_apache_base_dir/webenabled-logs"

  echo "
Include $webenabled_install_dir/compat/apache_include/*.conf
Include $webenabled_install_dir/compat/apache_include/custom/*.conf
Include $webenabled_install_dir/compat/apache_include/virtwww/*.conf" \
    >> "$webenabled_install_dir/compat/apache_include/webenabled.conf.main"

  ln -sf "$webenabled_install_dir/compat/apache_include/webenabled.conf.main" \
    "$_apache_includes_dir/webenabled.conf"

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
    useradd -M -c "$comment" -d "$homedir_base"/w_ -G w_ -g "$_apache_group" w_
  fi

  if ! getent passwd devpanel &>/dev/null; then
    echo "Adding user devpanel ..."; sleep 0.5
    useradd -m -c "$comment" -d "/home/devpanel" devpanel
  fi

  usermod -a -G virtwww "$_apache_user"
}

post_software_install() {
  local status

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

  # this one is not run on bootstrap, so we run it in normal install (don't
  # check for bootstrap
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

  "$webenabled_install_dir/libexec/update-packages"
}

# main

[ $# -eq 0 ] && usage

if [ $EUID -ne 0 ]; then
  echo "Error: This script needs to run with ROOT privileges." 1>&2
  exit 1
fi

shopt -s expand_aliases

current_dir=`dirname "${BASH_SOURCE[0]}"`
if [ -n "$DP_INSTALL_SOURCE_DIR" -a -d "$DP_INSTALL_SOURCE_DIR" ]; then
  install_source_dir="$DP_INSTALL_SOURCE_DIR"
else
  if [ "$current_dir" == "." ]; then
    current_dir="$PWD"
  elif [ "${current_dir:0:1}" != "/" ]; then
    current_dir="$PWD/$current_dir"
  fi

  install_source_dir=${current_dir%/*}
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


getopt_flags="I:L:V:H:U:K:u:A:hdRb"

unset from_bootstrap
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
      webenabled_distro_version="$OPTARG"
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
  if ! ln -sf "$source_config_dir" "$source_config_shortcut"; then
    error "unable to link source config shortcut $source_config_shortcut"
  fi
fi

if [ -z "$webenabled_distro_version" ]; then
  webenabled_distro_version=$(wedp_auto_detect_distro_version "$linux_distro")
fi

if ! set_global_variables "$install_source_dir" "$webenabled_install_dir" "$linux_distro"; then
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
    ${linux_distro}_$func "$webenabled_install_dir" \
      "$webenabled_distro_version"
    status=$?
    [ $status -ne 0 ] && error "${linux_distro}_$func returned $status"
  fi
done

if type -t "${linux_distro}_install_distro_packages" >/dev/null; then
  "${linux_distro}_install_distro_packages" "$webenabled_install_dir" \
    "$webenabled_distro_version"
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
"$webenabled_install_dir/config/os/pathnames/sbin/apachectl" configtest
if [ $? -ne 0 ]; then
  echo
  echo "Warning: apache configuration test failed. Please verify!" >&2
  sleep 3
else
  "$webenabled_install_dir/config/os/pathnames/sbin/apachectl" graceful
fi

echo
echo "Installation completed successfully"
