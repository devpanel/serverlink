#!/bin/bash

self_bin=$(readlink -e "${BASH_SOURCE[0]}")
if [ $? -ne 0 ]; then
  echo "Error: unable to get self path" 1>&2
  exit 1
fi

self_dir="${self_bin%/*}"

declare -a cmd_args_ar=()
while [ -n "$1" ]; do
  cmd_args_ar+=( "$1" )
  shift
done

if [ ${#cmd_args_ar[@]} -eq 0 ]; then
  cmd_args_ar=( -1 "$self_dir/tests.clitest" )
else
  n_args=${#cmd_args_ar[@]}
  last_arg="${cmd_args_ar[$(( $n_args - 1 ))]}"
  if [ -n "$last_arg" -a "${last_arg:0:1}" == - ]; then
    # last arg is not a file name (assuming that filenames don't start with a
    # dash). Append the default test file to the list of arguments
    cmd_args_ar+=( "$self_dir/tests.clitest" )
  fi
fi

"$self_dir/clitest" "${cmd_args_ar[@]}"
