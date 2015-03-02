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

/bin/true
