#!/usr/bin/perl
use strict;
use warnings;
use CGI (qw( -private_tempfiles ));
use Digest::SHA (qw( hmac_sha256_hex ));
use File::Basename qw( basename );
use constant TOKEN_MIN_LEN     => 12;
use constant SIG_LEN           => 64;
use constant SIG_REGEX         => qr/^[a-f0-9]+$/;
use constant TOKEN_REGEX       => qr/^[A-Za-z0-9]+$/;
use constant TIMESTAMP_REGEX   => qr/^\d+$/;

my $token_dir = '/opt/webenabled/var/tokens';
my $target_dir = '/opt/webenabled/data/vhost_archives';

our $cgi;

sub simple_reply {
  my($status, $msg, $internal_msg) = @_;

  print $cgi->header('-type' => 'text/plain');
  print $status;
  if(defined($msg)) {
    print ':', $msg;
  }
  print "\n";

  if(defined($internal_msg)) {
    warn $internal_msg, "\n";
  }
}

sub simple_error {
  my($status, $msg, $internal_msg) = @_;

  simple_reply($status, $msg);
  if(defined($internal_msg)) {
    warn $internal_msg, "\n";
  }

  my $slp_n = sprintf('%.3f', rand());
  sleep($slp_n);
  exit(1);
}

sub read_secret {
  my $file = shift;
  my $secret;

  if(!open(TOKEN_F, $file)) {
    warn "read_secret(): unable to open token file: $!\n";
    return 0;
  }

  $secret = <TOKEN_F>;
  close(TOKEN_F);
  chomp($secret);
  return $secret;
}

# main

my $start_time = time();
my $username;
my @user_info;
if(!(@user_info = getpwuid($<))) {
  simple_error(1, "unable to determine current user uid: $!",
                  "unable to determine current user uid: $!");
}

(my $vhost = $user_info[0]) =~ s/^w_//;
my $home_dir = $user_info[7];

my $clone_type;
if(__FILE__ =~ /-send(?:.\w{2,3})?$/) {
  $clone_type = 'send_passive';
} elsif(__FILE__ =~ /-recv(?:.\w{2,3})?$/) {
  $clone_type = 'recv_passive';
} else {
  warn "Error: unable to detect clone type from filename. " . __FILE__ .
   "Please rename the file so it's name ends with -send.cgi or -recv.cgi";
  exit(1);
}

$cgi = CGI->new;
my $content_type = $cgi->content_type();

if($cgi->request_method() ne 'POST') {
  simple_error(1, "request method needs to be post");
} elsif(!$content_type || length($content_type) < 19 ||
          substr($content_type, 0, 19) ne 'multipart/form-data') {
  simple_error(1, "content type needs to be multipart/form-data")
}

my $token = $cgi->param('token');
my $sig  = $cgi->param('sig');
my $pack = $cgi->param('pack');
my $recv_size = $cgi->param('size');
my $validate = $cgi->param('validate');
my $timestamp = $cgi->param('timestamp');

if(!defined($token)) {
  simple_error(1, "missing parameter token", "missing parameter token");
} elsif(length($token) < TOKEN_MIN_LEN) {
  simple_error(1, "invalid token", "invalid token length");
} elsif($token !~ TOKEN_REGEX) {
  simple_error(1, "invalid token", "token doesn't match regex");
}

if(!defined($timestamp)) {
  simple_error(1, "missing parameter timestamp",
                  "missing parameter timestamp");
} elsif(length($timestamp) != 10 && length($timestamp) != 11) {
  simple_error(1, "invalid format of timestamp",
                  "invalid length of timestamp");
} elsif($timestamp !~ TIMESTAMP_REGEX) {
  simple_error(1, "invalid format of timestamp",
                  "timestamp doesn't match regex");
}

if(!defined($sig)) {
  simple_error(1, "missing parameter sig", "missing parameter sig");
} elsif(length($sig) != SIG_LEN) {
  simple_error(1, "invalid signature", "invalid signature length");
} elsif($sig !~ SIG_REGEX) {
  simple_error(1, "invalid signature", "signature doesn't match regex");
}

