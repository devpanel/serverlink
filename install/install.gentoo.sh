#!/bin/sh -e

distro="$1"
dir=`dirname "$0"`

install_package()
{
  emerge --newuse --update "$@"
}

error()
{
  echo ERROR${1+: }"$@" >&2
  trap - EXIT
  exit 1
}

trap 'error' EXIT

  #emerge --sync

  echo Checking for crontab availability
  if crontab -l >/dev/null 2>&1
  then
    echo Already there
  else
    if [ $? = 127 ]
    then
      echo Not found, installing vixie-cron
      install_package vixie-cron
    else 
      echo Already there
    fi
  fi 

  USE=suexec install_package apache
  install_package mysql
  if ! USE='xml cgi curl gd mhash mysql mysqli reflection spl suhosin truetype json' install_package php
  then
    USE='xml cgi curl gd mhash mysql mysqli reflection spl truetype json' install_package php
    # emerging suhosin requires already installed php
    USE='xml cgi curl gd mhash mysql mysqli reflection spl suhosin truetype json' install_package php
  fi
  for i in \
           pear mod_macro mod_fcgid
  do
    install_package $i
  done

  #ln -sf ../mods-available/rewrite.load /etc/apache2/mods-enabled/
  #ln -sf ../mods-available/macro.load /etc/apache2/mods-enabled/
  #ln -sf ../mods-available/suexec.load /etc/apache2/mods-enabled/

  groupadd virtwww || true
  groupadd weadmin || true

  if ! [ -d "$dir/files" ]
  then
    echo Unpacking files
    tar xpf "$dir/files.tar" || error
  fi

  mkdir /opt/webenabled || error "Cannot mkdir /opt/webenabled: already installed?"
  chmod go+rx /opt/webenabled
  cp -a "$dir/files/opt/webenabled"/* /opt/webenabled

  ln -snf os.$distro /opt/webenabled/config/os

  useradd -s /opt/webenabled/current/libexec/server  -u0 -g0 -mo r_we || error

  mkdir ~r_we/.ssh || true
  cat /opt/webenabled/config/ssh/global.pub >>~r_we/.ssh/authorized_keys

  if [ -r /etc/apache2/macros.d/webenabled.conf ]
  then 
     error "/etc/apache2/macros.d/webenabled.conf exists. Webenabled already installed?"; 
  fi
  ln -snf /var/log/apache2 /etc/apache2/logs
  echo 'NameVirtualHost *:80' >> /etc/apache2/macros.d/webenabled.conf
  echo 'Include /opt/webenabled/compat/apache_include/*.conf' >> /etc/apache2/macros.d/webenabled.conf
  #mkdir /etc/apache2/webenabled.d || error "Cannot mkdir /etc/apache2/webenabled.d: already installed?"
  #echo 'Include webenabled.d/*.conf' >> /etc/apache2/conf.d/webenabled.conf

  mkdir -p /var/log/apache2/virtwww
  mkdir -p /home/clients/websites /home/clients/databases
  chmod go+rx /var/log/apache2/virtwww /home/clients /home/clients/websites /home/clients/databases
  chmod o+x /var/log/apache2

  groupadd w_
  useradd -M -d /home/clients/websites/w_ -G w_ -g virtwww w_ 
    # without the -M option, Fedora will create HOME

  ln -snf /opt/webenabled/compat/w_ /home/clients/websites/w_
  chown -R w_: /opt/webenabled/compat/w_
  chgrp `cat /opt/webenabled/config/os/names/apache.group` /opt/webenabled/compat/w_ 
  chgrp `cat /opt/webenabled/config/os/names/apache.group` /opt/webenabled/compat/w_/public_html
  chgrp `cat /opt/webenabled/config/os/names/apache.group` /opt/webenabled/compat/w_/public_html/cgi

  mv /usr/sbin/suexec /usr/sbin/suexec.orig || true
  ln -s /opt/webenabled/config/os/pathnames/sbin/suexec /usr/sbin/suexec
  chgrp `cat /opt/webenabled/config/os/names/apache.group` /opt/webenabled/compat/suexec
  chgrp `cat /opt/webenabled/config/os/names/apache.group` /opt/webenabled/config/os/pathnames/sbin/suexec
  chmod 4710 /opt/webenabled/config/os/pathnames/sbin/suexec
  dd bs=65536 count=1 if=/dev/zero of=/opt/webenabled/compat/suexec/config/suexec.map
  chmod 600 /opt/webenabled/compat/suexec/config/suexec.map

  rm -f /etc/apache2/mods-enabled/php5.load

  #APACHE2_OPTS="-D DEFAULT_VHOST -D INFO -D SSL -D SSL_DEFAULT_VHOST -D LANGUAGE"
  for i in MACRO SUEXEC
  do
    if ! grep -q "^APACHE2_OPTS=\".*-D $i\\>" /etc/conf.d/apache2
    then
      sed -i "s/^APACHE2_OPTS=\"\\(.*\\)\"/APACHE2_OPTS=\"\\1 -D $i\"/" /etc/conf.d/apache2
    fi
  done

  apache2ctl configtest
  apache2ctl stop || true
  apache2ctl start

  #ln -snf `cat /opt/webenabled/config/os.centos/names/skel.sql.version` /opt/webenabled/compat/skel.sql/mysql/any
    # check mysql version and probably update /opt/webenabled/config/os.centos/names/skel.sql.version
    # before running this command

  ln -s /opt/webenabled/compat/dbmgr/current/bin/dbmgr.init /etc/init.d/dbmgr
  update-rc add  dbmgr default

  su -lc 'sed -i "s/^REDIRECT_STATUS=200/export &/" public_html/cgi/phpmyadmin.php' w_
  su -lc 'sed -i "s/^REDIRECT_STATUS=200/export &/" public_html/cgi/extplorer.php' w_
  #su -lc 'sed -i "s^/opt/dbmgr/config/^/opt/webenabled/compat/dbmgr/config/^" public_html/phpmyadmin/config/asp.config.inc' w_

  trap - EXIT
  echo ALL DONE
