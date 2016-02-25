#!/bin/bash

IFS=!
ARRAY=(`find /home/clients/websites/* -maxdepth 0 -type d -printf %f!`)

for username in ${ARRAY[*]}; do
  # mem usage
  IFS=$'\n'
  RSS_ARR=(`ps -u $username orss|grep -v RSS`)
  mem=$( awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' ${RSS_ARR[@]} )
  procs=${#RSS_ARR[@]}

  # disk space usage
  user_diskspace_usage=`nice -n 19 du -s /home/clients/websites/${username}/|awk '{print $1}'`

  # db space usage
  db=$(sed 's/w_//g' <<< $username)
  db_size=`nice -n 19 du -s /home/clients/databases/b_${db}/|awk '{print $1}'`
  logs_size=$(nice -n 19 du -s /home/clients/websites/$username/logs/ | awk '{print $1}')

  echo "$username,$(((user_diskspace_usage + db_size) / 1024)),$((mem / 1024)),$procs,$((logs_size / 1024)),$((db_size / 1024))"
done
