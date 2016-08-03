#!/bin/bash

bootstrap_centos() {
  yum -y install git perl perl-devel perl-CGI perl-Time-HiRes \
    perl-Digest-HMAC perl-Digest-SHA perl-Crypt-SSLeay \
    redhat-lsb-core
  
  # test whether CGI::Util is available, it's needed by taskd
  # from Ubuntu 16 it's not included in the perl distribution
  perl -MData::Dumper -e 'exit 0;' &>/dev/null
  if [ $? -eq 0 ]; then
    :
  else
    yum -y install perl-Data-Dumper
  fi
}
