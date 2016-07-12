#!/bin/bash

# restart postgresql for metasploit
service postgresql restart

# check for backup operation
source /home/clients/websites/backup_info
if [ "$BACKUP" == "true" ]; then
  # cleanup file to avoid unnecessary operations
  echo "" > /home/clients/websites/backup_info
  if [ `ps aux|grep apache2|grep -v grep|wc -l` -gt 0 ]; then
    sleep infinity
  else
    while [ `ps aux|grep apache2|grep -v grep|wc -l` -eq 0 ]; do
      /usr/sbin/apache2ctl -D FOREGROUND
      sleep 1
    done
  fi
else
  # in case of first run
  ## copy configs from db
  cp -dpfR /data/* /home/clients/
  ## patch configs to access db host
  if [ "${APP}" == "wordpress" ]; then sed -i 's/127.0.0.1:4000/db:4000/' /home/clients/websites/w_${USER}/public_html/${USER}/wp-config.php; fi
  if [ "${APP}" == "drupal" ]; then sed -i 's/127.0.0.1/db/' /home/clients/websites/w_${USER}/public_html/${USER}/sites/default/settings.php; fi
  /usr/sbin/apache2ctl -D FOREGROUND
fi
