#!/bin/bash

# get variables
IP_ADDRESS=`ip ad sh dev eth0|grep 'inet 172'|awk -F'/16' '{print $1}'|awk '{print $2}'`
PORT=`ps aux|grep mysqld|grep -v grep|awk '{print $14}'|awk -F'=' '{print $2}'`
if [ -z "$PORT" ]; then PORT=4000; fi
USER=`find /home/clients/websites -maxdepth 1 ! -type l|tail -1|awk -F'w_' '{print $2}'`
PASSWORD=`tail -1 /home/clients/websites/w_${USER}/.mysql.passwd|awk -F':' '{print $2}'`
# export variables to file in shared volume
echo "$IP_ADDRESS:$PORT:$USER:$PASSWORD" > /data/databases/db_info

# check for clone operation
source /data/databases/clone_info
if [ "$CLONE" == "true" ]; then
  # cleanup file to avoid unnecessary operations and place debug info
  echo "USER:${USER} DOMAIN:${DOMAIN} DST_USER:${DST_USER} DST_DOMAIN:${DST_DOMAIN}" > /data/databases/clone_info
else
  # copy configs from db to shared dir for web container in case of first run
  cp -dpfR /home/clients/* /data/
fi

# start mysqld
if [ `ps aux|grep -v grep|grep -c mysqld` -gt 0 ]; then
  sleep infinity
else
  while [ `ps aux|grep -v grep|grep -c mysqld` -eq 0 ]; do
    mysqld --datadir=/home/clients/databases/b_${USER}/mysql --user=b_${USER} --port=4000 --socket=/home/clients/databases/b_${USER}/mysql/mysql.sock
    sleep 1
  done
fi
