package Cloudenabled::Util;
require Exporter;
our @ISA = ('Exporter');
use strict;
use warnings;
use Cloudenabled::Constants (qw( :DEFAULT %CE_OP_ST_MAP %CE_TASKS_MSG_TYPES ));
use POSIX (qw( setsid strftime ));
use Digest::SHA (qw( hmac_sha256_hex ));
use LW2;
use Fcntl (qw( :DEFAULT :flock ));
use CGI::Util (qw( escape ));
use CGI;
#use JSON::XS;

our $cgi_param_separator = '&';

our @EXPORT = (qw(
  cloudenabled_parse_conf cloudenabled_daemonize cloudenabled_sign_data
  ce_ret_success ce_ret_internal_error ce_ret_format_error ce_gen_random_str
  ce_ret_invalid_value ce_ret_missing_required ce_ret_nothing_updated
  ce_ret_permission_denied ce_was_successful ce_ret_signature_error
  ce_ret_not_found ce_ret_local_error ce_log ce_map_op_st_str
  ce_convert_task_ret ce_extract_cmd_params
  ce_map_task_msg_str ce_set_autoflush_noblock
  ce_in_array ce_drop_privs ce_get_user_gids
  ce_is_hash_key_empty
  ce_drop_uid ce_drop_gid
  ce_ret_unknown_operation
  ce_has_flag
  ce_set_flag
  ce_clear_flag
  ce_toggle_flag
));

our @EXPORT_OK = (qw(
  ce_tasks_http_request ce_task_cgi_2_ref
));

our $debug = 0;

sub cloudenabled_parse_conf {
  my $file = $_[0];
  my $conf;
    
  if($#_ == 0) {
    $conf = {};
  } else {
    $conf = $_[1];
  } 
    
  if(!open(F, $file)) {
    warn "Unable to open config file '$file': $!";
    return 0;
  } 
    
  my $n = 0;
  while(<F>) {
    $n++;
    chomp();
    next if length($_) == 0;
    $_ =~ s/^[\s\t]+//; # remove leading spaces         
    next if length($_) == 0;
    next if /^[\s\t]*#/;
    
    if($_ =~ /^.+=.+/) {
      my($param, $value) = split(/=/, $_, 2);
      $param =~ s/[\s\t]+$//; # remove trailing spaces                
      $value =~ s/^[\s\t]+//; # remove leading spaces                 
      $value =~ s/[\s\t]+$//; # remove trailing spaces
      if(length($param) == 0 || length($value) == 0) {
        warn "Warning: skipping invalid line $n in config file\n";
        next;
      }

      $conf->{$param} = $value;
    } else {
      warn "Warning: skipping invalid line $n in config file\n";
      next;
    }
  } 
  close(F);

  return $conf;
}

sub cloudenabled_daemonize {
  my $pid = fork();
  my($log_file) = @_;

  if(!defined($pid)) {
    warn "Error: unable to fork. $!\n";
    exit(1);
  } elsif($pid) {
    exit(0); # parent, just exit
  }

  # child process
  if(!setsid()) {
    warn "Error: unable to set new process session. $!\n";
    exit(1);
  }

  $log_file = defined($log_file) ? $log_file : '/dev/null';

  chdir('/');

  open(STDIN, '/dev/null') or die "Error: can't redirect stdin to /dev/null.  $!\n";
  open(STDOUT, ">>$log_file") or
    die sprintf("Error: can't redirect stdout to %s: %s\n", $log_file, $!);

  open(STDERR, '>&STDOUT') or die "Error: can't dup stderr to stdout. $!\n";

  # enable autoflush
  my $dist_fh = select(STDOUT);
  $| = 1;

  select(STDERR);
  $| = 1;

  select($dist_fh);
}

sub cloudenabled_sign_data {
  my($data, $key) = @_;

  my $sig = hmac_sha256_hex($data, $key);

  if($sig) {
    return $sig;
  } else {
    return 0;
  }
}

sub ce_gen_random_str {
  my $n = shift || 40;
  open(URANDOM, '/dev/urandom') or return undef;

  my $char;
  my $rand = '';


  # 0-9: 48-57
  # A-Z: 65-90
  # a-z: 97-122

  while(length($rand) < $n) {
    read(URANDOM, $char, 1);
    if((ord($char) >= 48 && ord($char) <= 57) ||
      (ord($char) >= 65 && ord($char) <= 90)  ||
      (ord($char) >= 97 && ord($char) <= 122)) {
      $rand .= $char;
    }
  }

  close(URANDOM);
  return $rand;
}

