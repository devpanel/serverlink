#!/bin/sh

distro=ubuntu
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

  /etc/init.d/shellinabox stop || true
  update-rc.d -f shellinabox remove
  rm -f /etc/init.d/shellinabox

  rm -rf /opt/webenabled
  userdel -f -r r_we
  rm /etc/apache2/conf.d/webenabled.conf
  userdel w_
  groupdel w_
  rm /home/clients/websites/w_
  #mv /etc/apache2/conf.d/php.conf.disabled /etc/httpd/conf.d/php.conf
  rm -f /etc/apache2/mods-enabled/macro.load

  apache2ctl configtest
  apache2ctl graceful

  update-rc.d -f dbmgr remove
  rm -f /etc/init.d/dbmgr

  update-rc.d -f cloud9 remove
  rm -f /etc/init.d/cloud9

  # cloud9 hack
  /sbin/iptables -D OUTPUT -d 127.0.0.2 -p tcp -m tcp --dport 4000:6000 -m owner '!' --uid-owner www-data -j REJECT --reject-with icmp-port-unreachable
  /sbin/iptables-save


  trap - EXIT
  echo ALL DONE
