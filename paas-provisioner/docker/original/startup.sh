#!/bin/bash

service apache2 restart
# start mysqld
if [ `ps aux|grep -v grep|grep -c mysqld` -gt 0 ]; then
  sleep infinity
else
  mysqld --datadir=/home/clients/databases/b_${USER}/mysql --user=b_${USER} --port=4000 --socket=/home/clients/databases/b_${USER}/mysql/mysql.sock
  sleep infinity
fi
