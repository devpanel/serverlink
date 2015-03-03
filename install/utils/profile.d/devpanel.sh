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

########
# Drush
########
#
# if there's a custom PHP version set on user home, then
# set drush related variables to use it
home_php_cli="$HOME/bin/php-cli"
home_php_cgi="$HOME/bin/php-cgi"
home_php="$HOME/bin/php"

for php_n in "$home_php_cli" "$home_php_cgi" "$home_php"; do
  if [ -f "$php_n" -a -x "$php_n" ]; then
    export BIN_PHP="$php_n" # backwards compatibility with 
                            # some old drupal cron scripts

    export DRUSH_PHP="$php_n"
    break
  fi
done

/bin/true
