#!/bin/bash

redhat_set_variables() {
  return 0
}

redhat_pre_run() {
  return 0
}

redhat_install_distro_packages() {
  local source_dir="$1"
  local install_dir="$2"
  local distro_version="${3:-0}"

  echo Checking for crontab availability
  if ! hash crontab &>/dev/null; then
    yum -y install vixie-cron
  fi

  yum -y install curl

  # Install Epel and Remi repositories so that we have more up to date
  # packages, specially for PHP and MySQL, than the ones available on RHEL
  # 
  # EPEL: https://fedoraproject.org/wiki/EPEL
  # Remi: http://rpms.famillecollet.com/

  local epel_url=$(deref_os_prop "$install_dir" names/epel_pkg_url )
  if [ $? -ne 0 -o -z "$epel_url" ]; then
    echo "$FUNCNAME(): error, missing epel_pkg_url" 1>&2
    return 1
  fi

  local remi_url=$(deref_os_prop "$install_dir" names/remi_pkg_url )
  if [ $? -ne 0 -o -z "$remi_url" ]; then
    echo "$FUNCNAME(): error, missing remi_pkg_url" 1>&2
    return 1
  fi

  local tmp_pkg_file=$(mktemp)

  local installed_epel=""
  local installed_remi=""

  local i=0
  for i in 1 2 3; do
    echo "Installing EPEL repository, attempt $i..."
    curl -so "$tmp_pkg_file" -L --retry 3 --retry-delay 15 "$epel_url"
    if [ $? -eq 0 ]; then
      rpm -Uvh "$tmp_pkg_file"
      if [ $? -eq 0 ]; then
        installed_epel=1
        break
      else
        echo "Failed attempt $i of installing EPEL..." 1>&2
      fi
    fi
    sleep 15
  done

  rm -f "$tmp_pkg_file"
  if [ -z "$installed_epel" ]; then
    echo "$FUNCNAME(): error, unable to install EPEL repository" 1>&2
    return 1
  fi


  tmp_pkg_file=$(mktemp)

  i=0
  for i in 1 2 3; do
    echo "Installing Remi repository, attempt $i..."
    curl -so "$tmp_pkg_file" -L --retry 3 --retry-delay 15 "$remi_url"
    if [ $? -eq 0 ]; then
      rpm -Uvh "$tmp_pkg_file"
      if [ $? -eq 0 ]; then
        installed_remi=1
        break
      else
        echo "Failed attempt $i of installing Remi..." 1>&2
      fi
    fi
    sleep 15
  done

  rm -f "$tmp_pkg_file"
  if [ -z "$installed_remi" ]; then
    echo "$FUNCNAME(): error, unable to install Remi repository" 1>&2
    return 1
  fi

  {
    echo "remi.enabled=1";
    echo "remi-php55.enabled=1";
  } | "$install_dir/bin/update-ini-file" /etc/yum.repos.d/remi.repo

  # end of external repository installation

  # install some of the most critical packages
  for pkg in php make mysql mysql-server; do
    yum -y install "$pkg"
    if [ $? -ne 0 ]; then
      echo "$FUNCNAME(): failed to install package $pkg" 1>&2
      return 1
    fi
  done

  for module in dba gd ldap mysql pdo xml xmlrpc process soap; do
    yum -y install php-$module
  done

  # Install perl modules needed by devPanel software
  yum -y install perl perl-devel perl-Time-HiRes make php-pear git \
    perl-Digest-HMAC perl-Digest-SHA perl-CGI mod_ssl perl-Crypt-SSLeay \
    perl-CGI-Session

  return 0
}

redhat_post_software_install() {
  local source_dir="$1"
  local dest_dir="$1"

  # will issue a warning about a signature and a recommendation to look at config samples
  if [ `uname -m` = x86_64 ]
  then
    rpm -U "$source_dir/compat/RPMS/mod_macro-1.1.10-1.x86_64.rpm"
  else
    rpm -U "$source_dir/compat/RPMS/mod_macro-1.1.8-2.i386.rpm"
  fi

  if [ $? -ne 0 ]; then
    echo -e "\n\nWarning: failed to install mod_macro, Apache will not work\n\n"
    sleep 3
  fi

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

redhat_adjust_system_config() {
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

  ln -s "$install_dir/compat/dbmgr/current/bin/dbmgr.init" /etc/init.d/devpanel-dbmgr
  chkconfig --add /etc/init.d/devpanel-dbmgr
}
