#!/usr/bin/perl
package Cloudenabled::RPCComm;
use strict;
use warnings;
use IO::Async::Loop;
use IO::Async::Stream;
use JSON::XS;
use IO::Socket::UNIX;
use Cloudenabled::Util;

our $debug = 0;

our $rpc_timeout = 5;

our $max_request_size = 10 * 1024 * 1024;

sub new {
  my ($class, @opts) = @_;
  my $self = {};

  if($#opts % 2 == 0) { # if the last element is even, the number of entered
                        # arguments is odd
    warn "Error: received an odd number of arguments\n";
    return 0;
  }

  # my($db_type, $db_url, $db_user, $db_pass, $db_opts);
  my($connect_address);

  for(my $i=0; $i < $#opts; $i++) {
    my $key = $opts[$i];
    my $val = $opts[++$i];

    if($key eq 'connect_address') {
      $connect_address = $val;
    } elsif($key eq 'rpc_timeout') {
      $rpc_timeout = $val;
    } elsif($key eq 'debug') {
      $debug = $val;
    } elsif($key eq 'max_request_size') {
      $max_request_size = $val;
    }
  }

  if(!connect_socket($self, $connect_address)) {
    warn __PACKAGE__, " - error: unable to connect to address '$connect_address': $!";
    return 0;
  }

  my $obj = bless($self, $class || __PACKAGE__);

  return $obj;
}

sub send {
  my($self, $data, $opts) = @_;

  foreach my $p (qw( _last_read _sent )) {
    delete($self->{$p}) if(exists($self->{$p}));
  }

  my $loop    = $self->{_loop};

  my $timeout = defined($opts) && exists($opts->{timeout}) ? $opts->{timeout} : $rpc_timeout;

  my $sent = 0;
  $self->{_stream}->write($data, on_flush => sub { $sent++; });

  my $timed_out = 0;
  my $timer = $loop->watch_time( after => $timeout , code => sub { $timed_out++; });

  $loop->loop_once() until ($timed_out || $sent && exists($self->{_last_read}));
  $loop->unwatch_time($timer) if(!$timed_out);

  return (exists($self->{_last_read}) ? $self->{_last_read} : undef);
}

sub op {
  my($self, $op, $args, $opts) = @_;

  $args->{op} = $op;

  my $json_enc = eval { encode_json($args); };
  if($@) {
    warn __PACKAGE__, " op() - error: unable to encode json data: $@";
    return 0;
  }

  my $rsp = $self->send($json_enc, (defined($opts) ? $opts : {}));

  return $rsp;
}

sub ping {
  my($self, $data) = @_;

  my $ret = $self->op('ping', {}, { timeout => 1 });
  if(ce_was_successful($ret) && exists($ret->{op}) && $ret->{op} eq 'pong') {
    return 1;
  } else {
    return 0;
  }
}

sub connect_socket {
  my($self, $address) = @_;

  $address = defined($address) ? $address :
              (exists($self->{_connect_address}) ? $self->{_connect_address} : '');

  my $addr;
  if($address =~ /^unix:(.+)$/) {
    $addr = $1;
  } else {
    warn __PACKAGE__, "connect_socket(): unknown address type\n";
    return 0;
  }

  my $previous_socket;
  if(exists($self->{_socket})) {
    $previous_socket = $self->{_socket};
  }

  my $socket = IO::Socket::UNIX->new(
    Type => SOCK_STREAM,
    Peer => $addr
  );

  if(!$socket) {
    return 0;
  }

  $self->{_connect_address} = $address;
  $self->{_socket} = $socket;

  if(exists($self->{_loop})) {
    defined($previous_socket) and $self->{_loop}->remove($previous_socket);
    $self->{_loop}->add($socket);
  } else {
    add_async_functions($self, $socket);
  }

  return $socket;
}

sub add_async_functions {
  my($self, $socket) = @_;

  my $json_obj = JSON::XS->new();

  my $stream = IO::Async::Stream->new(
    autoflush => 1,
    handle  => $socket,
    on_read => sub {
      my($sock, $buffref, $eof) = @_;

      my $partial_len += length($$buffref);

      if($partial_len > $max_request_size) {
        warn __PACKAGE__, " - Exceeded max buffer size\n";
        goto CLEAR_READ_BUFFER;
      }

      my $req;
      eval { $req = $json_obj->incr_parse($$buffref); };

      if($@) {
        warn __PACKAGE__, " - Error parsing request: $@";
        goto CLEAR_READ_BUFFER;
      } elsif(!defined($req)) {
        warn __PACKAGE__, " - request in multiple buffers. read $partial_len until now";
        $$buffref = "";
        return 0;               # wait next buffer
      } else { # has returned JSON references
        warn __PACKAGE__, ": got one JSON structure\n";
        $self->{_last_read} = $req;
      }


CLEAR_READ_BUFFER:
      $$buffref     = "";
      $partial_len  =  0;
      $json_obj->incr_reset();
    }, # // on_read

    on_read_error => sub {
      my($self, $errno) = @_;
      print "Error - $errno\n";
    },

    on_read_eof => sub {
      my($s) = @_;
      print "read EOF\n";
    },

    on_write_error => sub {
      my($self, $errmsg) = @_;
      warn __PACKAGE__, " socket write error: $errmsg\n";
    },
  );

  $self->{_stream} = $stream;

  my $loop = IO::Async::Loop->new();

  $loop->add($stream);
  $self->{_loop} = $loop;

  return 1;
}

1;
