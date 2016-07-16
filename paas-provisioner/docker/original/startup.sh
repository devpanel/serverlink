#!/bin/bash

# check for backup operation
source /home/clients/websites/backup_info
if [ "$BACKUP" == "true" ]; then
  # cleanup file to avoid unnecessary operations
  echo "" > /home/clients/websites/backup_info
  if [ `ps aux|grep apache2|grep -v grep|wc -l` -gt 0 ]; then
    sleep infinity
  else
    # start mysqld
    if [ `ps aux|grep -v grep|grep -c mysqld` -gt 0 ]; then
      sleep infinity
    else
      while [ `ps aux|grep -v grep|grep -c mysqld` -eq 0 ]; do
        mysqld --datadir=/home/clients/databases/b_${USER}/mysql --user=b_${USER} --port=4000 --socket=/home/clients/databases/b_${USER}/mysql/mysql.sock
        sleep 1
      done
    fi
  fi
else
  # start mysqld
  if [ `ps aux|grep -v grep|grep -c mysqld` -gt 0 ]; then
    sleep infinity
  else
    while [ `ps aux|grep -v grep|grep -c mysqld` -eq 0 ]; do
      mysqld --datadir=/home/clients/databases/b_${USER}/mysql --user=b_${USER} --port=4000 --socket=/home/clients/databases/b_${USER}/mysql/mysql.sock
      sleep 1
    done
  fi
  # /usr/sbin/apache2ctl -D FOREGROUND
fi
