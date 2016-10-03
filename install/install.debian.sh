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

  return 0
}

debian_install_distro_packages() {
  local source_dir="$1"
  local target_dir="$2"
  local distro="$3"
  local distro_ver="$4"
  local distro_ver_major="$5"
  local distro_ver_minor="$6"

  # install external repositories needed
  local repos_link repos_file repos_name key_link t_dir
  local repos_dir_1 repos_dir_2 repos_dir_3
  local pref_file pref_name

  local distro_config_dir="$source_dir/config/os.$distro"
  local repos_dir_tmpl="$distro_config_dir/@version@/repositories"

  local distro_ver_major_minor="$distro_ver_major.$distro_ver_minor"

  repos_dir_1="${repos_dir_tmpl//@version@/$distro_ver}"
  repos_dir_2="${repos_dir_tmpl//@version@/$distro_ver_major_minor}"
  repos_dir_3="${repos_dir_tmpl//@version@/$distro_ver_major}"

  for repos_link in "$repos_dir_1/repos."[0-9]*.* \
                    "$repos_dir_2/repos."[0-9]*.* \
                    "$repos_dir_3/repos."[0-9]*.*; do

    if [ ! -L "$repos_link" ]; then
      continue
    fi

    repos_name="${repos_link##*.}"
    t_dir="${repos_link%/*}"
    repos_file=$(readlink -e "$repos_link")
    if [ $? -ne 0 ]; then
      echo "$FUNCNAME(): warning, link $repos_link doesn't resolve" 1>&2
      sleep 2
      continue
    fi

    cp -f "$repos_file" /etc/apt/sources.list.d

    key_link="$t_dir/$repos_name.key"
    if [ -L "$key_link" -a -f "$key_link" ]; then
      apt-key add "$key_link"
    fi
  done

  for pref_file in "$repos_dir_1"/preferences.*  \
                    "$repos_dir_2"/preferences.* \
                    "$repos_dir_3"/preferences.* ; do

    if [ ! -f "$pref_file" ]; then
      continue
    fi

    pref_name="${pref_file##*.}"
    cp -f "$pref_file" "/etc/apt/preferences.d/$pref_name"
  done


  export DEBIAN_FRONTEND='noninteractive'

  apt-get update

  echo -n Checking for update-rc.d availability: 
  if hash update-rc.d ; then
    echo Already there
  else
      echo Not found, installing sysvinit
      apt-get -y install sysvinit
  fi

  for i in \
    cron dialog bsdutils curl apache2 libapache2-mod-macro apache2-suexec zlib1g libapache2-mod-fcgid \
    mysql-server git subversion \
    php5 php5-cli php-pear php5-gd php5-curl php5-mysql \
    php5-cgi php5-mcrypt php5-sqlite libjson-xs-perl libcrypt-ssleay-perl \
    libcgi-session-perl unzip
  do
    apt-get -y install $i
  done
}

debian_adjust_system_config() {
  local install_dir="$1"

  if [ -r /etc/apparmor.d/usr.sbin.mysqld ]
  then
    sed -i 's/^[:space:]*[^#]/#/' /etc/apparmor.d/usr.sbin.mysqld
    if [ -r /etc/init.d/apparmor ]
    then
      /etc/init.d/apparmor reload
    fi
  fi

  local module=""
  for module in cgi rewrite macro suexec ssl proxy proxy_http; do
    a2enmod $module
  done

  # fuser fails on slicehost CentOS  (/proc/net/tcp is empty)
  #if fuser 443/tcp >/dev/null || netstat -ln --tcp|grep -q :443
  #then
  #  :
  #else
  #  echo 'Listen 443' >> "$_apache_base_dir"/conf.d/webenabled.conf
  #fi

  if hash systemctl &>/dev/null; then
    systemctl enable devpanel-taskd
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
