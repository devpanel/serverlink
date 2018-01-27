#!/bin/bash
state_dir=/var/spool/devpanel

if [ -f "$state_dir/state.ini" ]; then
  exit 0
fi

if [ -n "$conf__migrations__latest_step" ]; then
  cp -dr "$sys_dir/install/skel/common/var/spool/devpanel" "${state_dir%/*}"
  chmod 711 "$state_dir"
else
  echo "Error: missing value of conf__migrations__latest_step" 1>&2
  exit 1
fi
