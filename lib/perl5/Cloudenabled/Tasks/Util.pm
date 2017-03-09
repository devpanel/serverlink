package Cloudenabled::Tasks::Util;
require Exporter;
our @ISA = ('Exporter');
use strict;
use warnings;
use Cloudenabled::Constants (qw( :DEFAULT %CE_OP_ST_MAP ));
use Cloudenabled::Util;
use URI::Escape;
use Data::Dumper;

BEGIN {
  # try HTTP::Tiny as the main module for HTTP connections
  eval "use HTTP::Tiny;";
  if($@) {
    eval "use LW2;";
    if($@) {
      die "Error: couldn't find an HTTP module for HTTP connections.\n";
    }
  }
}

our $debug = 0;
our $cgi_param_separator = '&';

our @EXPORT = (qw(
  ce_task_ret_success ce_task_ret_internal_error ce_task_ret_format_error
  ce_task_ret_invalid_value ce_task_ret_missing_required
  ce_task_ret_nothing_updated ce_task_ret_permission_denied
  ce_task_ret_signature_error ce_task_ret_not_found
  ce_task_was_successful ce_tasks_http_request
  ce_querystring_2_hashref
));

sub ce_task_ret_success {
  my($r) = @_;

  $r = {} if(!defined($r));
  $r->{_s} = CE_OP_ST_SUCCESS;

  return $r;
}

sub ce_task_ret_internal_error {
  my($r, $errmsg) = @_;

  $r->{_s} = CE_OP_ST_INTERNAL_ERROR;
  if(defined($errmsg)) {
    $r->{_e} = $errmsg;
  }

  return $r;
}

sub ce_task_ret_format_error {
  my($r, $p, $msg) = @_;

  $r->{_s} = CE_OP_ST_PARAMETER_FORMAT_ERROR;
  $r->{_e} = defined($msg) ? $msg : "Invalid syntax of parameter $p";

  return $r;
}

sub ce_task_ret_invalid_value {
  my($r, $p, $msg) = @_;

  $r->{_s} = CE_OP_ST_PARAMETER_INVALID_VALUE;
  $r->{_e} = defined($msg) ? $msg : "Invalid value for parameter $p";

  return $r;
}

sub ce_task_ret_missing_required {
  my($r, $p, $msg) = @_;

  $r->{_s} = CE_OP_ST_MISSING_PARAMETERS;
  $r->{_e} = defined($msg) ? $msg : "Missing parameter $p";

  return $r;
}

sub ce_task_ret_nothing_updated {
  my($r, $p) = @_;
  $r->{_s} = CE_OP_ST_NOTHING_UPDATED;
  if(defined($p)) {
    $r->{_e} = $p;
  }
}

sub ce_task_ret_permission_denied {
  my($r, $p) = @_;
  $r->{_s} = CE_OP_ST_PERMISSION_DENIED;

  if(defined($p)) {
    $r->{_e} = $p;
  }
}

sub ce_task_ret_signature_error {
  my($r, $msg) = @_;

  $r = {} if(!defined($r));
  $r->{_s} = CE_OP_ST_SIGNATURE_ERROR;

  if(defined($msg)) {
    $r->{_e} = $msg;
  }

  return $r;
}

sub ce_task_ret_not_found {
  my($r,$msg) = @_;

  $r = {} if(!defined($r));

  $r->{_s} = CE_OP_ST_NOT_FOUND;

  if(defined($msg)) {
    $r->{_e} = $msg;
  }

  return $r;
}

sub ce_task_was_successful {
  my($r) = @_;

  if(!defined($r) || !ref($r) || ref($r) ne 'HASH') {
    return 0;
  }

  if(exists($r->{_s}) && defined($r->{_s}) && $r->{_s} =~ /^\d+$/ && $r->{_s} == CE_OP_ST_SUCCESS) {
    return 1;
  } else {
    return 0;
  }
}

sub ce_tasks_http_request {
  if(defined($INC{'HTTP/Tiny.pm'})) {
    return ce_tasks_http_request_http_tiny(@_);
  } elsif(defined($INC{'LW2.pm'})) {
    return ce_tasks_http_request_lw2(@_);
  } else {
    my $errmsg = "didn\'t find any http library loaded";
    return ce_ret_local_error({}, $errmsg);
  }
}

