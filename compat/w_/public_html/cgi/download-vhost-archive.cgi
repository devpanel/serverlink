#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use Cwd (qw( abs_path ));
use CGI;
use CGI::Session;

BEGIN {
  if(!exists($ENV{HOME})) {
    my $home = (getpwuid($<))[7];
    if($? == 0) {
      $ENV{HOME} = $home;
    } else {
      print "Content-Type: text/plain\n\n";
      print "Error: unable to find HOME directory of current user.\n";
      exit(1);
    }
  }
}

my $app = "download-vhost-archive";

my $cgi = CGI->new;

my $token_str = $cgi->param('token');
my $session_str;
my $cookie;
my $dummy_uri;

if(defined($token_str)) {
  $session_str = $token_str;
} elsif($cookie = $cgi->cookie(CGI::Session->name())) {
  $session_str = $cookie;
} 

if(!defined($session_str)) {
  error_rsp("didn't receive a session identifier");
} elsif($session_str !~ /^[A-Za-z0-9_-]{32}$/) {
  error_rsp("session identifier has an invalid format");
}

my $session_obj = CGI::Session->load(undef, $session_str,
                  { Directory => "$ENV{HOME}/.tmp" }
);

if(!$session_obj) {
  error_rsp("unable to find a valid session");
}

if($session_obj->is_empty()) {
  error_rsp("not a valid session.");
} elsif($session_obj->is_expired()) {
  error_rsp("session expired. Please try again.");
}

if($session_obj->param('devpanel_app') ne $app) {
  error_rsp("got a valid cookie, though it's the wrong app");
}

# from now it's an authenticated request...

# up to here, if the token was specified in the url redirect the user
if($token_str) {
  $dummy_uri = sprintf("%s/%s", $cgi->script_name(),
                            basename($session_obj->param('archive_file')));

  $cookie = $cgi->cookie(
    -name  => CGI::Session->name(),
    -value => $session_obj->id(),
    -path  => $dummy_uri,
    -expires => sprintf("+%ss", $session_obj->expire()),
  );

  print $cgi->redirect(
    -uri      => $dummy_uri,
    -cookie   => [$cookie],
    -expires  => 'now',
  );
  exit(0);
}

# ...otherwise it's an authenticated request and is ready to download
my $archive_str = $session_obj->param('archive_file');
my $archive_file;
if(substr($archive_str, 0, 1) eq "/") {
  $archive_file = $archive_str;
} else {
  $archive_file = abs_path($ENV{HOME} . "/$archive_str");
}

if(length($archive_file) == 0) {
  error_rsp("unable to determine path of archive file from $archive_str");
}

if( ! -e $archive_file ) {
  error_rsp("file $archive_file doesn't exist");
} elsif( ! -f $archive_file ) {
  error_rsp("path $archive_file is not a regular file");
} elsif( ! -r $archive_file ) {
  error_rsp("archive file $archive_file is not readable");
}

if(!open(ARCHIVE_FD, $archive_file)) {
  error_rsp("unable to open file $archive_file");
}

my $f_size = (stat($archive_file))[7];
if(!defined($f_size)) {
  error_rsp("unable to stat file");
} elsif($f_size == 0) {
  error_rsp("the file has 0 bytes of size");
}

# prepare the cookie to expire it meanwhile the file is transfered
# this is a corner case:
# if the cookie is not expired for the same file and another cookie is
# created for that file later, the user won't be able to download the file
# until he deletes the browser cookie
$cookie = $cgi->cookie(
  -name     => CGI::Session->name(),
  -value    => $session_obj->id(),
  -path     => $dummy_uri,
  -expires  => 'now',
);

print $cgi->header(-type => 'application/octet-stream',
                   -expires => 'now',
                   -Content_length => $f_size,
                   -cookie => [$cookie],
);

while(read(ARCHIVE_FD, my $buf, 4096)) {
  print $buf;
}

# delete the session after a successful transfer
$session_obj->delete();

END {
  if(fileno(ARCHIVE_FD)) {
    close(ARCHIVE_FD);
  }
}



sub text_rsp {
  my($msg) = @_;

  print $cgi->header( -type => 'text/plain', -expires => 'now' );
  print $msg, "\n";
  exit(0);
}

sub error_rsp {
  my($msg) = @_;

  &text_rsp("Error: $msg");
}
