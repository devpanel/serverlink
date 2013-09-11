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

sub generate_global_config {
  my($file) = @_;

  if(!open(CONF, ">$file")) {
    warn "Error: unable to open '$file' for writing: $!\n";
    return 0;
  }

  print CONF "
scan-path=/home/git/repositories
cache-dynamic-ttl=1
";
  close(CONF);
}

sub generate_repo_specific_config {
  my($file, $repos_ar) = @_;

  if(!open(CONF, ">$file")) {
    warn "Error: unable to open '$file' for writing: $!\n";
    return 0;
  }

  print CONF "cache-dynamic-ttl=1\n";
  foreach my $r (@$repos_ar) {
    printf CONF "repo.url=%s\nrepo.path=/home/git/repositories/%s.git\n\n", $r, $r;
  }
  
  close(CONF);
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

  my $cgit_str = "cgit";
  my $repo = defined($cgi->param('dp_repo')) ? $cgi->param('dp_repo') : undef;
  if(defined($repo) && $repo =~ /^[\w_\.-]+$/) {
    $cgit_str = "cgit";
    # $cgit_str = "cgit_repo_$repo";
  } elsif(defined($repo)) {
    log_error_n_exit("Invalid syntax for parameter repo");
  }

  $session = CGI::Session->load(undef, $cgi, { Directory => sprintf("%s/.tmp", $user_ar[7]) });
  if($session && !$session->is_empty() && !$session->is_expired()) {
    if(defined($repo)) {
      my $repos_list = $session->param('repositories');
      # only set if there's already a list set
      # if there isn't a list set it means that the user already have global access
      if(defined($repos_list) && !scalar(grep { $_ eq $repo } @$repos_list)) {
        push(@$repos_list, $repo);
        generate_repo_specific_config($session->param('cgit_config'), $repos_list);
      }
    }
  } else {
    if(!DevPanel::App::TokenAuth::authenticate(token_str => $dp_token, app => $cgit_str)) {
      log_error_n_exit("Authentication failed");
    }

    my $tmp_dir = sprintf("%s/.tmp", $user_ar[7]);
    if(! -e $tmp_dir) {
      mkdir($tmp_dir);
    }

    my $tmp_config = sprintf("$tmp_dir/.cgit.conf.$$");
    $session = CGI::Session->new(undef, undef, { Directory => $tmp_dir });
    $session->param('cgit_config' => $tmp_config);
    if(defined($repo)) {
      $session->param('repositories' => [ $repo ] );
      generate_repo_specific_config($session->param('cgit_config'), [ $repo ]);
    } else {
      generate_global_config($session->param('cgit_config'));
    }
    $just_created = 1;
  }

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
 if(defined($cgi->param('dp_repo'))) {
   print $cgi->redirect($cgi->url() . '/' . $cgi->param('dp_repo') );
 } else {
   print $cgi->redirect($cgi->url());
 }

 exit(0);
} else {
  my $cgit_bin = abs_path($RealBin . "/../../../../bin/utils/cgit/cgi-bin/cgit.cgi");
  if( -x $cgit_bin ) {
    $ENV{CGIT_CONFIG} = $session->param('cgit_config');
    exec($cgit_bin);
  } else {
    log_error_n_exit("unable to find the executable binary $cgit_bin");
  }
}
