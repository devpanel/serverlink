#!/usr/bin/perl -w
package Cloudenabled::Controller::Constants;
require Exporter;
use strict;
use warnings;
use constant CE_FL_SERVER_DISABLED   => 1;

use constant CE_CTE_UUID_REGEX => qr/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
use constant CE_CTE_HOSTNAME_REGEX => qr/^[a-zA-Z0-9]([a-zA-Z0-9-]*\.){1,4}[A-Za-z]{2,4}$/;

use constant CE_FL_SESSION_CLOSED => 1;

our @ISA = qw( Exporter );
our @EXPORT = qw( 
  CE_FL_SERVER_DISABLED CE_CTE_UUID_REGEX CE_CTE_HOSTNAME_REGEX
  CE_FL_SESSION_CLOSED
);

our @EXPORT_OK = (qw(

));

1;