sub ce_tasks_http_request_http_tiny {
  my $prms = shift;

  foreach my $p (qw( __api_url __key )) {
    if(!exists($prms->{$p})) {
      ce_log(\*STDERR, "ce_tasks_http_request(): error - missing parameter $p");
      return ce_ret_local_error({}, "missing parameter $p");
    }
  }

  my $method = defined($prms->{'__method'}) ? uc($prms->{'__method'}) : 'GET';
  my $url    = $prms->{__api_url};
  my $data   = '';
  my @params = ();

  foreach my $p (keys %$prms) {
    next if(!ref($p) && $p =~ /^__/);

    if(ref($prms->{$p}) && ref($prms->{$p}) eq 'ARRAY') {
      my @values = ();
      for(my $i=0; $i <= $#{ $prms->{$p} }; $i++) {
        push(@params, "$p=" . uri_escape($prms->{$p}->[$i]));
      }
    } else {
      push(@params, $p . '=' . uri_escape($prms->{$p}));
    }
  }

  if($#params >= 0) {
    $data = join($cgi_param_separator, @params);
  }

  my $req_headers = {};
  my $req_obj = {
    headers => $req_headers,
  };

  if($method eq 'GET') {
    $url .= '?'. $data;

    # uri: remove the proto:host part
    (my $uri = $url) =~ s/^([a-z0-9A-Z]+:\/\/)?([^\/]+\/)?/\//;
    $req_headers->{&CE_HEADER_SIGNATURE_STR} = cloudenabled_sign_data($uri,
                                                        $prms->{'__key'});
  } elsif($method eq 'POST' || $method eq 'PUT') {
    $req_obj->{content} = $data;
    $req_headers->{'content-type'} = 'application/x-www-form-urlencoded';
    $req_headers->{&CE_HEADER_SIGNATURE_STR} = cloudenabled_sign_data($data,
                                                  $prms->{'__key'});
  } else {
    ce_log(\*STDERR, "http_request(): invalid request method");
    return ce_ret_local_error({}, 'http_request(): invalid request method');
  }

  $debug and ce_log(\*STDERR, "Sending request " . Dumper($req_obj));

  my $http_obj = HTTP::Tiny->new(
                    timeout => 30,
  );

  my $rsp = $http_obj->request($method, $url, $req_obj);

  $debug and ce_log(\*STDERR, "http_request(): received response " .  Dumper($rsp));

  if(!$rsp->{success}) {
    my $rsp_txt = defined($rsp->{content}) && length($rsp->{content}) ? 
                  $rsp->{content} : '(empty response)';
    ce_log(\*STDERR, "http_request(): error - $rsp_txt");
    return ce_ret_local_error({}, $rsp_txt);
  } elsif($rsp->{status} != 200) {
    return ce_ret_local_error({}, "http_request(): server returned http code $rsp->{status}");
  }

  my $rsp_headers_r     = $rsp->{headers};
  my $status_hdr = lc(&CE_HEADER_STATUS_STR);
  my $sig_hdr    = lc(&CE_HEADER_SIGNATURE_STR);

  my $alt_status_header = defined($rsp_headers_r->{$status_hdr}) &&
                          length($rsp_headers_r->{$status_hdr})   ?
                          $rsp_headers_r->{$status_hdr} : '';

  my $sig_recvd = defined($rsp_headers_r->{$sig_hdr}) && 
                  length($rsp_headers_r->{$sig_hdr})   ? 
                  $rsp_headers_r->{$sig_hdr} : '';

  my $content_recvd = defined($rsp->{content}) && length($rsp->{content}) ?
                      $rsp->{content} : '';

  if(!$sig_recvd && !$alt_status_header) {
    return ce_ret_local_error({}, "server didn't provide a valid signature (nor alt status header)");
  } elsif(!$sig_recvd && $alt_status_header) {
    return ce_ret_local_error({}, "http_request(): returned status: " .
                                  ce_map_op_st_str($alt_status_header));
  } elsif(!$content_recvd) {
    return ce_ret_local_error({}, "Error: server returned an empty response");
  } else {
    my $sig_expected = cloudenabled_sign_data($content_recvd, $prms->{'__key'});
    if($sig_recvd ne $sig_expected) {
      ce_log(\*STDERR, "http_request(): Error: server signature doesn't match." .
                       " Expected signature: $sig_expected");
      $debug and ce_log(\*STDERR, sprintf("http_request(): sig = %s, data = %s",
                      $sig_recvd, $content_recvd));
      return ce_ret_local_error({}, "server signature doesn't match");
    }
  }

  my $r_data = ce_querystring_2_hashref($rsp->{content});

  return $r_data;
}

sub ce_tasks_http_request_lw2 {
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

  if($req->{whisker}->{ssl} > 0) {
    $req->{whisker}->{ssl_save_info} = 1;
    $req->{whisker}->{ssl_resume}    = 1;
  }

  my $method = defined($prms->{'__method'}) ? lc($prms->{'__method'}) : 'get';

  my $data   = '';
  my @params = ();

  foreach my $p (keys %$prms) {
    next if(!ref($p) && $p =~ /^__/);

    if(ref($prms->{$p}) && ref($prms->{$p}) eq 'ARRAY') {
      my @values = ();
      for(my $i=0; $i <= $#{ $prms->{$p} }; $i++) {
        push(@params, "$p=" . uri_escape($prms->{$p}->[$i]));
      }
    } else {
      push(@params, $p . '=' . uri_escape($prms->{$p}));
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
  } elsif(!exists($rsp->{&CE_HEADER_SIGNATURE_STR}) && exists($rsp->{&CE_HEADER_STATUS_STR})) {
    return ce_ret_local_error({}, "http_request(): returned status: " .  
                                      ce_map_op_st_str($rsp->{&CE_HEADER_STATUS_STR}));
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

  my $r_data = ce_querystring_2_hashref($rsp->{whisker}->{data});

  return $r_data;
}


sub ce_querystring_2_hashref {
  my($query_string, $overwrite) = (@_);

  my $hash_ref = {};

  $overwrite = defined($overwrite) ? $overwrite : 0;

  my @key_values = split($cgi_param_separator, $query_string);

  foreach my $pair (@key_values) {
    my($key, $value_raw) = split('=', $pair);
    my $value;
    if(defined($value_raw) && length($value_raw)) {
      $value = uri_unescape($value_raw);
    }

    if($overwrite || !exists($hash_ref->{$key})) {
      $hash_ref->{$key} = $value;
      next;
    }

    if(exists($hash_ref->{$key})) {
      if(ref($hash_ref->{$key}) eq "ARRAY") {
        push(@{ $hash_ref->{$key} }, $value);
      } else {
        my $curr_value = $hash_ref->{$key};
        $hash_ref->{$key} = [ $curr_value, $value ];
      }
    }
  }

  return $hash_ref;
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
