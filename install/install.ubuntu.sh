ubuntu_set_variables() {
  return 0
}

ubuntu_pre_run() {
  local source_dir="$1"
  local target_dir="$2"
  local distro="$3"
  local distro_ver="$4"
  local distro_ver_major="$5"
  local distro_ver_minor="$6"

  export DEBIAN_FRONTEND='noninteractive'

  apt-get update

  if ! apt-get -y install apt-transport-https; then
    echo "$FUNCNAME(): apt-get install apt-transport-https FAILED" 1>&2
    return 1
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

  if [ -n "$lamp__distro_repos__enabled" ]; then
    add_apt_repositories "$source_dir" "$distro" "$distro_ver" \
      "$distro_ver_major" "$distro_ver_minor" || return $?
  fi

  # NOTE: at this point the $install_dir has not been copied in place yet

  ###############################################
  # workaround for mysql on low memory servers  #
  ###############################################
  # copy /etc/mysql/ in place with the lower memory defaults, so that the
  # mysqld is able to start just after install (that is the distro default
  # behavior) and not fail due to lack of memory that happens on low memory
  # servers + the salt client.
  #
  local mysql_dir_1="$source_dir/install/skel/common/etc/mysql"
  local mysql_dir_2="$source_dir/install/skel/$distro/$distro_ver_major/etc/mysql"
  local mysql_dir_3="$source_dir/install/skel/$distro/$distro_ver/etc/mysql"
  local mysql_dir

  for mysql_dir in "$mysql_dir_1" "$mysql_dir_2" "$mysql_dir_3"; do
    if [ -d "$mysql_dir" ]; then
      cp -R "$mysql_dir" /etc
    fi
  done
  # // workaround for mysql

  local pkg_list_file="$lamp__paths__distro_defaults_dir/distro-packages.txt"

  install_distro_pkgs "$distro" "$distro_ver_major" "$pkg_list_file"

  export DEBIAN_FRONTEND='noninteractive'

  # a2dismod php$php_ver

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

  if [ -d /etc/apparmor.d/ ]; then
    service apparmor reload
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

  # stop the standard mysql service of Ubuntu
  # the stop on boot is done by the skel directory
  service mysql stop || true

  if [ -n "$platform_version" -a "$platform_version" == 2 ]; then
    if hash systemctl &>/dev/null; then
      systemctl enable devpanel-taskd

      # the idea of disabling mysql was not to confuse users with an extra
      # mysql. But the problem is that on some versions apt-get gets broken
      # because mysql doesn't run the dpkg-configure correctly when mysql is
      # disabled on systemd.
      #
      # systemctl disable mysql
    else
      local taskd_init=/etc/init.d/devpanel-taskd
      if [ -L "$taskd_init" -o -e "$taskd_init" ]; then
        update-rc.d devpanel-taskd defaults
      fi
    fi
  fi

  if hash systemctl &>/dev/null; then
    systemctl enable devpanel-bootstrap
    systemctl start  devpanel-bootstrap
  elif hash initctl &>/dev/null; then
    initctl start devpanel-bootstrap
  fi

  # start crontab (if it's not running for any reason)
  service cron restart

  return 0
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
