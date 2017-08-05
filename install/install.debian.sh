debian_set_variables() {
  return 0
}

debian_pre_run() {
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
}

debian_install_distro_packages() {
  local source_dir="$1"
  local target_dir="$2"
  local distro="$3"
  local distro_ver="$4"
  local distro_ver_major="$5"
  local distro_ver_minor="$6"

  local tmp_self_file="${BASH_SOURCE[0]}"
  local tmp_self_dir=${tmp_self_file%/*}
  local tmp_aux_lib="$tmp_self_dir/lib.debian_ubuntu.sh"

  if ! . "$tmp_aux_lib"; then
    echo "$FUNCNAME(): error - unable to load file $tmp_aux_lib" 1>&2
    return 1
  fi

  add_apt_repositories "$source_dir" "$distro" "$distro_ver" \
    "$distro_ver_major" "$distro_ver_minor" || return $?

  local pkg_list_file
  pkg_list_file="$source_dir/config/os.$distro/$distro_ver_major/distro-packages.txt"

  install_distro_pkgs "$distro" "$distro_ver_major" "$pkg_list_file"
}

debian_adjust_system_config() {
  local install_dir="$1"

  if [ -r /etc/apparmor.d/usr.sbin.mysqld ]; then
    # add allow rules on apparmor.d for mysqld to access files on devPanel's
    # db home directories
    printf "%s/** rwk,\n" "$databasedir_base" \
      >>/etc/apparmor.d/local/usr.sbin.mysqld

    service apparmor reload
  fi

  local module=""
  local -a apache2_modules=( \
    cgi expires headers macro rewrite suexec ssl proxy proxy_http \
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

  # stop mysql from the distro
  service mysql stop

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

  # dbmgr.init is not yet compatible with systemd (mysqld dies even when
  # service type is oneshot)
  # so do a sysvinit setup style
  [ -e /etc/init.d/dbmgr ] && rm -f /etc/init.d/dbmgr
  ln -s "$install_dir"/compat/dbmgr/current/bin/dbmgr.init /etc/init.d/devpanel-dbmgr
  update-rc.d devpanel-dbmgr defaults

  if ! fuser -s 25/tcp; then
    apt-get -y install postfix
  fi

  return 0
}

debian_post_users_n_groups() {
  return 0
}

debian_post_software_install() {
  if [ -n "$dp_server_hostname" ]; then
    echo "$dp_server_hostname" >/etc/hostname
    hostname "$dp_server_hostname"
  fi

  a2dismod php5

  return 0
}
