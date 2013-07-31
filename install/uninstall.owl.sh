#!/bin/sh -x
dir=`dirname "$0"`/current

# enable if some dirs in which symlinks are created 
# are not to be removed completely
#while read source target
#do
#  [ -h "$target" ] && rm  "$target"
#done <"$dir/symlinks.lst"

apachectl stop
service dbmgr stop
userdel apache
userdel w_
userdel r_we
groupdel apache
groupdel virtwww
groupdel nagios
groupdel weadmin
groupdel w_
chkconfig --del dbmgr
rm -rf /usr/local/bin 
rm -rf /usr/local/sbin
rm -rf /opt
rm -rf /etc/ld.so.conf.d
rm -f /etc/rc.d/init.d/dbmgr
rm -rf /etc/skel.sql
rm -f /etc/logrotate.d/apache
rm -rf /etc/httpd
rm -rf /etc/suexec.map
rm -rf /home/clients/websites/w_
rm -rf /home/r_we
rm -rf /var/log/httpd
ldconfig
rpm -e freetype-devel-2.2.1-owl_add1 freetype-2.2.1-owl_add1
sed -i '/^[^#]*apachectl/d' /etc/rc.d/rc.local
sed -i 's/^\(UID_MIN[ 	]\{1,\}\)1000[ 	]*$/\1 500/' /etc/login.defs || error
