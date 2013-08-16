#!/usr/bin/env perl
use strict;
use warnings;
use CGI (qw( -oldstyle_urls ));
use CGI::Session;
use Cwd (qw( abs_path ));
use FindBin (qw( $RealBin ));
use lib $RealBin . "/../../../../lib/perl5";
use DevPanel::App::CGIUtils;
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

my $app_name = "shellinabox";

$cgi = CGI->new;
CGI::Session->name("DP_AUTH");

my $just_created = 0;
my $dp_op     = $cgi->param('dp_op');
my $token_str = $cgi->param('dp_token');

my @user_ar = getpwuid($>);
if(!@user_ar) {
  log_error_n_exit("Error: unable to get information for the current user");
}

my @group_ar = getgrgid($));
if(!@group_ar) {
  log_error_n_exit("Error: unable to get information for the current group");
}

$session = CGI::Session->load(undef, $cgi,
              { Directory => sprintf("%s/.tmp", $user_ar[7]) }
);

if(is_valid_app_session($session, $app_name)) {
  printf "Set-Cookie: %s\n", $cgi->cookie(
    -name    => $session->name(),
    -value   => $session->id(),
    -domain  => $cgi->server_name(),
    -path    => $cgi->url( -absolute => 1 ),
    -expires => '+1h'
  );

  print $cgi->redirect(sprintf("http://%s/-ctl/shellinabox-proxy/%s", $cgi->server_name(),
                                        $session->param('token')));
} elsif(defined($dp_op) && $dp_op eq "auth") {
  if(!defined($token_str)) {
    log_error_n_exit("Authentication failed");
  }

  if(!DevPanel::App::TokenAuth::authenticate(token_str => $token_str,
                                              app => $app_name)) {
    log_error_n_exit($DevPanel::App::TokenAuth::error_str);
  }

  my $tmp_dir = sprintf("%s/.tmp", $user_ar[7]);
  if(! -e $tmp_dir) {
    mkdir($tmp_dir);
  }

  $session = CGI::Session->new(undef, undef,
                { Directory => sprintf("%s/.tmp", $user_ar[7]) }
  );

  $session->param('auth', 1);
  $session->param('app', 'shellinabox');
  $session->param('token', $token_str);
  $session->flush();

  print $cgi->redirect($cgi->url());
} else {
  log_error_n_exit("Unknown request");
}
