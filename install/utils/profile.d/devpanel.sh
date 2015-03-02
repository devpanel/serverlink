#!/bin/bash

#######
# PATH
#
# add custom directories to PATH
self_bin=`readlink -e "${BASH_SOURCE[0]}"`
curr_dir=`dirname "$self_bin"`
bin_path=`readlink -e "$curr_dir/../../../bin/.path"`
bin_path_status=$?

if [ $bin_path_status -eq 0 ] && ! [[ "$PATH" =~ :?$bin_path:? ]]; then
  PATH="$bin_path:$PATH"
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
