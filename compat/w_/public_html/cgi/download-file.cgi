#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename (qw( basename ));
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

my $app = "download-file";

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
  error_rsp("session expired. Please request a new token.");
}

# from now it's an authenticated request...

# a few more sanity checks on the session
if($session_obj->param('devpanel_app') ne $app) {
  error_rsp("got a valid cookie, though it's the wrong app");
}

if(!defined($session_obj->param('file'))) {
  error_rsp("missing parameter file on the session");
}

my $file_str = $session_obj->param('file');
my $file_path;
if(substr($file_str, 0, 1) ne "/") {
  $file_path = abs_path($ENV{HOME} . "/$file_str");
} else {
  $file_path = $file_str;
}

if( ! -e $file_path ) {
  error_rsp("file $file_path doesn't exist");
} elsif( ! -f $file_path && ! -p $file_path ) {
  error_rsp("path $file_path is not a regular file nor a named pipe");
} elsif( ! -r $file_path ) {
  error_rsp("archive file $file_path is not readable");
}

my $f_size = (stat($file_path))[7];
if(!defined($f_size)) {
  error_rsp("unable to stat file '$file_path': $!");
} elsif(-f $file_path && $f_size == 0) {
  error_rsp("the file has 0 bytes of size");
}

if(!open(ARCHIVE_FD, $file_path)) {
  error_rsp("unable to open file $file_path");
}

my %headers = (
  -type       => 'application/octet-stream',
  -expires    => 'now',
  -attachment => basename($file_path),
  -charset    => 'utf-8', # just assume utf-8 for special characters
);

if(-f $file_path) {
  # if it's a regular file, then add the Content-Length header
  # (not doing it for named pipes, that have size == 0)
  $headers{'-Content_length'} = $f_size;
}

print $cgi->header(%headers);

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
