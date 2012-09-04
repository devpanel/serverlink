package Cloudenabled::Controller::Util;
require Exporter;
our @ISA = ('Exporter');
use strict;
use warnings;
use Cloudenabled::Util;
use JSON::XS;
use CGI::Util (qw( escape ));
use Cloudenabled::Constants (qw( :DEFAULT %CE_OP_ST_MAP ));
#use POSIX (qw( setsid strftime ));
#use Digest::SHA (qw( hmac_sha256_hex ));
use LW2;

our @EXPORT = (qw(
  ce_http_request ce_http_request_unauth
  translate_cmd_args translate_cmd_envs
  ce_task_compact_data
));

our @EXPORT_OK = (qw(
));

our $debug = 0;
our $cgi_param_separator = '&';

sub ce_http_request {
  my $prms = shift;

  foreach my $p (qw( __api_url __key )) {
    if(!exists($prms->{$p})) {
      ce_log(\*STDERR, "ce_tasks_http_request(): error - missing parameter $p");
      return ce_ret_local_error({}, "missing parameter $p");
    }
  }

  my $req = LW2::http_new_request();
  my $rsp = LW2::http_new_response();

  LW2::uri_split($prms->{'__api_url'}, $req);

  if($ENV{'http_proxy'}) {
    my($p_host, $p_port);
    ($p_host = $ENV{'http_proxy'}) =~ s/^http:\/\///;
    ($p_port = $p_host) =~ s/^.+://;
    $p_host =~ s/:\d+\/?$//;
    $p_port =~ s|/$||;

    $req->{whisker}->{proxy_host} = $p_host;
    $req->{whisker}->{proxy_port} = $p_port;
  }

  my $method = defined($prms->{'__method'}) ? lc($prms->{'__method'}) : 'get';

  my $data   = '';
  my @params = ();

  foreach my $p (keys %$prms) {
    next if(!ref($p) && $p =~ /^__/);

    if(ref($prms->{$p}) && ref($prms->{$p}) eq 'ARRAY') {
      my @values = ();
      for(my $i=0; $i <= $#{ $prms->{$p} }; $i++) {
        push(@params, "$p=" . escape($prms->{$p}->[$i]));
      }
    } else {
      push(@params, $p . '=' . escape($prms->{$p}));
    }
  }

  if($#params >= 0) {
    $data = join($cgi_param_separator, @params);
  }

  if($method eq 'get') {
    $req->{whisker}->{uri} .= '?'. $data;
    $req->{&CE_HEADER_SIGNATURE_STR} = cloudenabled_sign_data($req->{whisker}->{uri}, $prms->{'__key'});
  } elsif($method eq 'post' || $method eq 'put') {
    $req->{'whisker'}->{'method'} = uc($method);
    $req->{whisker}->{data} = $data;
    $req->{&CE_HEADER_SIGNATURE_STR} = cloudenabled_sign_data($data, $prms->{'__key'});
  } else {
    ce_log(\*STDERR, "http_request(): invalid request method");
    return ce_ret_local_error({}, 'http_request(): invalid request method');
  }

  LW2::http_fixup_request($req);

  $debug and ce_log(\*STDERR, "Sending request " . Dumper($req));

  my $st = LW2::http_do_request($req, $rsp);
  $debug and ce_log(\*STDERR, "http_request(): received response " .  Dumper($rsp));

  if($st) {
    ce_log(\*STDERR, "http_request(): error - $rsp->{whisker}->{error}");
    return ce_ret_local_error({}, $rsp->{whisker}->{error});
  } elsif($rsp->{whisker}->{code} != 200) {
    return ce_ret_local_error({}, "http_request(): server returned http code $rsp->{whisker}->{code}");
  }

  if(!exists($rsp->{&CE_HEADER_SIGNATURE_STR}) &&
    !exists($rsp->{&CE_HEADER_STATUS_STR})) {
    return ce_ret_local_error({}, "server didn't provide a valid signature");
  } elsif(!exists($rsp->{whisker}->{data}) || length($rsp->{whisker}->{data}) == 0) {
    return ce_ret_local_error({}, "Error: server returned an empty response");
  } else {
    my $sig = cloudenabled_sign_data($rsp->{whisker}->{data}, $prms->{'__key'});
    if($rsp->{&CE_HEADER_SIGNATURE_STR} ne $sig) {
      ce_log(\*STDERR, "http_request(): Error: server signature doesn't match.  Expected signature: $sig");
      $debug and ce_log(\*STDERR, sprintf("http_request(): sig = %s, data = %s",
                      $rsp->{&CE_HEADER_SIGNATURE_STR}, $rsp->{whisker}->{data}));
      return ce_ret_local_error({}, "server signature doesn't match");
    }
  }

  my $rsp_r = eval { decode_json($rsp->{whisker}->{data}); };
  if($@) {
    return ce_ret_local_error({}, "unable to decode http response data");
  } else {
    return $rsp_r;
  }
    
}

