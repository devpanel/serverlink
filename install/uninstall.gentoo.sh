#!/bin/sh

distro=gentoo
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

  rm -rf /opt/webenabled
  userdel -f -r r_we
  rm /etc/apache2/macros.d/webenabled.conf
  userdel w_
  groupdel w_
  rm /home/clients/websites/w_
  #mv /etc/apache2/conf.d/php.conf.disabled /etc/httpd/conf.d/php.conf

  apache2ctl configtest
  apache2ctl graceful

  update-rc del  dbmgr default
  rm -f /etc/init.d/dbmgr

  trap - EXIT
  echo ALL DONE