sub ce_log {
  my($fd, $msg) = @_;

  my $len = defined($msg) ? length($msg) : 0;
  if($len == 0) {
    $msg = " ";
    $len = 1;
  }

  printf $fd "[%s]: %s", strftime("%b %2d %H:%M:%S", localtime(time())), $msg;
  if(substr($msg, $len-1) ne "\n") {
    print "\n";
  }
}

sub ce_ret_success {
  my($r) = @_;

  $r = {} if(!defined($r));
  $r->{status} = CE_OP_ST_SUCCESS;

  return $r;
}

sub ce_ret_internal_error {
  my($r, $errmsg) = @_;

  $r->{status} = CE_OP_ST_INTERNAL_ERROR;
  if(defined($errmsg)) {
    $r->{errmsg} = $errmsg;
  }

  return $r;
}

sub ce_ret_format_error {
  my($r, $p, $msg) = @_;

  $r->{status} = CE_OP_ST_PARAMETER_FORMAT_ERROR;
  $r->{errmsg} = defined($msg) ? $msg : "Invalid syntax of parameter $p";

  return $r;
}

sub ce_ret_invalid_value {
  my($r, $p, $msg) = @_;

  $r->{status} = CE_OP_ST_PARAMETER_INVALID_VALUE;
  $r->{errmsg} = defined($msg) ? $msg : "Invalid value for parameter $p";

  return $r;
}

sub ce_ret_missing_required {
  my($r, $p, $msg) = @_;

  $r->{status} = CE_OP_ST_MISSING_PARAMETERS;
  $r->{errmsg} = defined($msg) ? $msg : "Missing parameter $p";

  return $r;
}

sub ce_ret_nothing_updated {
  my($r, $p) = @_;
  $r->{status} = CE_OP_ST_NOTHING_UPDATED;
  if(defined($p)) {
    $r->{errmsg} = $p;
  }

  return $r;
}

sub ce_ret_permission_denied {
  my($r, $p) = @_;
  $r->{status} = CE_OP_ST_PERMISSION_DENIED;

  if(defined($p)) {
    $r->{errmsg} = $p;
  }

  return $r;
}

sub ce_ret_signature_error {
  my($r, $msg) = @_;

  $r = {} if(!defined($r));
  $r->{status} = CE_OP_ST_SIGNATURE_ERROR;

  if(defined($msg)) {
    $r->{errmsg} = $msg;
  }

  return $r;
}

sub ce_ret_not_found {
  my($r,$msg) = @_;

  $r = {} if(!defined($r));

  $r->{status} = CE_OP_ST_NOT_FOUND;

  if(defined($msg)) {
    $r->{errmsg} = $msg;
  }

  return $r;
}

sub ce_ret_local_error {
  my($r,$msg) = @_;

  $r = {} if(!defined($r));

  $r->{status} = CE_OP_ST_LOCAL_ERROR;

  if(defined($msg)) {
    $r->{errmsg} = $msg;
  }

  return $r;
}

sub ce_ret_unknown_operation {
  my($r,$msg) = @_;

  $r = {} if(!defined($r));

  $r->{status} = CE_OP_ST_UNKNOWN_OPERATION;

  if(defined($msg)) {
    $r->{errmsg} = $msg;
  }

  return $r;
}

sub ce_was_successful {
  my $r = shift;

  if(exists($r->{status}) && $r->{status} == CE_OP_ST_SUCCESS) {
    return 1;
  } else {
    return 0;
  }
}

sub ce_map_op_st_str {
  my($st) = @_;
  if(!defined($st)) {
    $st = -1;
  }

  return exists($CE_OP_ST_MAP{$st}) ? $CE_OP_ST_MAP{$st} : '(unknown)';
}

sub ce_map_task_msg_str {
  my($st) = @_;

  return exists($CE_TASKS_MSG_TYPES{$st}) ? $CE_TASKS_MSG_TYPES{$st} : '(unknown)';
}


sub ce_convert_task_ret {
  my($r) = @_;

  my %map = (
    _s => 'status',
    _e => 'errmsg',
    _t => 'timestamp',
  );

  foreach my $k (keys %map) {
    if(exists($r->{$k})) {
      $r->{$map{$k}} = $r->{$k};
      delete($r->{$k});
    }
  }
}

sub ce_extract_cmd_params {
  my $str = shift;

  my @params = ();

  foreach my $v (split(/ /, $str)) {
    if($v =~ /%([\w_]+)%/) {
      push(@params, $1);
    }
  }

  return \@params;
}

sub ce_set_autoflush_noblock {
  my $fd = shift;

  my $prev_fd = select();
  select($fd);
  fcntl($fd, F_SETFL, O_NONBLOCK);
  $| = 1;

  select($prev_fd);
}

