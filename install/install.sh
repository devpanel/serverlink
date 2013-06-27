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
Usage: $prog <-d webenabled_install_directory>

  Options:
    -L distro         Assume the specified distro, don't try to auto-detect
    -I directory      Install the software in the specified directory
    -h                Displays this help message
    -d                print verbose debug messages
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

  # initialize global variables used throughout this script

  local we_config_dir="$source_dir/config"

  _suexec_bin=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/sbin/suexec")
  if [ $? -ne 0  -o -z "$_suexec_bin" ]; then
    echo "unable to set global variable _suexec_bin" 1>&2
    return 1
  fi
  _apache_logs_dir=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/var/log/apache_logs_dir")
  if [ $? -ne 0  -o -z "$_apache_logs_dir" ]; then
    echo "unable to set global variable _apache_logs_dir" 1>&2
    return 1
  fi

   _apache_vhost_logs_dir=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/var/log/apache_vhosts")
  if [ $? -ne 0  -o -z "$_apache_vhost_logs_dir" ]; then
    echo "unable to set global variable _apache_vhost_logs_dir" 1>&2
    return 1
  fi
  
  _apache_base_dir=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/etc/apache_base_dir")
  if [ $? -ne 0  -o -z "$_apache_base_dir" ]; then
    echo "unable to set global variable _apache_base_dir" 1>&2
    return 1
  fi

  _apache_includes_dir=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/etc/apache_includes_dir")
  if [ $? -ne 0  -o -z "$_apache_includes_dir" ]; then
    echo "unable to set global variable _apache_includes_dir" 1>&2
    return 1
  fi

  _apache_vhosts=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/etc/apache_vhosts")
  if [ $? -ne 0  -o -z "$_apache_vhosts" ]; then
    echo "unable to set global variable _apache_vhosts" 1>&2
    return 1
  fi

  _apache_vhosts_removed=$(wedp_resolve_link "$we_config_dir/os.$distro/pathnames/etc/apache_vhosts_removed")
  if [ $? -ne 0  -o -z "$_apache_vhosts_removed" ]; then
    echo "unable to set global variable _apache_vhosts_removed" 1>&2
    return 1
  fi

  _apache_user=`head -1 "$we_config_dir/os.$distro/names/apache.user"`
  if [ $? -ne 0 -o -z "$_apache_user" ]; then
    echo "unable to resolve apache user" 1>&2
    return 1
  fi


  _apache_group=`head -1 "$we_config_dir/os.$distro/names/apache.group"`
  if [ $? -ne 0 ]; then
    echo "unable to resolve apache group" 1>&2
    return 1
  fi

  _apache_exec_group=`head -1 "$we_config_dir/os.$distro/names/apache-exec.group"`
  if [ $? -ne 0 ]; then
    echo "unable to resolve apache exec group" 1>&2
    return 1
  fi

  _apache_main_config_file=`readlink "$we_config_dir/os.$distro/pathnames/etc/apache_main_config_file"`
  if [ $? -ne 0 -o -z "$_apache_main_config_file" ]; then
    echo "unable to resolve apache_main_config_file" 1>&2
    return 1
  fi

  _git_user="git"

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

  cp -f "$source_dir/install/config/devpanel.conf.template" "$webenabled_install_dir/etc/devpanel.conf"

  # start of setup of suexec (DevPanel uses a custom suexec)
  local we_suexec_path="$webenabled_install_dir/compat/suexec/suexec"
  
  if [ -L "$_suexec_bin" ]; then
    rm "$_suexec_bin"
  elif [ -e "$_suexec_bin" ] && ! mv -f "$_suexec_bin" "$_suexec_bin.dist"; then
    echo "error: unable to move distro default suexec binary" >&2
    return 1
  fi

  ln -sf "$we_suexec_path.$linux_distro.$machine_type" "$we_suexec_path"
  ln -sf "$webenabled_install_dir/compat/suexec/chcgi.$machine_type" \
    "$webenabled_install_dir/compat/suexec/chcgi"

  if ! ln -sf "$we_suexec_path" "$_suexec_bin"; then
    echo "error: unable to link suexec to distro suexec path '$_suexec_bin'" >&2
    return 1
  fi

  chown 0:"$_apache_group" "$_suexec_bin"
  chmod 4711 "$_suexec_bin"
  chown 0:"$_apache_group" "$we_suexec_path"
  chmod 4711 "$we_suexec_path"
  chown 0:0 "$webenabled_install_dir/compat/suexec/config/suexec.map"
  chmod 0600 "$webenabled_install_dir/compat/suexec/config/suexec.map"
  # end of suexec setup

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
Include $webenabled_install_dir/compat/apache_include/virtwww/*.conf" \
    >> "$webenabled_install_dir/compat/apache_include/webenabled.conf.main"

  ln -sf "$webenabled_install_dir/compat/apache_include/webenabled.conf.main" \
    "$_apache_includes_dir/webenabled.conf"

  ln -s "utils.$machine_type" \
    "$webenabled_install_dir/bin/utils"

  return 0
}

add_custom_users_n_groups() {
  local source_dir="$1"
  local webenabled_install_dir="$2"

  for u in w_ virtwww weadmin; do
    if ! getent group $u >/dev/null; then
      groupadd $u || true
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
  useradd -M -c "$comment" -d "$homedir_base"/w_ -G w_ -g "$_apache_group" w_
  useradd -m -c "$comment" -d "/home/devpanel" devpanel

  usermod -a -G virtwww "$_apache_user"
}

post_software_install() {
  # start setting up user for git management
  useradd -m \
    -c "account for managing DevPanel git repos. Please don't remove" "$_git_user"

  if [ $? -eq 0 ]; then
    su -l -s /bin/bash -c "[ ! -d ~/.ssh ] && mkdir -m 700 ~/.ssh ; \
     [ -d ~/.ssh ] && ssh-keygen -f ~/.ssh/id_rsa -b 4096 -P ''" "$_git_user"

    if [ $? -eq 0 ]; then
      su -l -c "$webenabled_install_dir/bin/gitolite \
              setup -pk ~/.ssh/id_rsa.pub" "$_git_user"
    fi
  else
    echo -e "\n\nWarning: failed to setup account for git management\n\n" 1>&2
    sleep 3
  fi
  # end of git setup section

  taskd_config_file="$webenabled_install_dir/etc/devpanel.conf"
  if [ -n "$WEBENABLED_SERVER_UUID" \
    -a -n "$WEBENABLED_SERVER_SECRET_KEY" ]; then

    ini_section_replace_value "$taskd_config_file" taskd uuid "$WEBENABLED_SERVER_UUID"
    status=$?

    if [ $status -ne 0 ]; then
      echo
      echo "Warning: unable to set uuid in taskd.conf. Please " \
  "correct it manually in '$taskd_config_file'. " \
  "Or your install will not work." >&2
      sleep 3
    else
      "$webenabled_install_dir/sbin/taskd"
    fi
  fi

  if [ -n "$WEBENABLED_VPS_HOSTNAME" ]; then
    "$webenabled_install_dir/libexec/config-vhost-names-default" \
      "$WEBENABLED_VPS_HOSTNAME"

    # add the hostname to the apache main file, in case it's not configured
    # to avoid the warning when restarting Apache
    if ! egrep -qs '^[[:space:]]*ServerName' "$_apache_main_config_file"; then
      sed -i -e "0,/^#[[:space:]]*ServerName[[:space:]]\+[A-Za-z0-9:.-]\+$/ {
      /^#[[:space:]]*ServerName[[:space:]]\+[A-Za-z0-9:.-]\+$/ {
      a\
ServerName $WEBENABLED_VPS_HOSTNAME
;
      }  }" "$_apache_main_config_file"
    fi


  fi

  "$webenabled_install_dir/config/os/pathnames/sbin/apachectl" configtest
  if [ $? -ne 0 ]; then
    echo
    echo "Warning: apache configuration test failed. Please verify!" >&2
    sleep 3
  else
    "$webenabled_install_dir/config/os/pathnames/sbin/apachectl" graceful
  fi


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


getopt_flags="I:L:V:hd"

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
      if [ -d "$webenabled_install_dir" ]; then
        error "directory '$webenabled_install_dir' already exists"
      fi
      ;;
    V)
      webenabled_distro_version="$OPTARG"
      ;;
    h|*)
      usage
      ;;
  esac
done
[ -n "$OPTIND" -a $OPTIND -gt 1 ] && shift $(( $OPTIND - 1 )) 

if [ -z "$webenabled_install_dir" ]; then
  error "please specify the target installation directory with the -d option"
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

if [ ! -e "$install_source_dir/config/os.$linux_distro" ]; then
  error "missing the configuration directory for distro '$linux_distro'.
There seems to be a problem in this installation package."
  exit 1
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

echo
echo "Installation completed successfully"
