#!/usr/bin/env perl
use strict;
use warnings;
use CGI (qw( -oldstyle_urls ));
use CGI::Session;
use Cwd (qw( abs_path ));
use FindBin (qw( $RealBin ));
use lib $RealBin . "/../../../../lib/perl5";
use DevPanel::App::TokenAuth;

my $cgi;
my $session;

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

my $dp_op    = $cgi->param('dp_op');
my @user_ar = getpwuid($>);
if(!@user_ar) {
  log_error_n_exit("Authentication failed");
}

my $just_created = 0;
if(defined($dp_op) && $dp_op eq "auth") {
  my $dp_token = $cgi->param('dp_token');
  if(!defined($dp_token)) {
    log_error_n_exit("Authentication failed");
  }

  if(!DevPanel::App::TokenAuth::authenticate(token_str => $dp_token, app => "cgit")) {
    log_error_n_exit("Authentication failed");
  }

  my $tmp_dir = sprintf("%s/.tmp", $user_ar[7]);
  if(! -e $tmp_dir) {
    mkdir($tmp_dir);
  }

  $just_created = 1;
  $session = CGI::Session->new(undef, undef, { Directory => $tmp_dir });
  $session->param('auth' => 1);
  $session->flush(); # save on disk now, because exec() will not return

} else {
  $session = CGI::Session->load(undef, $cgi, { Directory => sprintf("%s/.tmp", $user_ar[7]) });
  if(!$session || $session->is_empty()) {
    log_error_n_exit("Authentication failed");
  }
}

printf "Set-Cookie: %s\n", $cgi->cookie(
  -name    => $session->name(),
  -value   => $session->id(),
  -domain  => $cgi->server_name(),
  -path    => $cgi->url( -absolute => 1 ),
  -expires => '+1h'
);

if($just_created) {
 print $cgi->redirect($cgi->url());
 exit(0);
} else {
  my $cgit_bin = abs_path($RealBin . "/../../../../bin/utils/cgit/cgi-bin/cgit.cgi");
  if( -x $cgit_bin ) {
    exec($cgit_bin);
  } else {
    log_error_n_exit("unable to find the executable binary $cgit_bin");
  }
}