if($clone_type eq 'recv_passive' && !defined($recv_size)) {
  simple_error(1, "missing receive size parameter", 
                  "missing receive size parameter");
} elsif($clone_type eq 'recv_passive' && $recv_size !~ /^\d+$/) {
  simple_error(1, "receive size must be numeric",
                  "received a non-numeric 'size' parameter");
} elsif($clone_type eq 'recv_passive' && $recv_size == 0) {
  simple_error(1, "trying to send a file of size 0",
                  "trying to send a file of size 0");
}

if($clone_type eq 'recv_passive' && !defined($validate) && 
  !defined($pack)) {
  simple_error(1, "missing parameter pack");
}

my $token_file = sprintf('%s/%s.%s.%s', $token_dir, $vhost, $clone_type, $token);
#my $target_archive = sprintf('%s/public_html/gen/archive/%s.%s.%s.tgz', 
#                                $home_dir, $vhost, $clone_type, $token);
my $target_archive = sprintf('/opt/webenabled-data/vhost_archives/%s/%s.%s.%s.tgz', 
                             $vhost, $vhost, $clone_type, $token);

my $data_to_check = sprintf('token=%s&timestamp=%s', $token, $timestamp);

# seems weird to have this check at this place, but we can't check the
# signature without reading the token file
if(! -e $token_file) {
  simple_error(1, "invalid signature", "token file '$token_file' doesn't exist");
}
my $secret_key;
if(!($secret_key = read_secret($token_file))) {
    simple_error(1, "invalid signature");
}

my $exp_sig = hmac_sha256_hex($data_to_check, $secret_key);
if($sig ne $exp_sig) {
  simple_error(1, "invalid signature",
    "token: $token, signature doesn't match. received $sig, ".
    " was expecting $exp_sig");
}

if($clone_type eq 'recv_passive' && -e $target_archive) {
  simple_error(1, "target archive already exists", 
    "token: $token, type: $clone_type, " .
    "target archive already exists '$target_archive'");
} elsif($clone_type eq 'send_passive' && ! -e $target_archive) {
  simple_error(1, "target archive doesn't exist",
    "token: $token, type: $clone_type, ". 
    "target archive '$target_archive' doesn't exist");
}

if($validate) {
  # actually all validations have already been done, just exit success
  simple_reply(0);
  exit(0);
}

if($clone_type eq 'recv_passive') {
  my $pack_fh   = $cgi->upload('pack');
  if(!$pack_fh && $cgi->cgi_error()) {
    simple_error(1, $cgi->cgi_error(), $cgi->cgi_error());
  }
  my $size = (stat($pack_fh))[7];
  if(!$size) {
    simple_error(1, "unable to determine the file size of the local file: $!",
                  "token: $token, type: $clone_type, " .
                  "unable to determine the file size of the local file: $!");
  }

  binmode($pack_fh);
  if(!open(TARGET_ARCHIVE, ">$target_archive")) {
    simple_error(1,
      "unable to open target archive '$target_archive' for writing: $!",
      "token: $token, type: $clone_type, " .
      "unable to open target archive '$target_archive' for writing: $!"
    );
  }
  while(<$pack_fh>) {
    print TARGET_ARCHIVE $_;
  }
  close(TARGET_ARCHIVE);

  my $time_spent = time() - $start_time;

  simple_reply(0, "ok, clone completed in $time_spent seconds",
                  "token: $token, type: $clone_type, " .
                  "received file '$target_archive' in $time_spent seconds");
} elsif($clone_type eq 'send_passive') {
  if(!open(ARCHIVE, $target_archive)) {
    simple_error(1, "unable to open archive '$target_archive': $!",
                  "token: $token, type: $clone_type, " .
                  "unable to open archive '$target_archive': $!");
  }
  my $basename = basename($target_archive);
  binmode(ARCHIVE);

  print $cgi->header(
    '-type' => 'application/octect-stream',
    'Content-disposition' => "attachment;filename=$basename",
  );

  my $b_trans = 0;
  while(<ARCHIVE>) {
    if(!print $_) {
      warn "token: $token, type: $clone_type, ",
        "unable to print to remote end. ",
        "Transfer interrupted after sending $b_trans bytes", "\n";
      exit(1);
    }
    $b_trans += length($_);
  }
  close(ARCHIVE);

  my $time_spent = time() - $start_time;
  warn "token: $token, type: $clone_type. ",
    "Successfully transfered file '$target_archive', ",
    "transferred $b_trans bytes in $time_spent seconds", "\n";
}
