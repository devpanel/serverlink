#!/bin/bash

# local LOCAL_APPS_ARRAY
IFS=!
LOCAL_APPS_ARRAY=(`find /home/clients/websites/* -maxdepth 0 -type d -printf %f!`)
for username in ${LOCAL_APPS_ARRAY[*]}; do
  username=`echo $username|cut -d '_' -f2`
  git_commits=$(cd /home/clients/websites/w_${username}/public_html/${username} && git rev-list HEAD...origin/master --count 2>&1)
  if [ $(echo $git_commits|grep fatal|wc -l) -gt 0 ]; then git_commits=-1; fi
  echo w_${username},${git_commits}
done

# docker apps
if [ $(whereis docker|grep -c /usr) -gt 0 ]; then
  IFS=$'\n'
  DOCKER_APPS_ARRAY=(`docker ps|tail -n +2|awk '{print $NF}'`)
  for docker_container in ${DOCKER_APPS_ARRAY[*]}; do
    docker exec ${docker_container} /opt/webenabled/sbin/check_git_update.sh
  done
fi
