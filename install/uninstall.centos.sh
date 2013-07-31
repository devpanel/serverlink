#!/bin/sh

distro=centos
dir=`dirname "$0"`

install_package()
{
  yum -y "$@"
}

error()
{
  echo ERROR${1+: }"$@" >&2
  trap - EXIT
  exit 1
}

trap 'error' EXIT
  ./uninstall-svn.$distro.sh
  ./uninstall-git.$distro.sh

  /opt/webenabled/compat/shellinabox/shellinabox.init stop
  sed -i 's!/opt/webenabled/compat/shellinabox/shellinabox.init start!#&!' /etc/rc.d/rc.local

  rm -rf /opt/webenabled
  userdel -r r_we
  rpm -e mod_macro
    # will issue a warning about a signature 
    # and a recommendation to look at config samples

  rm /etc/httpd/conf.d/webenabled.conf
  rm -rf /etc/httpd/webenabled.d
  userdel w_
  groupdel w_
  rm /home/clients/websites/w_
  mv /etc/httpd/conf.d/php.conf.disabled /etc/httpd/conf.d/php.conf

  #sed -i 's/^session.save_path/;/' /etc/php.ini
    # By default, PHP tries to create sessions in a directory owned by the user apache,
    # which doesn't work with suexec

  if [ -h /etc/pki/tls/certs/localhost.crt ] && [ -f /etc/pki/tls/certs/localhost.crt.orig ]
  then
    rm /etc/pki/tls/certs/localhost.crt
    mv /etc/pki/tls/certs/localhost.crt.orig /etc/pki/tls/certs/localhost.crt
  fi 
  if [ -h /etc/pki/tls/private/localhost.key ] && [ -f /etc/pki/tls/private/localhost.key.orig ]
  then
    rm /etc/pki/tls/private/localhost.key
    mv /etc/pki/tls/private/localhost.key.orig /etc/pki/tls/private/localhost.key
  fi 

  apachectl configtest
    # Issues a warning: [warn] NameVirtualHost *:80 has no VirtualHosts
    # The warning will disappear when at least one vhost is created
  apachectl graceful

  sed -i 's!/opt/webenabled/compat/dbmgr/current/bin/dbmgr.init start!#&!' /etc/rc.d/rc.local


  trap - EXIT
  echo ALL DONE
