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

our $cgi_param_separator = ';';

our @EXPORT = (qw(
  cloudenabled_parse_conf cloudenabled_daemonize cloudenabled_sign_data
  ce_ret_success ce_ret_internal_error ce_ret_format_error ce_gen_random_str
  ce_ret_invalid_value ce_ret_missing_required ce_ret_nothing_updated
  ce_ret_permission_denied ce_was_successful ce_ret_signature_error
  ce_ret_not_found ce_ret_local_error ce_log ce_map_op_st_str
  ce_convert_task_ret ce_extract_cmd_params
  ce_map_task_msg_str ce_set_autoflush_noblock
));

our @EXPORT_OK = (qw(
  ce_tasks_http_request ce_task_cgi_2_ref
));

our $debug = 0;

sub cloudenabled_parse_conf {
  my $file = $_[0];
  my $conf;
    
  if($#_ == 1) {
    return undef;
  } elsif($#_ == 0) {
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
        ce_log(sprintf("Warning: skipping invalid line %d in config file\n", $n));
        next;
      }

      $conf->{$param} = $value;
    } else {
      ce_log(sprintf("Warning: skipping invalid line %d in config file\n", $n));
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

1;
