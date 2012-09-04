package Cloudenabled::Tasks::HTTPApi;
use base 'CGI::Application';

use MIME::Base64;
use Data::Dumper;
use Socket;
use CGI::Util (qw( escape ));
use Cloudenabled::Constants;
use Cloudenabled::Util;
use Cloudenabled::Tasks::Util;
use Cloudenabled::Controller::Util;
use Cloudenabled::RPCComm;

our $param_separator = ';';

sub setup {
  my $app = shift;
  my @modes = (
                  &CE_TASK_OP_HELLO       => 'hello',
                  &CE_TASK_OP_GET_MSGS    => 'get_msgs',
                  &CE_TASK_OP_REPORT      => 'task_report',
                  &CE_TASK_OP_SET_RUNNING => 'set_running',
                  'error_log'             => 'error_log',
                  'install_token'         => 'install_token',
              );
              #    validation_error error_log sig_err list set_state report 
              #    get_next list2run update_dns set_running );
  
  $app->mode_param('op');
  $app->start_mode('error_log'); # unknown modes go here
  $app->error_mode('error_log');
  $app->run_modes(@modes);
}

sub cgiapp_init {
  my $app = shift;

  my $ctlconn = Cloudenabled::RPCComm->new( connect_address => 'unix:/tmp/controllerd_socket');
  if(!$ctlconn) {
    warn "Error: unable to connect to controller\n";
    exit(1);
  }

  $app->param('ctlconn', $ctlconn);
  open(F, '>>/tmp/fastcgi-started.txt');
  print F "Started: ", scalar(localtime()), "\n";
  close(F);

  $app->param('min_idle_time', 600);
}

sub _prerun_validate {
  # basic validation of the request
  my $app = shift;
  my $cgi = $app->query;
  
  if(!$cgi->remote_addr) {
    return ce_ret_local_error({}, "couldn't get IP address. Are you running it from command line?");
  }

  if(!defined($cgi->http(CE_HEADER_SIGNATURE_STR))) {
    return ce_task_ret_signature_error({}, 'missing signature header');
  }

  my $run_mode = $app->get_current_runmode;
  warn "run mode = " . $run_mode . "\n";
  if($run_mode ne CE_TASK_OP_HELLO && !$cgi->param('_S')) {
    return ce_ret_missing_required({}, '', 'missing session parameter');
  } elsif($run_mode eq CE_TASK_OP_HELLO && !$cgi->param('U')) {
    return ce_ret_missing_required({}, '', 'missing host parameter');
  }

  return ce_ret_success();
}


