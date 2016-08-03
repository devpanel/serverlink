#!/bin/bash

bootstrap_ubuntu() {
  export DEBIAN_FRONTEND='noninteractive'
  apt-get update
  apt-get -y install libcrypt-ssleay-perl libjson-xs-perl ca-certificates git

  # test whether CGI::Util is available, it's needed by taskd
  # from Ubuntu 16 it's not included in the perl distribution
  perl -MCGI::Util -e 'exit 0;' &>/dev/null
  if [ $? -eq 0 ]; then
    :
  else
    apt-get -y install libcgi-pm-perl
  fi
}
