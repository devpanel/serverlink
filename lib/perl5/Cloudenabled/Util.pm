package Cloudenabled::Util;
require Exporter;
our @ISA = ('Exporter');
use strict;
use warnings;
use Cloudenabled::Constants (qw( :DEFAULT %CE_OP_ST_MAP %CE_TASKS_MSG_TYPES ));
use POSIX (qw( setsid strftime ));
use Digest::SHA (qw( hmac_sha256_hex ));
use Fcntl (qw( :DEFAULT :flock ));

our $cgi_param_separator = '&';

our @EXPORT = (qw(
  cloudenabled_parse_conf cloudenabled_daemonize cloudenabled_sign_data
  ce_ret_success ce_ret_internal_error ce_ret_format_error ce_gen_random_str
  ce_ret_invalid_value ce_ret_missing_required ce_ret_nothing_updated
  ce_ret_permission_denied ce_was_successful ce_ret_signature_error
  ce_ret_not_found ce_ret_local_error ce_log ce_map_op_st_str
  ce_error_r_str
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
  ce_add_to_hash
));

our @EXPORT_OK = (qw(
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
    $r->{error_msg} = $errmsg;
  }

  return $r;
}

sub ce_ret_format_error {
  my($r, $p, $msg) = @_;

  $r->{status} = CE_OP_ST_PARAMETER_FORMAT_ERROR;
  $r->{error_msg} = defined($msg) ? $msg : "Invalid syntax of parameter $p";

  return $r;
}

sub ce_ret_invalid_value {
  my($r, $p, $msg) = @_;

  $r->{status} = CE_OP_ST_PARAMETER_INVALID_VALUE;
  $r->{error_msg} = defined($msg) ? $msg : "Invalid value for parameter $p";

  return $r;
}

sub ce_ret_missing_required {
  my($r, $p, $msg) = @_;

  $r->{status} = CE_OP_ST_MISSING_PARAMETERS;
  $r->{error_msg} = defined($msg) ? $msg : "Missing parameter $p";

  return $r;
}

sub ce_ret_nothing_updated {
  my($r, $p) = @_;
  $r->{status} = CE_OP_ST_NOTHING_UPDATED;
  if(defined($p)) {
    $r->{error_msg} = $p;
  }

  return $r;
}

sub ce_ret_permission_denied {
  my($r, $p) = @_;
  $r->{status} = CE_OP_ST_PERMISSION_DENIED;

  if(defined($p)) {
    $r->{error_msg} = $p;
  }

  return $r;
}

sub ce_ret_signature_error {
  my($r, $msg) = @_;

  $r = {} if(!defined($r));
  $r->{status} = CE_OP_ST_SIGNATURE_ERROR;

  if(defined($msg)) {
    $r->{error_msg} = $msg;
  }

  return $r;
}

sub ce_ret_not_found {
  my($r,$msg) = @_;

  $r = {} if(!defined($r));

  $r->{status} = CE_OP_ST_NOT_FOUND;

  if(defined($msg)) {
    $r->{error_msg} = $msg;
  }

  return $r;
}

sub ce_ret_local_error {
  my($r,$msg) = @_;

  $r = {} if(!defined($r));

  $r->{status} = CE_OP_ST_LOCAL_ERROR;

  if(defined($msg)) {
    $r->{error_msg} = $msg;
  }

  return $r;
}

sub ce_ret_unknown_operation {
  my($r,$msg) = @_;

  $r = {} if(!defined($r));

  $r->{status} = CE_OP_ST_UNKNOWN_OPERATION;

  if(defined($msg)) {
    $r->{error_msg} = $msg;
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

sub ce_error_r_str {
  my($rsp_r) = @_;

  my $errmsg = exists($rsp_r->{error_msg}) ? $rsp_r->{error_msg} : "(none)";
  my $tag    = exists($rsp_r->{ctl_tag})   ? $rsp_r->{ctl_tag}   : "";

  return "Error[$tag]: " . ce_map_op_st_str($rsp_r->{status}) . ": $errmsg.";
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

sub ce_add_to_hash {
  my($hash_r, $key, $value) = @_;

  if(!exists($hash_r->{$key}) || !defined($hash_r->{$key})) {
    $hash_r->{$key} = $value;
  } elsif(!ref($hash_r->{$key})) {
    my $curr_value = $hash_r->{$key};
    $hash_r->{$key} = [ $curr_value, $value ];
  } elsif(ref($hash_r->{$key}) eq "ARRAY") {
    push(@{ $hash_r->{$key} }, $value);
  } else {
    warn "ce_add_to_hash(): invalid value for key $key\n";
    return 0;
  }
}

1;
