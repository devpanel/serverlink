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

if [ -n "$HOME" ] && ! echo "$PATH" | egrep -q ":?$HOME/bin/?:?"; then
  [ -d "$HOME/bin" ] && PATH="$HOME/bin:$PATH"
fi

if [ -z "$LS_COLORS" ] && hash dircolors >/dev/null 2>&1; then
  eval $(dircolors -b 2>/dev/null)
fi

if ! alias ls >/dev/null 2>&1; then
  alias ls='ls -F --color=tty'
fi

if [ "$PS1" = '\s-\v\$ ' ]; then
  PS1='[\u@\h:\w]\$ '
fi

/bin/true
