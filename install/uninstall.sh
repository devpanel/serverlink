#!/bin/bash
umask 022

usage() {
  echo "
Usage: $0 -y [ options ]

  Options:
    -y          yes, you really want to uninstall everything
    -d          enable debug, print every command executed
    -T          running through taskd

  This script removes all DevPanel software and related data. You'll lose
  data if you run this script!
"

  if [ $EUID -ne 0 ]; then
    echo "This script requires ROOT privileges to be run."
    echo
  fi

  exit 1
}

kill_using_path() {
  local path="$1"
  local n_max_tries=${2:-3}

  if ! fuser -s "$path"; then
    return 0
  fi

  # try to kill the process with SIGTERM $n_max_tries
  local -i i=0
  while [ $i -le $n_max_tries ]; do
    i+=1
    fuser -k -TERM "$path"
    sleep 3
    if ! fuser -s "$path"; then
      return 0
    fi
  done

  # returned without a successful kill, let's kill -9 then
  fuser -k "$path"
}

cleanup() {
  unlock_path "$uninstall_base_dir"
}

# main

[ $# -eq 0 ] && usage

if [ "${0:0:1}" != / ]; then
  echo "Error: please run this script with the full path, non-relative." 1>&2
  exit 1
fi
script_dir=`dirname "$0"`

if [ $EUID -ne 0 ]; then
  echo "Error: This script needs to run with ROOT privileges." 1>&2
  exit 1
fi

unset confirmed through_taskd
getopt_flags='ydT'
while getopts $getopt_flags OPTN; do
  case "$OPTN" in
    y)
      confirmed=1
      ;;
    d)
      set -x
      ;;
    T)
      through_taskd=1
      ;;
    *)
      exit 1
      ;;
  esac
done
[ $OPTIND -gt 1 ] && shift $(( $OPTIND - 1 ))

if [ -z "$confirmed" ]; then
  echo "Error: please use option -y to confirm that you really want to uninstall the software and lose data" 1>&2
  exit 1
fi

self_bin=$(readlink -e "$0")
self_dir="${self_bin%/*}"
install_dir=$(readlink -e "$self_dir/..")

if [ "$install_dir" == / ]; then
  echo "Error: install_dir can't be /" 1>&2
  exit 1
fi

lib_file="$install_dir/lib/functions"
if ! source "$lib_file"; then
  echo "Error. Unable to load auxiliary functions from file " 1>&2
  exit 1
fi

if [ "${PWD##$install_dir}" != "$PWD" ]; then
  error "this shell is currently on the install dir. Please cd / before continuing."
fi

load_devpanel_config || exit $?

linux_distro=$(wedp_auto_detect_distro)
status=$?
if [ $status -ne 0 ]; then
  error "unable to detect the system distribution"
fi

vhosts_home_dir="$lamp__apache_paths__virtwww_homedir"
mysqls_dir="$lamp__apache_paths__instances_homedir"

apache_vhost_logs_dir="$lamp__apache_paths__vhost_logs_dir"

apache_base_dir="$lamp__apache_paths__base_dir"

apache_includes_dir="$lamp__apache_paths__includes_dir"

mysql_inc_dir="$conf__mysql_paths__conf_d"

uninstall_base_dir="$conf__paths__data_dir/.previous_installs"
if [ ! -d "$uninstall_base_dir" ] && ! mkdir -m 700 "$uninstall_base_dir"; then
  error "unable to create archive directory $uninstall_base_dir"
fi

if ! lock_path "$uninstall_base_dir" >/dev/null; then
  error "unable to lock path $uninstall_base_dir"
fi
trap 'cleanup' EXIT

uninstall_archive_dir="$uninstall_base_dir/$(date +%b-%d-%Y--%Hh%Mm-%Z)"
if ! mkdir -m 700 "$uninstall_archive_dir"; then
  error "unable to create directory $uninstall_archive_dir"
fi
vhost_archives_dir="$conf__paths__data_dir/vhost_archives"
old_removed_vhosts_dir="$conf__paths__data_dir/removed_vhosts"

db_stale_dir="$uninstall_archive_dir/db_stale"
vhost_stale_dir="$uninstall_archive_dir/www_stale"

for asdf_dir in "$db_stale_dir" "$vhost_stale_dir"; do
  if ! mkdir "$asdf_dir"; then
    error "unable to create directory $asdf_dir"
  fi
done

# MacOSX as a provisioner has it's own removal logic
if [ "$linux_distro" == "macosx" ]; then
  exec "$script_dir/uninstall.$linux_distro.sh" -y "$install_dir"
fi

# Linux removal logic
stop_apache

