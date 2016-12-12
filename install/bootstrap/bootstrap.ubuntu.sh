#!/bin/bash

bootstrap_ubuntu() {
  export DEBIAN_FRONTEND='noninteractive'
  apt-get update
  apt-get -y install libcrypt-ssleay-perl libjson-xs-perl ca-certificates \
             git libio-socket-ssl-perl liburi-perl
}
