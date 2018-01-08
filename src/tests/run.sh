#!/bin/bash

self_bin=$(readlink -e "${BASH_SOURCE[0]}")
if [ $? -ne 0 ]; then
  echo "Error: unable to get self path" 1>&2
  exit 1
fi

self_dir="${self_bin%/*}"

"$self_dir/clitest" -1 "$self_dir/tests.clitest"
