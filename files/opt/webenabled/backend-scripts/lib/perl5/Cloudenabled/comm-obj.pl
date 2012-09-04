#!/usr/bin/perl
use strict;
use warnings;
use Cloudenabled::RPCComm;
use Data::Dumper;

my $cobj = Cloudenabled::RPCComm->new(
  connect_address => 'unix:/tmp/controllerd_socket',
);

if(!$cobj) {
  exit(1);
}

my $rsp = $cobj->send($ARGV[0]);
if($rsp) {
  print Dumper($rsp), "\n";
} elsif(!defined($rsp)) {
  warn "Received nothing.\n";
} else {
  warn "Unknown condition.\n";
}
