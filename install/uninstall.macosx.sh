#!/bin/bash


# main

[ $# -eq 0 ] && usage

if [ "${0:0:1}" != / ]; then
  error "please run this script with the full path, non-relative."
fi
script_dir=`dirname "$0"`

if [ $EUID -ne 0 ]; then
  echo "Error: This script needs to run with ROOT privileges." 1>&2
  exit 1
fi

unset confirmed
getopt_flags='yd'
while getopts $getopt_flags OPTN; do
  case "$OPTN" in
    y)
      confirmed=1
      ;;
    d)
      set -x
      ;;
  esac
done
shift $(( $OPTIND - 1 ))

if [ -z "$confirmed" ]; then
  echo "Error: please use option -y to confirm that you really want to uninstall the software and lose data" 1>&2
  exit 1
fi

install_dir="$1"
if [[ "$install_dir" =~ ^/*$ ]]; then
  echo "Error: install_dir can't be /" 1>&2
  exit 1
fi

dp_user="devpanel"
dp_group="$dp_user"

user_path="/Users/$dp_user"
group_path="/Groups/$dp_group"
if dscl . -read "$group_path" &>/dev/null; then
  if dscl . delete "$group_path"; then
    echo "Successfully removed group $group_path."
  else
    echo "Failed to remove group $group_path."
  fi
fi

if dscl . -read "$user_path" &>/dev/null; then
  user_home_line=`dscl . -read "$user_path" NFSHomeDirectory`
  if [ $? -eq 0 -a -n "$user_home" ]; then
    user_home="${user_home_line##*: }"
    if [ "$user_home" != "/" -a -d "$user_home" ]; then
      echo rm -rf "$user_home"
    fi
  fi

  if dscl . delete "$user_path"; then
    echo "Successfully removed user $user_path."
  else
    echo "Failed to remove user $user_path."
  fi
fi

taskd_pids_str=`fuser /var/run/.taskd.lock`
if [ $? -eq 0 ]; then
  taskd_pids=${taskd_pids_str##*: }
  if [ -n "$taskd_pids" ]; then
    echo "Stopping taskd pids $taskd_pids"
    kill $taskd_pids
  fi
fi

echo "Removing the install dir $install_dir"
echo rm -rf "$install_dir"

echo "Finished removal of devPanel software"
