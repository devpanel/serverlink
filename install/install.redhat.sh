#!/bin/bash

redhat_set_variables() {
  return 0
}

redhat_pre_run() {
  return 0
}

redhat_install_distro_packages() {
  local install_dir="$1"
  local distro_version="${2:-0}"

  local phpver=""
  #centos-5: getting php 5.2 or later
  #
  #  Source:
  #    http://centos.org/modules/newbb/viewtopic.php?topic_id=16648&forum=38
  #
  #      Updated info on this. php 5.2 is now available from the testing
  #      repository for CentOS-5. Please see
  #         http://wiki.centos.org/AdditionalResources/Repositories 
  #      for details on how to use this repository
  #
  #
  #  Enabling the testing repo
  #
  #      /etc/install_package.repos.d/CentOS-Testing.repo
  #        - download it from http://dev.centos.org/centos/5/CentOS-Testing.repo
  #        - change 'enabled' to 1
  #wget -O /etc/yum.repos.d/CentOS-Testing.repo http://dev.centos.org/centos/5/CentOS-Testing.repo
  #sed -i 's/^enabled=0$/enabled=1/' /etc/yum.repos.d/CentOS-Testing.repo
  #if ! rpm -ql epel-release-5-4.noarch >/dev/null 2>&1
  #then
  #  rpm -Uvh 'http://download.fedora.redhat.com/pub/epel/5/i386/epel-release-5-4.noarch.rpm'
  #fi
  #
  #
  #
  #fedora 12/centos-5.4

  echo Checking for crontab availability
  if crontab -l >/dev/null 2>&1
  then
    echo Already there
  else
    if [ $? = 127 ]
    then
      echo Not found, installing vixie-cron
      yum -y install vixie-cron
    else 
      echo Already there
    fi
  fi 

  yum -y install curl make mysql mysql-server

  if [ "${distro_version:0:1}" == "5" ]; then
    phpver=53
  fi

  yum -y install php$phpver
    # tested with:
    #   5.3.1-1.fc12 (Fedora)
    #   5.1.6-24.el5_4.5 (CentOS); phpmyadmin will not work!
    #   5.2.10-1.el5.centos (CentOS) from CentOS-Testing.repo; required for phpmyadmin


  for module in dba gd ldap mysql pdo xml xmlrpc process soap; do
    yum -y install php$phpver-$module
  done

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
