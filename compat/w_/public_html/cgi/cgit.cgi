#!/usr/bin/env perl
use strict;
use warnings;
use CGI (qw( -oldstyle_urls ));
use CGI::Session;
use Cwd (qw( abs_path ));
use FindBin (qw( $RealBin ));
use lib $RealBin . "/../../../../lib/perl5";

my $cgi;

sub log_error {
  my($msg) = @_;

  warn "Error: $msg\n";
  print $cgi->header( -type => "text/plain" );
  print $msg . "\n";
}

sub log_error_n_exit {
  log_error(@_);
  exit(1);
}

# main

$cgi = CGI->new;
CGI::Session->name("DP_AUTH");

my @user_ar = getpwuid($>);
if(!@user_ar) {
  log_error_n_exit("Authentication failed");
}

my $sessions_dir = sprintf("%s/.devpanel/tmp/sessions", $user_ar[7]);

my $session = CGI::Session->load(undef, $cgi, { Directory => $sessions_dir });
if(!$session || $session->is_empty()) {
  log_error_n_exit("Authentication failed");
}

my $cgit_url = $cgi->url(-absolute => 1, -path_info => 1);
      
if(!$session->param('cgit_config')) {
  log_error_n_exit("missing cgit_conf file in session");
}

printf "Set-Cookie: %s\n", $cgi->cookie(
  -name    => $session->name(),
  -value   => $session->id(),
  -domain  => $cgi->server_name(),
  -path    => $cgi->url( -absolute => 1 ),
  -expires => '+1h'
);

if($cgi->param('devpanel_repo')) {
  # convenience option to redirect the user to a specific repo
  
  print $cgi->redirect( -uri => sprintf("%s/%s", $cgit_url,
                        scalar($cgi->param('devpanel_repo'))) );
  exit(0);
}

my $cgit_bin = abs_path($RealBin . "/../../../../bin/utils/cgit/current/cgi-bin/cgit.cgi");
if( -x $cgit_bin ) {
  $ENV{CGIT_CONFIG} = $session->param('cgit_config');
  exec($cgit_bin);
} else {
  log_error_n_exit("unable to find the executable binary $cgit_bin");
}