sub ce_tasks_http_request {
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

  my $cgi = CGI->new($rsp->{whisker}->{data});
  if(!$cgi) {
    ce_log(\*STDERR, "Error: unable to create CGI object. $!");
    return ce_ret_local_error({}, "unable to create CGI object");
  }

  my $r_data = ce_task_cgi_2_ref($cgi);
  undef($cgi);

  return $r_data;
}

sub ce_task_cgi_2_ref {
  my($cgi) = @_;

  my $r = {};
  foreach my $p (qw( s t w e M S )) {
    my $v = '_' . $p;
    if(defined($cgi->param($v))) {
      $r->{$v} = $cgi->param($v);
      $cgi->delete($v);
    }
  }

  foreach my $p ($cgi->param) {
    my @values = $cgi->param($p);
    if($#values > 0) {
      $r->{$p} = \@values;
    } else {
      $r->{$p} = $cgi->param($p);
    }
  }

  return $r;
}

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

sub ce_in_array {
  my($entry, @array) = @_;

  return scalar(grep { $_ eq $entry } @array);
}

sub ce_drop_privs {
  my($uid, $gid) = @_;

  my @u_entry = getpwuid($uid);
  if($? != 0) {
    warn "Error: unable to get information about uid $uid: $!\n";
    return 0;
  }

  my @g_entry = getgrgid($gid);
  if($? != 0) {
    warn "Error: unable to get information about gid $gid: $!\n";
    return 0;
  }

  $( = $) = $gid;  # setgid(); equivalent
  if($!) {
    warn "Error: unable to setgid() to target_group '$gid': $!";
    return 0;
  }

  $< = $> = $uid;  # setuid(); equivalent
  if($!) {
    warn "Error: unable to setuid() to target_user '$uid': $! \n";
    return 0;
  }

  $ENV{HOME} = $u_entry[7];
  $ENV{USER} = $ENV{LOGNAME} = $u_entry[0];

  return 1;
}

sub ce_get_user_gids {
  my($username) = @_;
  my $f = 'ce_get_user_gids()';

  my @gids = ();

  if(!open(CE_GROUP_F, '/etc/group')) {
    warn "$f: error, unable to open /etc/group\n";
    return ();
  }

  my @user_ar = getpwnam($username);
  if(@user_ar) {
    push(@gids, $user_ar[3]);
  } else {
    warn "$f: error user doesn't exist\n";
    return '';
  }
  
  flock(CE_GROUP_F, LOCK_SH);

  while(<CE_GROUP_F>) {
    chomp();
    my($name, undef, $gid, $members) = split(/:/, $_, 4);
    if(!defined($members)) {
      next;
    }

    if(grep({ $_ eq $username; } (split(/,/, $members))) &&
      !grep({ $_ eq $gid } @gids)) {

      push(@gids, $gid);
    }
  }

  flock(CE_GROUP_F, LOCK_UN);
  close(CE_GROUP_F);

  return join(' ', @gids);
}

sub ce_is_hash_key_empty {
  my($hash_ref, $key) = @_;

  if(!exists($hash_ref->{$key})) {
    return 1;
  } elsif(!defined($hash_ref->{$key})) {
    return 1;
  } elsif(length($hash_ref->{$key}) == 0) {
    return 1;
  } else {
    return 0;
  }
}

sub ce_drop_gid {
  my($gid) = @_;
  my $f = 'ce_drop_gid()';

  if(!defined($gid)) {
    warn "$f: missing gid\n";
    return 0;
  } elsif(length($gid) == 0) {
    warn "$f: empty gid\n";
    return 0;
  }

  undef($!) if(defined($!));
  $( = $) = $gid;  # setgid(); equivalent
  if($!) {
    warn "Error: Unable to setgid() to target_group: $!";
    return 0;
  }

  return 1;
}

sub ce_drop_uid {
  my($uid) = @_;
  my $f = 'ce_drop_uid()';

  if(!defined($uid)) {
    warn "$f: missing uid\n";
    return 0;
  } elsif(length($uid) == 0 || $uid !~ /^\d+$/) {
    warn "$f: invalid uid\n";
    return 0;
  }

  undef($!) if(defined($!));
  $< = $> = $uid;  # setuid(); equivalent
  if($!) {
    warn "Error: Unable to setuid() to target_user: $! \n";
    return 0;
  }

  return 1;
}

sub ce_has_flag {
  my($base_value, $flag) = @_;

  return ($base_value & $flag) == $flag;
}

sub ce_set_flag {
  my($base_value, $flag) = @_;

  return $base_value | $flag;
}

sub ce_clear_flag {
  my($base_value, $flag) = @_;

  return $base_value & ~$flag;
}

sub ce_toggle_flag {
  my($base_value, $flag) = @_;

  return $base_value ^ $flag;
}

1;