sub ce_http_request_unauth {
  my $prms = shift;

  foreach my $p (qw( __api_url )) {
    if(!exists($prms->{$p})) {
      ce_log(\*STDERR, "ce_tasks_http_request(): error - missing parameter $p");
      return ce_ret_local_error({}, "missing parameter $p");
    }
  }

  my $req = LW2::http_new_request();
  my $rsp = LW2::http_new_response();

  LW2::uri_split($prms->{'__api_url'}, $req);

  if($ENV{'http_proxy'}) {
    my($p_host, $p_port);
    ($p_host = $ENV{'http_proxy'}) =~ s/^http:\/\///;
    ($p_port = $p_host) =~ s/^.+://;
    $p_host =~ s/:\d+\/?$//;
    $p_port =~ s|/$||;

    $req->{whisker}->{proxy_host} = $p_host;
    $req->{whisker}->{proxy_port} = $p_port;
  }

  my $method = defined($prms->{'__method'}) ? lc($prms->{'__method'}) : 'get';

  my $data   = '';
  my @params = ();

  foreach my $p (keys %$prms) {
    next if(!ref($p) && $p =~ /^__/);

    if(ref($prms->{$p}) && ref($prms->{$p}) eq 'ARRAY') {
      my @values = ();
      for(my $i=0; $i <= $#{ $prms->{$p} }; $i++) {
        push(@params, "$p=" . escape($prms->{$p}->[$i]));
      }
    } else {
      push(@params, $p . '=' . escape($prms->{$p}));
    }
  }

  if($#params >= 0) {
    $data = join($cgi_param_separator, @params);
  }

  if($method eq 'get') {
    $req->{whisker}->{uri} .= '?'. $data;
  } elsif($method eq 'post' || $method eq 'put') {
    $req->{'whisker'}->{'method'} = uc($method);
    $req->{whisker}->{data} = $data;
  } else {
    ce_log(\*STDERR, "http_request(): invalid request method");
    return ce_ret_local_error({}, 'http_request(): invalid request method');
  }

  LW2::http_fixup_request($req);

  $debug and ce_log(\*STDERR, "Sending request " . Dumper($req));

  my $st = LW2::http_do_request($req, $rsp);
  $debug and ce_log(\*STDERR, "http_request(): received response " .  Dumper($rsp));

  if($st) {
    ce_log(\*STDERR, "http_request(): error - $rsp->{whisker}->{error}");
    return ce_ret_local_error({}, $rsp->{whisker}->{error});
  } elsif($rsp->{whisker}->{code} != 200) {
    return ce_ret_local_error({}, "http_request(): server returned http code $rsp->{whisker}->{code}");
  }

  if(!exists($rsp->{whisker}->{data}) || length($rsp->{whisker}->{data}) == 0) {
    return ce_ret_local_error({}, "Error: server returned an empty response");
  }

  my $rsp_r = eval { decode_json($rsp->{whisker}->{data}); };
  if($@) {
    return ce_ret_local_error({}, "unable to decode http response data");
  } else {
    return $rsp_r;
  }
    
}

