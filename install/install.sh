#!/bin/bash

# default install dir.  can be overwritten with -I
webenabled_install_dir="/opt/webenabled"

# default websites base dir, can be overwritten with -H
webenabled_homedir_base="/home/clients/websites"

# default databases base dir, can be overwritten with -D
webenabled_databasedir_base="/home/clients/databases"

usage() {
  local prog=`basename "$0"`
  echo "
Usage: $prog <-d webenabled_install_directory>

  Options:
    -L distro         Assume the specified distro, don't try to auto-detect
    -I directory      Install the software in the specified directory
    -h                Displays this help message
    -d                print verbose debug messages
    -H directory      Create sites directories under this path
    -D directory      Create database directories under this path
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

  _git_user="git"

  return 0
}

install_ce_software() {
  local linux_distro="$1"
  local source_dir="$2"
  local webenabled_install_dir="$3"
  local machine_type=$(uname -m)

  if ! cp -a "$source_dir" \
    $(dirname "$webenabled_install_dir" ); then
    echo "Error: unable to copy installation files to target dir" >&2
    return 1
  fi

  chmod 755 "$webenabled_install_dir"

  ln -snf os.$linux_distro "$webenabled_install_dir"/config/os

  mkdir -p "$webenabled_homedir_base" "$webenabled_databasedir_base"
  chmod 0755 "$webenabled_homedir_base" "$webenabled_databasedir_base"

  ln -snf "$webenabled_install_dir"/compat/w_ "$webenabled_homedir_base"/w_
  chown -R w_:"$_apache_exec_group" "$webenabled_install_dir"/compat/w_

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

  mkdir -p `readlink -m "$webenabled_install_dir"/config/os/pathnames/etc/ssl/certs`
  mkdir -p `readlink -m "$webenabled_install_dir"/config/os/pathnames/etc/ssl/keys`
  #openssl req -subj "/C=--/ST=SomeState/L=SomeCity/O=SomeOrganization/OU=SomeOrganizationalUnit/CN=*.`hostname`" -new -x509 -days 3650 -nodes -out /opt/webenabled/config/os/pathnames/etc/ssl/certs/wildcard -keyout /opt/webenabled/config/os/pathnames/etc/ssl/keys/wildcard
  cp -a "$source_dir"/install/old/cloudenabled/wildcard.cloudenabled.net.key "$webenabled_install_dir"/config/os/pathnames/etc/ssl/keys/wildcard
  cp -a "$source_dir"/install/old/cloudenabled/wildcard.cloudenabled.net.crt "$webenabled_install_dir"/config/os/pathnames/etc/ssl/certs/wildcard

  # echo Vhost-simple-SSL-wildcard > "$webenabled_install_dir"/config/names/apache-macro
  echo Vhost-simple > "$webenabled_install_dir"/config/names/apache-macro

  if [ -e "$_apache_vhost_logs_dir" -a ! -d "$_apache_vhost_logs_dir" ]; then
    mv "$_apache_vhost_logs_dir" "$_apache_vhost_logs_dir".old
  elif [ ! -d "$_apache_vhost_logs_dir" ]; then
    mkdir -p "$_apache_vhost_logs_dir"
  fi
  chmod 755 "$_apache_vhost_logs_dir"

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
  useradd -M -c "$comment" -d "$webenabled_homedir_base"/w_ -G w_ -g "$_apache_group" w_
  useradd -m -c "$comment" -d "/home/devpanel" devpanel

  useradd -m \
    -c "account for managing DevPanel git repos. Please don't remove" "$_git_user"

  if [ $? -eq 0 ]; then
    su -l -s /bin/bash -c "[ ! -d ~/.ssh ] && mkdir -m 700 ~/.ssh ; \
     [ -d ~/.ssh ] && ssh-keygen -f ~/.ssh/id_rsa -b 4096 -P ''" "$_git_user"

    if [ $? -eq 0 ]; then
      su -l "$webenabled_install_dir/backend-scripts/bin/gitolite \
              setup -pk ~/.ssh/id_rsa.pub" "$_git_user"
    fi
  else
    echo
    echo
    echo "Warning: failed to setup account for git management" 1>&2
    echo
    echo
    sleep 3
  fi

  usermod -a -G virtwww "$_apache_user"
}

# main

[ $# -eq 0 ] && usage

if [ $EUID -ne 0 ]; then
  echo "Error: This script needs to run with ROOT privileges." 1>&2
  exit 1
fi

shopt -s expand_aliases

install_source_dir="${BASH_SOURCE[0]}/.."
if [ $? -ne 0 ]; then
  echo "Error: unable to determine the source directory. Please execute"\
 " this script again calling it with the full path." 1>&2
  exit 1
fi

. "$install_source_dir"/lib/variables || \
  { echo "Error. Unable to load variables" 1>&2; exit 1; }

. "$install_source_dir"/lib/functions || \
  { echo "Error. Unable to load functions" 1>&2; exit 1; }


lock_file="/var/run/devpanel_install.lock"
if ! ln -s /dev/null "$lock_file"; then
  error "there seems to have another installation running. Cannot create lock file '$lock_file'."
fi
trap 'rm -f "$lock_file" ; trap - EXIT INT HUP TERM; exit 1' EXIT INT HUP TERM


getopt_flags="I:L:H:D:V:hd"

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
    H)
      webenabled_homedir_base="$OPTARG"
      ;;
    D)
      webenabled_databasedir_base="$OPTARG"
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

set_global_variables "$install_source_dir" "$webenabled_install_dir" "$linux_distro" || exit 1

distro_install_script="install.$linux_distro.sh"
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

if type -t "${linux_distro}_post_software_install" >/dev/null; then
  "${linux_distro}_post_software_install" "$webenabled_install_dir"
fi

if type -t "${linux_distro}_adjust_system_config" >/dev/null; then
  "${linux_distro}_adjust_system_config" "$webenabled_install_dir"
fi

taskd_config_file="$webenabled_install_dir/config/devpanel.conf"
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

if ! grep -q taskd /etc/rc.local; then
  sed -i -e "/^exit / i\
[ -x $webenabled_install_dir/sbin/taskd ] && $webenabled_install_dir/sbin/taskd" /etc/rc.local
fi

if [ -n "$WEBENABLED_VPS_HOSTNAME" ]; then
  "$webenabled_install_dir/libexec/config-vhost-names-default" \
    "$WEBENABLED_VPS_HOSTNAME"
fi

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
