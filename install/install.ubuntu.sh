ubuntu_set_variables() {
  return 0
}

ubuntu_pre_run() {
  local has_ssh=""

  for i in {1..3}; do
    fuser ssh/tcp &>/dev/null
    if [ $? -eq 0 ]; then
      has_ssh=1
      break
    fi
  done

  if [ -z "$has_ssh" ]; then
    if hash sshd &>/dev/null; then
      if ! service ssh start; then
        echo "Error: unable to start sshd service. It's required by devPanel" 1>&2
        exit 1
      fi
    else
      apt-get update

      apt-get install openssh-server
      if [ $? -ne 0 ]; then
        echo "Error: unable to install OpenSSH. It's required by many"\
        "functionalities of devPanel" 1>&2
        return 1
      fi
    fi
  fi

  return 0
}

ubuntu_install_distro_packages() {
  local source_dir="$1"
  local install_dir="$2"
  local ubuntu_version="${3:-0}"

  export DEBIAN_FRONTEND='noninteractive'

  apt-get update

  echo -n Checking for update-rc.d availability: 
  if hash update-rc.d ; then
    echo Already there
  else
      echo Not found, installing sysvinit
      apt-get -y install sysvinit
  fi

  local -a install_pkgs=( curl apache2 libapache2-mod-macro apache2-suexec \
                          zlib1g libapache2-mod-fcgid mysql-server git
                          apache2-utils php5 php5-cli php-pear php5-gd
                          php5-curl php5-mysql php5-cgi php5-mcrypt
                          php5-sqlite libjson-xs-perl libcrypt-ssleay-perl
                          libcgi-session-perl \
                          nano vim s3cmd unzip
                        )
                          

  for i in ${install_pkgs[@]}; do
    apt-get -y install $i
  done

  # test whether CGI::Util is available, it's needed by taskd
  # from Ubuntu 16 it's not included in the perl distribution
  perl -MCGI::Util -e 'exit 0;' &>/dev/null
  if [ $? -eq 0 ]; then
    :
  else
    apt-get -y install libcgi-pm-perl
  fi

  # this is Ubuntu specific, that right now doesn't ship with a default MTA
  # if there isn't anything listening on port 25/tcp then we install Postfix
  # for the sites to be able to send e-mail
  if ! fuser -s 25/tcp; then
    apt-get -y install postfix
  fi
}

ubuntu_adjust_system_config() {
  local install_dir="$1"

  if [ -r /etc/apparmor.d/usr.sbin.mysqld ]
  then
    sed -i 's/^[:space:]*[^#]/#/' /etc/apparmor.d/usr.sbin.mysqld
    if [ -r /etc/init.d/apparmor ]
    then
      /etc/init.d/apparmor reload
    fi
  fi

  for module in rewrite macro cgi suexec ssl proxy proxy_http; do
    if [ ! -e "$_apache_base_dir/mods-enabled/$module.load" \
      -a -f "$_apache_base_dir/mods-available/$module.load" ]; then
      ln -sf ../mods-available/$module.load "$_apache_base_dir"/mods-enabled/
    fi
  done

  # fuser fails on slicehost CentOS  (/proc/net/tcp is empty)
  #if fuser 443/tcp >/dev/null || netstat -ln --tcp|grep -q :443
  #then
  #  :
  #else
  #  echo 'Listen 443' >> "$_apache_base_dir"/conf.d/webenabled.conf
  #fi

  [ -e "$_apache_base_dir"/mods-enabled/php5.load ] && rm -f "$_apache_base_dir"/mods-enabled/php5.load
  [ -e "$_apache_base_dir"/mods-enabled/php5.conf ] && rm -f "$_apache_base_dir"/mods-enabled/php5.conf

  # enable php mcrypt module that is generally disabled
  if hash php5enmod &>/dev/null; then
    php5enmod mcrypt
  fi

  [ -e /etc/init.d/dbmgr ] && rm -f /etc/init.d/dbmgr
  ln -s "$install_dir"/compat/dbmgr/current/bin/dbmgr.init /etc/init.d/devpanel-dbmgr
  update-rc.d devpanel-dbmgr defaults
}

ubuntu_post_users_n_groups() {
  return 0
}

ubuntu_post_software_install() {
  if [ -n "$dp_server_hostname" ]; then
    echo "$dp_server_hostname" >/etc/hostname
    hostname "$dp_server_hostname"
  fi

  return 0
}
