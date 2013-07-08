#!/bin/bash

bootstrap_ubuntu() {
  export DEBIAN_FRONTEND='noninteractive'
  apt-get -y install libnet-ssleay-perl libjson-xs-perl
}
