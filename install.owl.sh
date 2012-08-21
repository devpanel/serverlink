#!/bin/sh

dir0=`dirname "$0"`
dir="$dir0/files"

error()
{
  echo ERROR${1+: }"$@" >&2
  exit 1
}

if ! [ -d "$dir" ]
then
  echo Unpacking files
  tar xpof "$dir0/files.tar" || error
fi

test_perms=`stat -c%a "$dir/usr/local/bin/passgen"` || error "Cannot find var/log/httpd"
[ o"$test_perms" = o"711" ] || error "Bad perms on usr/local/bin/passgen, files.tar should have been unpackated with tar zxpf"

install()
{
  local source="$1"
  local target="$2"
  [ -e "$target" ] && error "$target exists. Are you trying to install WE twice? If not, please remove $target and try again"
  cp -a "$source" "$target" || exit "Cannot create $target"
}
install_symlink()
{
  local source="$1"
  local target="$2"
  ln -sn "$source" "$target" || error "$target exists. Are you trying to install WE twice? If not, please remove $target and try again"
}

#install_crontab()
#{
#  local crontab_contents
#  if crontab_contents=`crontab -l` 2>&1
#  then
#    if echo "$crontab_contents" | grep -q logrotate
#    then
#      echo "(existing crontab already has logrotate, leaving it as is)"
#    else
#      echo "(appending to existing crontab)"
#      ( echo "$crontab_contents" | sed '/^#/{1d;2d;3d}' - $dir/crontab.root|crontab -) || error "Cannot install crontab"
#    fi
#  else
#    echo "(crontab for root does not exist, creating)"
#    crontab - <$dir/crontab.root || error "Cannot install crontab"
#  fi
#}

add_to_config()
{
  local file="$1"
  local text="$2"
  local diag_regex="$3"
  grep -q "$diag_regex" "$file" && error "$text is already in $file. Are you trying to install WE twice? If not, please remove this text and try again"
  echo "$text" >>"$file" || error
}

add_user()
{
  local user="$1"
  shift
  local opts="$*"
  useradd $opts $user || error "User $user exists. Are you trying to install WE twice? If not, please remove this user and try again"
}

add_group()
{
  local group="$1"
  groupadd $group || error "Group $group exists. Are you trying to install WE twice? If not, please remove this user and try again"
}

echo Installing RPMS
rpm -U "$dir/RPMS/"*.rpm || error

mv /home/clients/websites/w_ /home/clients/websites/w_.orig

for subdir in opt/dbmgr \
              opt/doxygen \
              opt/fonts \
              opt/libgd \
              opt/libxvid \
              opt/mm \
              opt/openldap \
              opt/webenabled \
              opt/wit \
              opt/httpd/helpers \
              opt/httpd/config/empty \
              opt/httpd/config/include \
              opt/httpd/config/vmailwww \
              etc/ld.so.conf.d \
              etc/rc.d/init.d \
              etc/logrotate.d \
              etc/httpd \
              etc/profile.d \
              etc/control.d/facilities \
              etc/ssl \
              home/clients/websites \
              home/clients/databases \
              home/r_we \
              var/log \
              usr/local/bin \
              usr/local/sbin \
              usr/local/libexec
do
  echo Installing "$subdir"
  mkdir -m755 -p "/$subdir" || error
  files=`ls -a "$dir/$subdir"` || error
  for file in $files
  do
    [ o"$file" = o"." -o o"$file" = o".." ] && continue
    install "$dir/$subdir/$file" "/$subdir/$file" || error
  done
done

echo Running ldconfig
ldconfig

echo Modifying rc.local
add_to_config /etc/rc.d/rc.local "/sbin/service dbmgr start" "^[^#]*\<dbmgr" || error

echo Enabling services
chkconfig --add dbmgr || error
chkconfig httpd on || error

echo Creating special groups
for group in logview nagios weadmin
do 
  add_group $group || error
done

echo Creating special users
# HOME???
usermod -d /home/clients/websites/w_ w_ || error
add_user r_we -g0 -u0 -o -d /home/r_we -s /opt/webenabled/current/libexec/server || error

# Per 'GRG: a small howto re: the WE template upgrade' 
rm -rf /opt/httpd/logs

echo Creating symlinks
while read source target
do
  [ o"$source" = o"#" ] && continue
  install_symlink "$source" "$target" || error
  readlink -e "$target" >/dev/null || error "$source -> $target: broken symlink created, why? Please update symlinks.lst and perform the installation again"
done < "$dir/symlinks.lst"

# fix for a buggy RPM
chmod ugo+x /opt/libxml2/*/bin/*

chmod go-r /opt/httpd/helpers
chmod go+rx /home/clients /home/clients/websites /home/clients/databases
chown -R w_:virtwww /home/clients/websites/w_
chgrp _httpd /home/clients/websites/w_
chgrp -R nagios /opt/apache/config/conf
chgrp weadmin /opt/webenabled/data /opt/webenabled/config/ssh
chgrp virtwww /var/log/httpd/vmailwww /var/log/httpd/virtwww
chgrp w_ /var/log/httpd/virtwww/w_
chmod 755 /etc/ssl
chmod 711 /etc/ssl/certs
chmod 700 /etc/ssl/keys

echo Setting UID_MIN in /etc/login.defs to 1000
sed -i 's/^\(UID_MIN[ 	]\{1,\}\)500[ 	]*$/\1 1000/' /etc/login.defs || error

echo Disabling Zend Optimizer
sed -i 's/^zend_extension=/;&/' /opt/php/config/php.d/zend_optimizer.ini || error

/opt/webenabled/current/libexec/config-auth-keygen || error

echo Starting apache
apachectl start || error "Unknown error. Please start apache manually before creating any websites"

echo "Enabling users' crontabs"
control crontab public || error 'control crontab public failed'

echo "Enabling SFTP"
control webenabled_sftp wrapper || error 'control webenabled_sftp wrapper failed'

#echo "Installing crontab for root"
#install_crontab

echo WebEnabled successfully installed