sub cgiapp_prerun {
  my $app = shift;
  my $cgi = $app->query;

  $cgi->autoEscape(0);

  # basic header validation before proceeding
  if(!ce_was_successful(my $ret = _prerun_validate($app))) {
    $app->param('r', $ret);
    goto REDIRECT_TO_ERROR_MODE;
  }

  my $ctl  = $app->param('ctlconn');
  # test connection to controller
  # and try to reconnect if not connected
  if(!$ctl->ping() && ! $ctl->connect_socket()) {
    $app->param('r', ce_task_ret_internal_error({}, 'internal connectivity problem'));
    $app->param('s', 1);
    goto REDIRECT_TO_ERROR_MODE;
  }

  my $run_mode = $app->get_current_runmode;
  if($run_mode ne CE_TASK_OP_HELLO) {
    $session_id = $cgi->param('_S');

    # a session was provided, let's validate it
    my $ret = $ctl->op('get_active_server_session_byid', { id => $session_id });
    if(!ce_was_successful($ret) && $ret->{status} == CE_OP_ST_NOT_FOUND) {
      # let's not leak if the session exists or not
      $app->param('r', ce_ret_permission_denied({}));
      goto REDIRECT_TO_ERROR_MODE;
    } elsif(!ce_was_successful($ret)) {
      $app->param('r', $ret);
      goto REDIRECT_TO_ERROR_MODE;
    }

    $session_ref = $ret->{entry};
    $host        = $session_ref->{server_uuid};

    $ctl->op('update_last_vps_checkin', {
                                    server_id => $session_ref->{server_id},
                                    session_id => $session_ref->{id}
                                    });
    $app->param('session_ref', $session_ref);
  } elsif($run_mode eq CE_TASK_OP_HELLO) {
    $host = $cgi->param('U');
    my $ret = $ctl->op('get_server_info', { uuid => $host });
    if(!ce_was_successful($ret) && $ret->{status} == CE_OP_ST_NOT_FOUND) {
      # let's not explicitly leak whether the uuid exists or not
      $app->param('r', ce_ret_permission_denied({}));
      goto REDIRECT_TO_ERROR_MODE;
    } elsif(!ce_was_successful($ret)) {
      $app->param('r', $ret);
      goto REDIRECT_TO_ERROR_MODE;
    }
  }

  my $sig = $cgi->http(CE_HEADER_SIGNATURE_STR);

  my $data_to_sign = _extract_data_to_sign($cgi);
  $app->param('DEBUG') and warn "verifying signature of data: $data_to_sign, expected sig: $sig";

  if(!ce_was_successful(my $ret = $ctl->op('validate_server_signature',
                          { uuid => $host,
                            data => $data_to_sign,
                            exp_sig => $sig
                            }))) {

    $app->param('r', $ret);
    goto REDIRECT_TO_ERROR_MODE;
  }

  return 1;

REDIRECT_TO_ERROR_MODE:
  $app->prerun_mode($app->error_mode);
  return 0;
}

sub cgiapp_postrun {
  my($app, $output) = @_;
  my $cgi = $app->query;

  if(defined($app->param('raw_output'))) {
    return 1; # leave the output untouched
  } elsif(defined($app->param('r'))) {
    $ret = $app->param('r');
    $app->param('DEBUG') and warn "sending response ". Dumper($ret) . "\n";
  } else {
    $app->param('DEBUG') and warn "received an empty response\n";
    $ret = {};
  }

  my $ctl = $app->param('ctlconn');

  $app->header_add(-type => 'application/x-www-form-urlencoded');

  if(exists($ret->{status})) {
    $ret->{_s} = $ret->{status};
    delete($ret->{status});
  }

  if(exists($ret->{errmsg})) {
    $ret->{_e} = $ret->{errmsg};
    delete($ret->{errmsg});
  }

  $ret->{_r}   = ce_gen_random_str();
  $ret->{_t}   = time();

  $$output = _encode_output($ret);

  if($app->param('s')) {
    $app->header_add('-' . CE_HEADER_STATUS_STR, $ret->{_s});
    $app->delete('s');
  }

  my $session_ref = $app->param('session_ref');
  if($session_ref &&
    ce_was_successful(my $rs = $ctl->op('sign_server_data',
                       { uuid => $session_ref->{server_uuid},
                         data => $$output }
                                 ))) {

    $app->header_add('-'. CE_HEADER_SIGNATURE_STR, $rs->{sig});
  }

}

sub teardown {
  my $app = shift;
  # clean session variable for next request
  $app->delete('session_ref');
  $app->delete('raw_output');
  $app->delete('r');
}