# remove databases and vhosts
while read passwd_line; do
  IFS=":" read user x uid gid gecos home shell <<< "$passwd_line"

  if [ ${#user} -gt 2 -a "${user:0:2}" == "w_" ]; then
    vhost=$(get_vhost_from_linuxuser)

    # first try the usual removal
    if devpanel remove vhost --vhost "$vhost" >/dev/null; then
      echo "Successfully archived and removed vhost $vhost" 1>&2
      removal_st=$?
      continue # successfully removed, go to the next
    fi

    # usual removal failed, let's deal with it

    # first move the web files
    if [ -d "$home" ]; then
      kill_using_path "$home"
      mv -v -f "$home" "$vhost_stale_dir"
    fi

    if getent passwd "$user" &>/dev/null; then
      "$install_dir/libexec/remove-user" "$user"
    fi

    # now move the stale database dir, if any
    if getent passwd "b_$vhost" &>/dev/null; then
      db_dir=$(eval echo \~"b_$vhost")

      if [ -d "$db_dir" ]; then
        kill_using_path "$db_dir"
        mv -v -f "$db_dir" "$db_stale_dir"
      fi

      "$install_dir/libexec/remove-user" "b_$vhost"
    fi
  fi
done < <(getent passwd | egrep ^w_)

[ -d "$apache_vhost_logs_dir" ] && rm_rf_safer "$apache_vhost_logs_dir"

# remove database users in case it didn't have the w_user companion on
# previous loop
while read passwd_line; do
  IFS=":" read user x uid gid gecos home shell <<< "$passwd_line"
  userdel -r "$user"
done < <(getent passwd | egrep ^b_)

# return null expansions when /path/name* doesn't expand to anything
shopt -s nullglob

# remove anything stale from vhosts directory
for v_path in "$vhosts_home_dir"/*; do
  [ ! -d "$v_path" ] && continue

  kill_using_path "$v_path"

  if [ "${v_path##*/}" == "w_" ]; then
    rm -rf "$v_path" # for the w_ directory we just remove it,
                     # as it doesn't contain personal data
  else
    mv -v -f "$v_path" "$vhost_stale_dir"
  fi

done

# remove anything stale from databases directory
for v_path in "$mysqls_dir"/*; do
  [ ! -d "$v_path" ] && continue

  kill_using_path "$v_path"
  mv -v -f "$v_path" "$db_stale_dir"
done

for inc_dir in "$mysql_inc_dir"; do
  rm -v -f -- "$inc_dir/"*devpanel*
done

if hash systemctl &>/dev/null; then
  has_systemd=1
  # disable taskd on boot, but don't stop it now
  systemctl disable devpanel-taskd
fi

if hash update-rc.d &>/dev/null; then
  taskd_initd=/etc/init.d/devpanel-taskd

  if [ -f "$taskd_initd" ]; then
    update-rc.d -f devpanel-taskd remove
  fi
fi

# move old vhost archives
mv -v "$vhost_archives_dir" "$uninstall_archive_dir"
mv -v "$old_removed_vhosts_dir" "$uninstall_archive_dir"

# vagrant specific code
vagrant_dir=~devpanel/vagrant
if [ -d "$vagrant_dir" ]; then
  for D in "$vagrant_dir"/*; do
    if [ -d "$D" ]; then
      echo "Destroying VM `basename "$D"`..."
      su -l -c "cd $D && vagrant destroy -f ; cd $D/.. ; rm -rf $D" devpanel
    fi
  done
fi

if getent passwd git &>/dev/null; then
  git_home_dir=$(eval echo \~git)

  [ -d "$git_home_dir" ] && mv -v -f "$git_home_dir" "$uninstall_archive_dir"
fi

for u in git w_; do
  if getent passwd "$u" &>/dev/null; then
    userdel -r "$u"
  fi
done

for g in virtwww weadmin w_; do
  if getent group "$g" &>/dev/null; then
    groupdel "$g"
  fi
done

 # Uninstall Zabbix
 $install_dir/install/install-zabbix off
 
$install_dir/libexec/change-iptables-rules -D

# remove the remaining system paths (not removed before because it needs taskd
# to report the execution status
for path_dir in /etc/init.d /etc/init /etc/profile.d \
  "$apache_base_dir" "$apache_includes_dir"; do

  rm -f "$path_dir/devpanel"*
  rm -f "$path_dir/webenabled"*
done

rm -v -f /etc/cron*/devpanel*
rm -v -f /etc/logrotate.d/devpanel*
rm -v -f /etc/profile.d/devpanel*
rm -v -f /etc/init/devpanel*
rm -v -f /etc/default/devpanel*
rm -v -f /etc/sudoers.d/devpanel*
rm -f /usr/local/bin/devpanel* /usr/bin/devpanel*

if [ -d "$conf__paths__data_dir/vhost_archives" ]; then
  mv -f "$conf__paths__data_dir/vhost_archives" "$uninstall_archive_dir"
fi

(
  # ignore SIGTERM when the parent shell exits
  trap 'echo Ignoring SIGTERM' TERM

  if [ -n "$through_taskd" ]; then
    # wait a bit for taskd to report the task
    sleep 10
  fi

  if [ -n "$has_systemd" ]; then
    systemctl --no-block stop    devpanel-taskd
    systemctl --no-block disable devpanel-taskd
    rm -v -f /lib/systemd/system/devpanel*
  else
    service devpanel-taskd stop
    if hash chkconfig &>/dev/null; then
      chkconfig devpanel-taskd off
    elif hash update-rc.d &>/dev/null; then
      update-rc.d devpanel-taskd remove
    fi
  fi

  "$install_dir/libexec/remove-user" devpanel

  if getent group devpanel &>/dev/null; then
    groupdel devpanel
  fi

  rm_rf_safer "$install_dir"

  [ -d /var/log/webenabled ] && rm -rf /var/log/webenabled
) &

if [ -z "$through_taskd" ]; then
  wait
fi

echo
echo "Successfully uninstalled devPanel software. Backup made on $uninstall_archive_dir"
exit 0