sub ce_task_compact_data {
  my($tasks_ar, $cmd_defs) = @_;

  my @regular_opts = (qw( flags last_attempt_id activity_id ));

  my $transl_r = {};
  $transl_r->{n} = $#{ $tasks_ar } + 1;

  for(my $i=1; $i-1 <= $#{ $tasks_ar }; $i++) {
    my $task_def = $tasks_ar->[$i-1];
    $transl_r->{"t$i"} = $task_def->{id};
    foreach my $p (@regular_opts) {
      $transl_r->{"t$i"} .= ',' . $task_def->{$p};
    }

    my $cmd_args  = [];
    my $task_data = {};

    if(length($task_def->{input_data}) > 0) {
      my $ref = eval { decode_json($task_def->{input_data}); };
      if($@) {
        warn "ce_task_compact_data(): error - unable to decode data for ",
              "task ", $task_def->{id}, " ", $@, "\n";
        return 0;
      }
      $task_data = $ref;
    }

    my $cmd_id    = $task_def->{command_id};
    my $cmd_data  = $cmd_defs->{$cmd_id};

    push(@$cmd_args, $cmd_data->{cmd_path});

    if(exists($task_data->{cmd_opts})) {
      push(@$cmd_args, @{ $task_data->{cmd_opts} });
    }

    if(defined($cmd_data->{cmd_args}) &&
        length($cmd_data->{cmd_args}) > 0) {
      my $args_ar = translate_cmd_args($cmd_data->{cmd_args}, $task_data);
      push(@$cmd_args, @$args_ar);
    }

    if(defined($cmd_defs->{$cmd_id}->{cmd_env}) &&
          length($cmd_defs->{$cmd_id}->{cmd_env}) > 0) {
      my $cmd_envs = translate_cmd_envs($cmd_data->{cmd_env}, $task_data);
      my $j=1;
      foreach my $key (keys %$cmd_envs) {
        $transl_r->{"t${i}e${j}n"} = $key;
        $transl_r->{"t${i}e${j}v"} = $cmd_envs->{$key};
        $j++;
      }
    }

    $transl_r->{"c${i}"} = $cmd_args;

    my $flags = $task_def->{flags};
    if($flags & CE_TASK_FL_DROP_PRIVS && exists($task_data->{exec_user})) {
      $transl_r->{"u${i}"} = $task_data->{exec_user};
    }

    if($flags & CE_TASK_FL_DROP_PRIVS && exists($task_data->{exec_group})) {
      $transl_r->{"g${i}"} = $task_data->{exec_group};
    }

    if($flags & CE_TASK_FL_READ_STDIN && exists($task_data->{stdin_data})) {
      $transl_r->{"s${i}"} = $task_data->{stdin_data};
    }

  } # for(i) // tasks_ar

  return $transl_r;
}

sub translate_cmd_args {
  my($args_str, $task_r) = @_;

  $args_str =~ s/\s+/ /g;
  my @def_args = (split(/ /, $args_str));

  my @translated_args = ();

  for(my $i=0; $i <= $#def_args; $i++) {
    my $arg = $def_args[$i];
    if($arg =~ /^%(.+)%$/ && exists($task_r->{$1})) {
      push(@translated_args, $task_r->{$1});
    } else {
      push(@translated_args, $arg);
    }
  }

  return \@translated_args;
}

sub translate_cmd_envs {
  my($env_str, $task_r) = @_;
  my $envs = {};

  my @def_envs = (split(/ /, $env_str));
  for(my $i=0; $i <= $#def_envs; $i++) {
    my($var, $value);
    my $e = $def_envs[$i];
    if($e =~ /^([\w_]+)=(.+)$/) {
      ($var, $value) = ($1, $2);

      if($value =~ /^%(.+)%$/ && exists($task_r->{$1})) {
        $envs->{$var} = $task_r->{$1};
      } else {
        $envs->{$var} = $value;
      }
    }
  }

  return $envs;
}

1;
