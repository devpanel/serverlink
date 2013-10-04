#!/bin/bash

bootstrap_centos() {
  yum -y install git perl perl-devel perl-CGI perl-Time-HiRes \
    perl-Digest-HMAC perl-Digest-SHA perl-Crypt-SSLeay
}
