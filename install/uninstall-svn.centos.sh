#!/bin/sh
/etc/init.d/httpd-svn stop
chkconfig --del httpd-svn
rm /etc/init.d/httpd-svn
userdel -r r_svnmgr
rm -rf /home/clients/websites/w_websvn
rm -f /etc/httpd/conf.d/websvn_frontend.conf
rm -rf /etc/httpd/logs/repos
apachectl graceful

rm -rf /etc/httpd/conf/repos 
rm -f /etc/httpd/conf/httpd-svn.conf
rm -f /etc/httpd/conf/manage-svn.conf
rm -f /etc/httpd/conf/svn-clients.port
rm -f /etc/httpd/conf/svn-clients.map

