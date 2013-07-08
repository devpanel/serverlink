#!/bin/bash

bootstrap_centos() {
  yum -y install perl perl-devel perl-CGI perl-Time-HiRes \
    perl-Digest-HMAC perl-Digest-SHA perl-Net-SSLeay

}
