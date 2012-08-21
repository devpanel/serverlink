ubuntu_set_variables() {
  _suexec_bin="/usr/lib/apache2/suexec"
  _apache_base_dir="/etc/apache2"
  _apache_log_dir="/var/log/apache2"
}

ubuntu_pre_run() {
  return 0
}

ubuntu_install_distro_packages() {
  local install_dir="$1"

  export DEBIAN_FRONTEND='noninteractive'

  apt-get update

  echo -n Checking for update-rc.d availability: 
  if update-rc.d  >/dev/null 2>&1
  then
    echo Already there
  else
    if [ $? = 127 ]
    then
      echo Not found, installing sysvinit
      apt-get -y install sysvinit
    else
      echo Already there
    fi
  fi

  if [ `uname -m` = x86_64 ]
  then
    # for suexec, chcgi, gena10, pwqgen
    apt-get -y install libc6-dev-i386
  fi

  for i in \
           apache2 mysql-server php5 php5-cli php-pear php5-gd \
           php5-curl php5-mysql libapache2-mod-macro php5-cgi php5-mcrypt \
           apache2-suexec zlib1g #git subversion #libapache2-mod-fcgid
  do
    apt-get -y install $i
  done
}

ubuntu_adjust_system_config() {
  local install_dir="$1"

  if [ -r /etc/apparmor.d/usr.sbin.mysqld ]
  then
    sed -i 's/^/#/' /etc/apparmor.d/usr.sbin.mysqld
    if [ -r /etc/init.d/apparmor ]
    then
      /etc/init.d/apparmor reload
    fi
  fi

  for module in rewrite macro suexec ssl proxy proxy_http; do
    [ -f "$_apache_base_dir/mods-available/$module.load" ] && \
      ln -sf ../mods-available/$module.load "$_apache_base_dir"/mods-enabled/
  done

  ln -snf "$_apache_log_dir" "$_apache_base_dir"/logs
  # fuser fails on slicehost CentOS  (/proc/net/tcp is empty)
  #if fuser 443/tcp >/dev/null || netstat -ln --tcp|grep -q :443
  #then
  #  :
  #else
  #  echo 'Listen 443' >> "$_apache_base_dir"/conf.d/webenabled.conf
  #fi

  echo 'NameVirtualHost *:80' >> "$_apache_base_dir"/conf.d/webenabled.conf
  echo 'NameVirtualHost *:443' >> "$_apache_base_dir"/conf.d/webenabled.conf
  echo 'Include '"$install_dir"'/compat/apache_include/*.conf' >> "$_apache_base_dir"/conf.d/webenabled.conf
  #mkdir "$_apache_base_dir"/webenabled.d || error "Cannot mkdir "$_apache_base_dir"/webenabled.d: already installed?"
  #echo 'Include webenabled.d/*.conf' >> "$_apache_base_dir"/conf.d/webenabled.conf

  mkdir -p "$_apache_log_dir"/virtwww
  chmod go+rx "$_apache_log_dir"/virtwww
  chmod o+x "$_apache_log_dir"

  rm -f "$_apache_base_dir"/mods-enabled/php5.load

  apache2ctl configtest
  apache2ctl graceful

  ln -s "$install_dir"/compat/dbmgr/current/bin/dbmgr.init /etc/init.d/dbmgr
  update-rc.d dbmgr defaults
}

ubuntu_post_users_n_groups() {
  return 0
}

ubuntu_post_software_install() {
  return 0
}
