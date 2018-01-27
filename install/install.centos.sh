#!/bin/bash 

centos_set_variables() {
  return 0
}

centos_pre_run() {
  return 0
}

centos_install_distro_packages() {
  local source_dir="$1"
  local install_dir="$2"
  local distro="$3"
  local distro_ver="$4"
  local distro_ver_major="$5"
  local distro_ver_minor="$6"
 
  # install external repositories needed
  local distro_config_dir="$source_dir/config/os.$distro"
  local repos_dir_tmpl="$distro_config_dir/@version@/repositories"
  local repos_link repos_dir_1 repos_dir_2 repos_dir_3 repos_rpm_file

  local distro_ver_major_minor="$distro_ver_major.$distro_ver_minor"

  repos_dir_1="${repos_dir_tmpl//@version@/$distro_ver}"
  repos_dir_2="${repos_dir_tmpl//@version@/$distro_ver_major_minor}"
  repos_dir_3="${repos_dir_tmpl//@version@/$distro_ver_major}"

  for repos_link in "$repos_dir_1/repos."[0-9]*.* \
                    "$repos_dir_2/repos."[0-9]*.* \
                    "$repos_dir_3/repos."[0-9]*.* ; do

    if [ ! -L "$repos_link" ]; then
      continue
    fi

    repos_rpm_file=$(readlink -e "$repos_link")
    if [ $? -ne 0 ]; then
      echo "$FUNCNAME(): warning, link $repos_link doesn't resolve" 1>&2
      sleep 2
      continue
    fi

    rpm -Uvh "$repos_rpm_file"
  done

  ###############################################
  # workaround for mysql on low memory servers  #
  ###############################################
  # copy /etc/my.cnf.d/ in place with the lower memory defaults, so that the
  # mysqld is able to start just after install (that is the distro default
  # behavior) and not fail due to lack of memory that happens on low memory
  # servers + the salt client.
  #
  local mysql_dir_1="$source_dir/install/skel/common/etc/my.cnf.d"
  local mysql_dir_2="$source_dir/install/skel/$distro/$distro_ver_major/etc/my.cnf.d"
  local mysql_dir_3="$source_dir/install/skel/$distro/$distro_ver/etc/my.cnf.d"
  local mysql_dir

  for mysql_dir in "$mysql_dir_1" "$mysql_dir_2" "$mysql_dir_3"; do
    if [ -d "$mysql_dir" ]; then
      cp -R "$mysql_dir" /etc
    fi
  done
  # // workaround for mysql

  local pkg_list_file
  pkg_list_file="$source_dir/config/os.$distro/$distro_ver_major/distro-packages.txt"

  install_distro_pkgs "$distro" "$distro_ver_major" "$pkg_list_file"

  if [ "$distro_ver_major" == 6 ]; then
    # on CentOS 6 it comes with httpd disabled on boot by default
    chkconfig httpd on
  fi

  # Disable selinux
  setenforce 0
  sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux

  return 0
}

centos_post_software_install() {
  local source_dir="$1"
  local dest_dir="$1"

  if [ -n "$dp_server_hostname" ]; then
    echo "$dp_server_hostname" >/etc/hostname
    hostname "$dp_server_hostname"
  fi

  return 0
}

centos_adjust_system_config() {
  local install_dir="$1"

  [ -e "$_apache_includes_dir"/php.conf ] && mv -f "$_apache_includes_dir"/php.conf{,.disabled}

  echo '# disabled. With devPanel PHP must run as suexec, not as mod_php.' \
    >"$_apache_includes_dir/php.conf"

  if [ -f /etc/php.ini ]; then
    sed -i 's/^\(session.save_path.\+\)/;\1/' /etc/php.ini
  fi

  # By default /etc/my.cnf doesn't add the include dir, so we must do it
  if [ -f /etc/my.cnf -a -d /etc/my.cnf.d ]; then
    if ! fgrep -q -x '!includedir /etc/my.cnf.d' /etc/my.cnf; then
      echo '!includedir /etc/my.cnf.d' >> /etc/my.cnf
    fi
  fi

  # openssl req -subj "/C=--/ST=SomeState/L=SomeCity/O=SomeOrganization/OU=SomeOrganizationalUnit/CN=*.`hostname`" -new -x509 -days 3650 -nodes -out /opt/webenabled/config/os/pathnames/etc/ssl/certs/wildcard -keyout /opt/webenabled/config/os/pathnames/etc/ssl/keys/wildcard

  if [ -n "$platform_version" -a "$platform_version" == 2 ]; then
    if hash systemctl &>/dev/null; then
      systemctl enable devpanel-taskd
      # dbmgr can't be a systemd service yet because mysqld dies just after
    fi
  fi

  ln -s "$install_dir/compat/dbmgr/current/bin/dbmgr.init" /etc/init.d/devpanel-dbmgr
  chkconfig --add /etc/init.d/devpanel-dbmgr

  # start crontab (if it's not running for any reason)
  service cron restart

  return 0
}
