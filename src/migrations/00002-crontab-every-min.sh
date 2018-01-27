#!/bin/bash

self_bin=`readlink -e "$0"`
if [ $? -ne 0 ]; then
  echo "Error: unable to get self path" 1>&2
  exit 1
fi

self_dir="${self_bin%/*}"
sys_dir="${self_dir%/*/*}"

cp -r "$sys_dir/install/skel/common/etc/cron.d/." /etc/cron.d/
