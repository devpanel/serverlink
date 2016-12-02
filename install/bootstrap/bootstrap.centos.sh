#!/bin/bash

bootstrap_centos() {
  yum -y install git perl perl-devel perl-CGI perl-Time-HiRes \
    perl-Digest-HMAC perl-Digest-SHA perl-Crypt-SSLeay \
    redhat-lsb-core perl-IO-Socket-SSL perl-URI
  
  # test whether Data::Dumper is available, it's needed by taskd
  perl -MData::Dumper -e 'exit 0;' &>/dev/null
  if [ $? -eq 0 ]; then
    :
  else
    yum -y install perl-Data-Dumper
  fi
}
