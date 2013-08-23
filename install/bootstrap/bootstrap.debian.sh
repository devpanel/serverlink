#!/bin/bash

bootstrap_debian() {
  export DEBIAN_FRONTEND='noninteractive'
  apt-get -y install libnet-ssleay-perl libjson-xs-perl
}
