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
  local distro="$3"
  local distro_ver="$4"
  local distro_ver_major="$5"
  local distro_ver_minor="$6"

  # NOTE: at this point the $install_dir has not been copied in place yet

  local tmp_self_file="${BASH_SOURCE[0]}"
  local tmp_self_dir=${tmp_self_file%/*}
  local tmp_aux_lib="$tmp_self_dir/lib.debian_ubuntu.sh"

  if ! . "$tmp_aux_lib"; then
    echo "$FUNCNAME(): error - unable to load file $tmp_aux_lib" 1>&2
    return 1
  fi

  add_apt_repositories "$source_dir" "$distro" "$distro_ver" \
    "$distro_ver_major" "$distro_ver_minor" || return $?

  # NOTE: at this point the $install_dir has not been copied in place yet

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
                        zlib1g libapache2-mod-fcgid mysql-server git       \
                        apache2-utils libjson-xs-perl libcrypt-ssleay-perl \
                        libcgi-session-perl nano vim s3cmd unzip bc
                        libio-socket-ssl-perl
                        )
                          

  for i in ${install_pkgs[@]}; do
    apt-get -y install $i
  done

  local php_ver php_mod
  php_ver=$(deref_os_prop "$source_dir" names/php_version_from_distro)

  apt-get -y install php$php_ver php-pear

  for php_mod in cgi cli curl gd mbstring mcrypt mysql sqlite zip; do
    apt-get -y install php$php_ver-$php_mod
  done

  a2dismod php$php_ver

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

  local module
  local -a apache2_modules=( \
    cgi expires headers macro rewrite proxy proxy_http ssl suexec \
  )

  for module in ${apache2_modules[@]}; do
    a2enmod $module
  done

  # remove distro default cgi-bin aliases, will not be used
  a2disconf serve-cgi-bin

  # fuser fails on slicehost CentOS  (/proc/net/tcp is empty)
  #if fuser 443/tcp >/dev/null || netstat -ln --tcp|grep -q :443
  #then
  #  :
  #else
  #  echo 'Listen 443' >> "$_apache_base_dir"/conf.d/webenabled.conf
  #fi

  # enable php mcrypt module that is generally disabled
  if hash php5enmod &>/dev/null; then
    php5enmod mcrypt
  fi

  [ -e /etc/init.d/dbmgr ] && rm -f /etc/init.d/dbmgr
  ln -s "$install_dir"/compat/dbmgr/current/bin/dbmgr.init /etc/init.d/devpanel-dbmgr
  update-rc.d devpanel-dbmgr defaults

  # stop the standard mysql service of Ubuntu
  # the stop on boot is done by the skel directory
  service mysql stop || true

  if hash systemctl &>/dev/null; then
    systemctl enable devpanel-taskd
    systemctl disable mysql
  else
    local taskd_init=/etc/init.d/devpanel-taskd
    if [ -L "$taskd_init" -o -e "$taskd_init" ]; then
      update-rc.d devpanel-taskd defaults
    fi
  fi
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