sub hello {
  my $app = shift;
  my $cgi = $app->query;
  my $ctl = $app->param('ctlconn');

  my $host       = $cgi->param('U');
  my $session_ref;
  my $idle_time = 0;

  my $ret = $ctl->op('get_active_server_session', { uuid => $host });

  if(!ce_was_successful($ret) && $ret->{status} != CE_OP_ST_NOT_FOUND) {
    $app->param('r', $ret);
    return;
  } elsif(ce_was_successful($ret)) {
    $session_ref = $ret->{entry};
    $idle_time   = time() - $session_ref->{last_checkin};
    $app->param('session_ref', $session_ref);
  }

  my $curr_ip = $cgi->remote_addr();

  if($session_ref && $session_ref->{ip_address} eq $curr_ip) {
    # there's already an open session for this IP, let's re-use it
    $app->param('r', ce_task_ret_success( { _S => $session_ref->{id},
                                            P => 60, E => 30 } ));
    return;
  } elsif($session_ref && $session_ref->{ip_address} ne $curr_ip &&
      $idle_time < $app->param('min_idle_time')) {
    # there's a session open, but for another IP...let's reject this
    # connection
    $app->param('r', ce_ret_permission_denied({}, 
                "there's a session open for another IP. Please wait a bit for it to expire"));
    return;
  } elsif($idle_time >= $app->param('min_idle_time') &&
    !ce_was_successful(my $ret = $ctl->op('close_server_session', {
                                  uuid       => $session_ref->{server_uuid},
                                  session_id => $session_ref->{id},
                                  }    ))) { 
    # the previous session expired, tried to close it, but it failed
    $app->param('r', $ret);
    return;
  } elsif(!$session_ref || $idle_time >= $app->param('min_idle_time')) {
    # there's no active session, or the session was expired and closed in
    # the previous elsif condition
    my $sr = $ctl->op('create_server_session', { uuid => $host, ip_address => $curr_ip });
    if(ce_was_successful($sr)) {
      $app->param('session_ref', { server_uuid => $host, id => $sr->{id} });
      $app->param('r', ce_task_ret_success({ _S => $sr->{id},
                                              P => 60, E => 30 }));
      return;
    } else {
      $app->param('r', $sr);
      return;
    }
  } else {
    $app->param('r', ce_ret_permission_denied({}, "unknown session condition"));
    return;
  }

}

sub error_log {
  my $app = shift;
  my $msg = shift;

  if(!$app->param('r') && defined($msg)) {
    $app->param('r', { _s => CE_OP_ST_INTERNAL_ERROR, _e => $msg });
  } elsif(!$app->param('r')) {
    $app->param('r', { _s => CE_OP_ST_INTERNAL_ERROR });
  }

  return;
}

sub task_report {
  my $app = shift;
  my $cgi = $app->query;

  my $ctl = $app->param('ctlconn');

  my $ref = {
    output    => $cgi->param('o'),
    ret       => $cgi->param('r'),
    task_id   => $cgi->param('T'),
    end_time  => $cgi->param('e') || time(),
    server_id => $app->param('session_ref')->{server_id}
  };

  $app->param('r', $ctl->op('task_report', $ref));

  return 1;
}

sub set_running {
  my $app = shift;
  my $cgi = $app->query;
  my $dbh = $app->param('dbh');

  my @task_ids = $cgi->param('T');

  if(!@task_ids) {
    $app->param('r', ce_ret_missing_required({}, 'T'));
    return 0;
  }

  my $server_id = $app->param('session_ref')->{server_id};

  my $ctl = $app->param('ctlconn');

  my $ret = $ctl->op('set_running', { 
                                    server_id => $server_id,
                                    task_id   => \@task_ids,
                                  });

  $app->param('r', $ret);

  return 1;
}

sub get_msgs {
  my $app = shift;
  my $cgi = $app->query;
  my $ctl = $app->param('ctlconn');

  my $server_id = $app->param('session_ref')->{server_id};

  my $max = defined($cgi->param('N')) ? $cgi->param('N') : 5;

  my $ret = $ctl->op('list2run', { server_id => $server_id,
                                   max       => $max });

  if(!ce_was_successful($ret)) {
    $app->param('r', $ret);
    return;
  }
  my $tasks_ar = $ret->{task_data};

  # no tasks for this VPS, that's fine
  if($#{ $tasks_ar } < 0) {
    $app->param('r', ce_ret_success({ _M => CE_TASK_MSG_NO_MESSAGES }));
    return;
  }

  my @cmd_ids = ();
  foreach my $t (@{ $tasks_ar }) {
    push(@cmd_ids, $t->{command_id}); # duplicates are ok
  }

  if(!ce_was_successful($ret = $ctl->op('get_cmd_defs', { id => \@cmd_ids }))) {
    $app->param('r', $ret);
    return $ret;
  }
  my $cmd_defs = $ret->{cmd_defs};

  my $compacted_data;
  if($compacted_data = ce_task_compact_data($tasks_ar, $cmd_defs)) {
    $compacted_data->{_M} = CE_TASK_MSG_RUN_TASKS;
    $app->param('r', ce_ret_success($compacted_data));
  } else {
    $app->param('r', ce_ret_internal_error({ _M => CE_TASK_MSG_NO_MESSAGES }, 'unable to compact task data'));
  }

  return;
}

