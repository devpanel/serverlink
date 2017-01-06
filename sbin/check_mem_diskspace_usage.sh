#!/bin/bash

# local apps
IFS=!
LOCAL_APPS_ARRAY=(`find /home/clients/websites/* -maxdepth 0 -type d -printf %f!`)
for username in ${LOCAL_APPS_ARRAY[*]}; do
  # mem usage
  IFS=$'\n'
  W_RSS_ARR=(`ps -u $username orss|grep -v RSS`)
  B_RSS_ARR=(`ps -u b_${username#w_} orss|grep -v RSS`)
  mem=$(($( awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' ${W_RSS_ARR[@]} ) + $( awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' ${B_RSS_ARR[@]} )))
  procs=$((${#W_RSS_ARR[@]} + ${#B_RSS_ARR[@]}))

  # disk space usage
  user_diskspace_usage=`nice -n 19 du -s /home/clients/websites/${username}/|awk '{print $1}'`

  # db space usage
  db=$(sed 's/w_//g' <<< $username)
  db_size=`nice -n 19 du -s /home/clients/databases/b_${db}/|awk '{print $1}'`
  logs_size=$(nice -n 19 du -s /home/clients/websites/$username/logs/ | awk '{print $1}')

  echo "$username,$(((user_diskspace_usage + db_size) / 1024)),$((mem / 1024)),$procs,$((logs_size / 1024)),$((db_size / 1024))"
done

# docker apps
if [ $(whereis docker|grep -c /usr) -gt 0 ]; then
  DOCKER_APPS_ARRAY=(`docker ps|tail -n +2|awk '{print $NF}'`)
  for docker_container in ${DOCKER_APPS_ARRAY[*]}; do
    docker exec ${docker_container} /opt/webenabled/sbin/check_mem_diskspace_usage.sh
  done
fi

# throw 0 instead empty data, which will return ZBX_NOTSUPPORTED
if [ ${#LOCAL_APPS_ARRAY[@]} -eq 0 -a ${#DOCKER_APPS_ARRAY[@]} -eq 0 ]; then
  echo "0"
fi
