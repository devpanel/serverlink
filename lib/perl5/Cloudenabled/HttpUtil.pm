package Cloudenabled::HttpUtil;
require Exporter;
our @ISA = ('Exporter');
use strict;
use warnings;
use Cloudenabled::Constants (qw( :DEFAULT %CE_OP_ST_MAP %CE_TASKS_MSG_TYPES ));
use Cloudenabled::Util;
use POSIX (qw( setsid strftime ));
use Digest::SHA (qw( hmac_sha256_hex ));
use LW2;
#use Fcntl (qw( :DEFAULT :flock ));
use CGI::Util (qw( escape ));
# use CGI;

BEGIN {
  eval 'use JSON::XS (qw( decode_json ));';
  if($@) { # not found JSON::XS, try JSON::PP
    eval 'use JSON::PP (qw( decode_json ))';
    if($@) {
      die __PACKAGE__ . " Error: either JSON::XS or JSON::PP are required. None found\n";
    }
  }
}

our $cgi_param_separator = '&';

our @EXPORT = (qw(
  ce_http_request ce_http_request_unauth
  ce_http_request_new

));

our @EXPORT_OK = (qw(
));

our $debug = 0;

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

  my $data    = '';
  my @params  = ();
  my @headers = ();

  foreach my $p (keys %$prms) {
    if(!ref($p) && $p =~ /^__/ && $p !~ /^__header_/) {
      next;
    } elsif(!ref($p) && $p =~ /^__header_(.+)$/) {
      push(@headers, $1);
      next;
    }

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

  foreach my $hdr (@headers) {
    $req->{$hdr} = $prms->{'__header_' . $hdr};
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

sub ce_http_request_new {
  my $prms = shift;

  foreach my $p (qw( __api_url )) {
    if(!exists($prms->{$p})) {
      warn "ce_http_request_new(): error - missing parameter\n";
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

  my $method = defined($prms->{'__method'}) ? lc($prms->{'__method'}) : 'GET';

  my $data    = '';
  my @params  = ();

  foreach my $p (keys %$prms) {
    if(!ref($p) && $p =~ /^__/) {
      next;
    }

    if(ref($prms->{$p}) && ref($prms->{$p}) eq 'ARRAY') {
      my @values = ();
      for(my $i=0; $i <= $#{ $prms->{$p} }; $i++) {
        push(@params, "$p=" . escape($prms->{$p}->[$i]));
      }
    } else {
      push(@params, $p . '=' . escape($prms->{$p}));
    }
  }

  if(exists($prms->{__headers}) && ref($prms->{__headers}) eq 'HASH') {
    foreach my $key (keys %{ $prms->{__headers} }) {
      $req->{$key} = $prms->{__headers}->{$key};
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
    return ce_ret_local_error({}, 'ce_http_request_new(): invalid request method');
  }

  my $auth = exists($prms->{'__key'}) ? 1 : 0;
  if($auth && $method eq 'get') {
    $req->{&CE_HEADER_SIGNATURE_STR} = cloudenabled_sign_data($req->{whisker}->{uri}, $prms->{'__key'});
  } elsif($auth && $method eq 'post' || $method eq 'put') {
    $req->{&CE_HEADER_SIGNATURE_STR} = cloudenabled_sign_data($data, $prms->{'__key'});
  }

  LW2::http_fixup_request($req);

  my $st = LW2::http_do_request($req, $rsp);

  my $ret_r = { http_rsp => $rsp };

  if($st) {
    return ce_ret_local_error($ret_r, $rsp->{whisker}->{error});
  } elsif($rsp->{whisker}->{code} != 200) {
    return ce_ret_local_error($ret_r,
             "server returned http code $rsp->{whisker}->{code}");
  }

  if($auth && !exists($rsp->{&CE_HEADER_SIGNATURE_STR}) && exists($rsp->{&CE_HEADER_STATUS_STR})) {
    return ce_ret_local_error($ret_r, "server error: " . ce_map_op_st_str($rsp->{&CE_HEADER_STATUS_STR}));
  } elsif($auth && !exists($rsp->{&CE_HEADER_SIGNATURE_STR}) && !exists($rsp->{&CE_HEADER_STATUS_STR})) {
    return ce_ret_local_error($ret_r, "server didn't provide a signature nor an error response");
  } 
  
  if($auth && !exists($rsp->{whisker}->{data}) || length($rsp->{whisker}->{data}) == 0) {
    return ce_ret_local_error($ret_r, "server returned an empty response");
  } elsif($auth) {
    my $sig = cloudenabled_sign_data($rsp->{whisker}->{data}, $prms->{'__key'});
    if($rsp->{&CE_HEADER_SIGNATURE_STR} ne $sig) {
      return ce_ret_local_error($ret_r, "server signature doesn't match. " .
        "Expected signature: $sig, received sig: " .
        $rsp->{&CE_HEADER_SIGNATURE_STR} . ", data = $rsp->{whisker}->{data}");
    }
  }

  if($rsp->{'Content-Type'} eq 'application/json') {
    my $json_r = eval { decode_json($rsp->{whisker}->{data}); };
    if($@) {
      return ce_ret_local_error({}, "unable to decode http response data");
    } else {
      foreach my $key (keys %$json_r) {
        $ret_r->{$key} = $json_r->{$key};
      }
    }
  }

  return ce_ret_success($ret_r);
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

1;
