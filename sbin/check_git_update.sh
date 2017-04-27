#!/bin/bash

IFS=!
LOCAL_APPS_ARRAY=(`find /home/clients/websites/* -maxdepth 0 -type d -printf %f!`)
for username in ${LOCAL_APPS_ARRAY[*]}; do
  username=`echo $username|cut -d '_' -f2`
  git_commits=$(cd /home/clients/websites/w_${username}/public_html/${username} && git rev-list HEAD...origin/master --count 2>&1)
  if [ $(echo $git_commits|grep fatal|wc -l) -gt 0 ]; then git_commits=-1; fi
  echo w_${username},${git_commits}
done
