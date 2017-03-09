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
 
  echo Checking for crontab availability
  if ! hash crontab &>/dev/null; then
    yum -y install vixie-cron
  fi 

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

  # enable PHP 5.6 from the Remi by default
  local remi_file="/etc/yum.repos.d/remi.repo"
  if [ -f "$remi_file" ]; then
    { 
      echo "remi.enabled=1"; 
      echo "remi-php56.enabled=1"; 
    } | "$source_dir/bin/update-ini-file" "$remi_file"
  fi

  # end of external repository installation

  local -a install_pkgs=( bc curl httpd mod_fcgid php make mysql-server mysql \
                          nano vim s3cmd unzip \
                        )

  # install some of the most critical packages
  for pkg in ${install_pkgs[@]}; do
    yum -y install "$pkg"
    if [ $? -ne 0 ]; then
      echo "$FUNCNAME(): failed to install package $pkg" 1>&2
      return 1
    fi
  done

  local -a php_mods=( 
                      php-dba php-gd php-ldap php-mysqlnd php-pdo \
                      php-xml php-xmlrpc php-process php-soap     \
                      php-mbstring
  )

  yum -y install ${php_mods[*]}

  # Install perl modules needed by devPanel software
  yum -y install perl perl-devel perl-core perl-Time-HiRes make php-pear git \
    perl-Digest-HMAC perl-Digest-SHA perl-CGI mod_ssl perl-Crypt-SSLeay \
    perl-CGI-Session perl-IO-Socket-SSL perl-URI

  return 0
}

centos_post_software_install() {
  local source_dir="$1"
  local dest_dir="$1"

  # included JSON::PP on the default install (no need anymore for the lines
  # below)
  # 
  # install JSON::PP (we'd prefer JSON::XS, but not to install gcc, etc
  # we can go with JSON::PP that is fully compatible with JSON::XS
  # "$install_dir/bin/cpanm" JSON::PP
  # if [ $? -ne 0 ]; then
  #  echo -e "\n\nWarning: failed to install JSON::PP\n\n"
  #  sleep 3
  # fi

  if [ -n "$dp_server_hostname" ]; then
    echo "$dp_server_hostname" >/etc/hostname
    hostname "$dp_server_hostname"
  fi

  return 0
}

centos_adjust_system_config() {
  local install_dir="$1"
  # fuser fails on slicehost CentOS  (/proc/net/tcp is empty)
  #if fuser 443/tcp >/dev/null || netstat -ln --tcp|grep -q :443
  #then
  #  :
  #else
  #  echo 'Listen 443' >> /etc/httpd/conf.d/webenabled.conf
  #fi
  [ -e "$_apache_includes_dir"/php.conf ] && mv -f "$_apache_includes_dir"/php.conf{,.disabled}

  sed -i 's/^\(session.save_path.\+\)/;\1/' /etc/php.ini
  sed -i 's/^[[:space:]]*\(short_open_tag\).\+/\1 = On/' /etc/php.ini

  # openssl req -subj "/C=--/ST=SomeState/L=SomeCity/O=SomeOrganization/OU=SomeOrganizationalUnit/CN=*.`hostname`" -new -x509 -days 3650 -nodes -out /opt/webenabled/config/os/pathnames/etc/ssl/certs/wildcard -keyout /opt/webenabled/config/os/pathnames/etc/ssl/keys/wildcard

  if hash systemctl &>/dev/null; then
    systemctl enable devpanel-taskd
    # dbmgr can't be a systemd service yet because mysqld dies just after
  fi

  ln -s "$install_dir/compat/dbmgr/current/bin/dbmgr.init" /etc/init.d/devpanel-dbmgr
  chkconfig --add /etc/init.d/devpanel-dbmgr
}