sub install_token {
  my $app = shift;
  my $cgi = $app->query;
  my $ctl = $app->param('ctlconn');

  $app->param('raw_output', 1);
  my $token = $cgi->param('token');

  if(!$token) {
    return 'missing token';
  } elsif(length($token) != 12 || $token !~ /^\w+$/) {
    return 'invalid token format';
  }

  my $ret_r = $ctl->op('get_install_info', { token_str => $token });
  if(ce_was_successful($ret_r)) {
    return 'successfully retrieved token';
  } else {
    return 'error, unable to retrieve the information';
  }
}

sub _is_valid_signature {
  my $app = shift;
  my $cgi = $app->query;
  my $dbh = $app->param('dbh');
  my $host;

  if(!($host = _get_row($dbh, 'Servers', 
                            { uuid => scalar($cgi->http(CE_HEADER_SERVER_STR)) }))) {
    warn "[secwarn] Authentication: unknown server\n";
    return 0;
  }

  my $data;
  if(lc($cgi->request_method) eq 'get') {
    $data = $cgi->url(-absolute => 1, -query => 1);
  } elsif(lc($cgi->request_method) eq 'post' && $cgi->content_type eq 'application/x-www-form-urlencoded') {
    foreach my $p ($cgi->param) {
      if(length($data) != 0) {
        $data .= ';';
      }
      $data .= sprintf('%s=%s', $p, CGI::escape($cgi->param($p)));
    }
  }

  my $fmt = "%s signature. method = %s, data = %s, sig = %s";
  my $sig  = hmac_sha256_hex($data, $host->{key});

  if($sig eq $cgi->http(CE_HEADER_SIGNATURE_STR)) {
    $app->param('DEBUG') and
      printf STDERR $fmt, 'Valid', $cgi->request_method(), $data, $sig;
    return 1;
  } else {
    $app->param('DEBUG') and 
      printf STDERR $fmt, '[secwarn] Invalid', $cgi->request_method(), $data, $sig;
    return 0;
  }
}

sub _extract_data_to_sign {
  my($cgi) = @_;

  my $data = '';

  my $method = lc($cgi->request_method);

  if($method eq 'get') {
    $data = $cgi->url(-absolute => 1, -query => 1);
  } elsif($method eq 'post') {
    foreach my $p ($cgi->param) {
      if(length($data) > 0) {
        $data .= $param_separator;
      }

      my @values = ($cgi->param($p));
      for(my $i=0 ; $i <= $#values; $i++) {
        $data .= sprintf('%s=%s', $p, CGI::escape($values[$i]));
        if($i < $#values) {
          $data .= $param_separator;
        }
      }
    }
  } else {
    warn __PACKAGE__, " - _extract_data_to_sign(): Unsupported method: ", $cgi->request_method, "\n";
    return 0;
  }

  return $data;
}

sub _encode_output {
  my($r) = @_;

  my $str = '';
  foreach my $k (keys %$r) {
    $str .= $param_separator if(length($str) > 0);
    if(ref($r->{$k}) && ref($r->{$k}) eq 'ARRAY') {
      my @v = ();
      foreach my $e (@{ $r->{$k} }) {
        push(@v, sprintf('%s=%s', $k, escape($e)));
      }
      $str .= join($param_separator, @v);
    } else {
      $str .= sprintf('%s=%s', $k, escape($r->{$k}));
    }
  }

  return $str;
}

1;
