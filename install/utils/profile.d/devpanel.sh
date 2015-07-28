#!/bin/bash
########################
# IMPORTANT REMINDER:
# this script should be posix compliant, so no bash exclusive syntax
#
# Other notes:
#
# * $0 is not the script path when run from su, so don't use it
#######
# PATH
#
# add custom directories to PATH
source_file="/etc/default/devpanel"
if [ -z "$DEVPANEL_HOME" ] && [ -f "$source_file" ]; then
  . "$source_file"
fi

if [ -n "$DEVPANEL_HOME" ] && ! echo "$PATH" | egrep -q ":?$DEVPANEL_HOME:?"; then
  DEVPANEL_PATH="${DEVPANEL_PATH:-$DEVPANEL_HOME/bin/.path}"
  PATH="$DEVPANEL_PATH:$PATH"
fi

/bin/true
