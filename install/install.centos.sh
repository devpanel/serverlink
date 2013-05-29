#!/bin/bash

centos_set_variables() {
  return 0
}

centos_pre_run() {
  return 0
}

centos_install_distro_packages() {
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

  yum -y install mysql mysql-server
  # tested with 5.1.44-1.fc12 (Fedora), 5.0.77-4.el5_4.2 (CentOS)

  if [ "${distro_version:0:1}" == "5" ]; then
    phpver=53
  fi

  yum -y install php$phpver
    # tested with:
    #   5.3.1-1.fc12 (Fedora)
    #   5.1.6-24.el5_4.5 (CentOS); phpmyadmin will not work!
    #   5.2.10-1.el5.centos (CentOS) from CentOS-Testing.repo; required for phpmyadmin


  for module in dba gd ldap mysql mcrypt pdo xml xmlrpc process soap; do
    yum -y install php$phpver-$module
  done

  yum -y install php-pear git cgit perl-Digest-HMAC perl-Digest-SHA1 \
    perl-CGI subversion mod_dav_svn mod_ssl

  # will issue a warning about a signature and a recommendation to look at config samples
  if [ `uname -m` = x86_64 ]
  then
    rpm -U files/opt/webenabled/compat/RPMS/mod_macro-1.1.10-1.x86_64.rpm
  else
    rpm -U files/opt/webenabled/compat/RPMS/mod_macro-1.1.8-2.i386.rpm
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
  [ -e "$_apache_includes_dir"/conf.d/php.conf ] && mv -f "$_apache_includes_dir"/conf.d/php.conf{,.disabled}

  sed -i 's/^\(session.save_path.\+\)/;\1/' /etc/php.ini
    # By default, PHP tries to create sessions in a directory owned by the user apache,
    # which doesn't work with suexec

  # mv -f "$_apache_base_dir"/conf.d/welcome.conf{,.disabled}

  # openssl req -subj "/C=--/ST=SomeState/L=SomeCity/O=SomeOrganization/OU=SomeOrganizationalUnit/CN=*.`hostname`" -new -x509 -days 3650 -nodes -out /opt/webenabled/config/os/pathnames/etc/ssl/certs/wildcard -keyout /opt/webenabled/config/os/pathnames/etc/ssl/keys/wildcard

  # if [ -f /etc/pki/tls/certs/localhost.crt ]
  # then
  #   mv /etc/pki/tls/certs/localhost.crt /etc/pki/tls/certs/localhost.crt.orig
  #   ln -s /opt/webenabled/config/os/pathnames/etc/ssl/certs/wildcard /etc/pki/tls/certs/localhost.crt
  # fi 
  # if [ -f /etc/pki/tls/private/localhost.key ]
  # then
  #   mv /etc/pki/tls/private/localhost.key /etc/pki/tls/private/localhost.key.orig
  #   ln -s /opt/webenabled/config/os/pathnames/etc/ssl/keys/wildcard /etc/pki/tls/private/localhost.key
  # fi 

  # apachectl configtest
    # Issues a warning: [warn] NameVirtualHost *:80 has no VirtualHosts
    # The warning will disappear when at least one vhost is created
  # apachectl graceful

  # ln -snf `cat "$install_dir"/config/os.centos/names/skel.sql.version` "$install_dir"/compat/skel.sql/mysql/any
    # check mysql version and probably update /opt/webenabled/config/os.centos/names/skel.sql.version
    # before running this command

  echo "$install_dir"/compat/dbmgr/current/bin/dbmgr.init start >>/etc/rc.d/rc.local
  # echo "$install_dir"/compat/shellinabox/shellinabox.init start >>/etc/rc.d/rc.local
#   /opt/webenabled/compat/shellinabox/shellinabox.init start


#  su -lc 'sed -i "s/^REDIRECT_STATUS=200/export &/" public_html/cgi/phpmyadmin.php' w_
  #su -lc 'sed -i "s^/opt/dbmgr/config/^/opt/webenabled/compat/dbmgr/config/^" public_html/phpmyadmin/config/asp.config.inc' w_

#  ./install-svn.centos.sh
#  ./install-git.centos.sh

  # SliceHost hack
  # if [ -r /etc/sysconfig/system-config-securitylevel ]
  # then
  #   /sbin/iptables -P INPUT ACCEPT
  #   /sbin/iptables -P FORWARD ACCEPT
  #   /sbin/iptables -P OUTPUT ACCEPT
  #   /sbin/iptables -F
  # fi
  # cloud9 hack
  # /sbin/iptables -A OUTPUT -d 127.0.0.2 -p tcp -m tcp --dport 4000:6000 -m owner '!' --uid-owner apache -j REJECT --reject-with icmp-port-unreachable
  # /etc/init.d/iptables save
}
