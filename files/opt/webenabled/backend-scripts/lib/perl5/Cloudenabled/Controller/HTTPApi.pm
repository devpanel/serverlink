package Cloudenabled::Controller::HTTPApi;
use base 'CGI::Application';

use MIME::Base64;
use Data::Dumper;
use Socket;
use CGI::Util (qw( escape ));
use Cloudenabled::Constants;
use Cloudenabled::Util;
use Cloudenabled::Tasks::Util;
use Cloudenabled::RPCComm;
use JSON::XS;

our $param_separator = ';';

sub setup {
  my $app = shift;
  my @modes = (
                  &CE_TASK_OP_HELLO       => 'hello',
                  &CE_TASK_OP_GET_MSGS    => 'get_msgs',
                  &CE_TASK_OP_REPORT      => 'task_report',
                  &CE_TASK_OP_SET_RUNNING => 'set_running',
                  'error_log'             => 'error_log',
                  'create_server'         => 'create_server',
                  'server_reboot'         => 'server_reboot',
                  'public_key_vhost'      => 'public_key_vhost',
                  'exists_mode'           => 'exists_mode',
                  'get_server_info'       => 'get_server_info',
                  'list_activities'       => 'list_activities',
                  'list_tasks'            => 'list_tasks',
                  'get_activity_report'   => 'get_activity_report',
                  'get_task_status'       => 'get_task_status',
                  'retry_activity'        => 'retry_activity',
                  'cancel_activity'       => 'cancel_activity',
                  'list_hosting_companies' => 'list_hosting_companies',
              );

  
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
}

sub cgiapp_prerun {
  my $app = shift;
  my $cgi = $app->query;

  $cgi->autoEscape(0);

  # basic header validation before proceeding
  # if(!ce_was_successful(my $ret = _prerun_validate($app))) {
  #  $app->param('r', $ret);
  #  goto REDIRECT_TO_ERROR_MODE;
  # }

  my $ctl  = $app->param('ctlconn');
  # test connection to controller
  # and try to reconnect if not connected
  if(!$ctl->ping() && ! $ctl->connect_socket()) {
    $app->param('r', ce_ret_internal_error({}, 'internal connectivity problem'));
    goto REDIRECT_TO_ERROR_MODE;
  }

  my $host = $cgi->http(CE_HEADER_SERVER_STR);
  my $sig  = $cgi->http(CE_HEADER_SIGNATURE_STR);

  my $data_to_sign = _extract_data_to_sign($cgi);
  $app->param('DEBUG') and warn "verifying signature of data: $data_to_sign, expected sig: $sig";

  if(!ce_was_successful(my $ret = $ctl->op('validate_signature',
                          { uuid => $host,
                            data => $data_to_sign,
                            exp_sig => $sig
                            }))) {

    $app->param('r', $ret);
    goto REDIRECT_TO_ERROR_MODE;
  } else {
    $app->param('auth_data', { uuid => $host });
  }

  return 1;

REDIRECT_TO_ERROR_MODE:
  $app->prerun_mode($app->error_mode);
  return 0;
}

sub cgiapp_postrun {
  my($app, $output) = @_;
  my $cgi = $app->query;

  if(defined($app->param('r'))) {
    $ret = $app->param('r');
    $app->param('DEBUG') and warn "sending response ". Dumper($ret) . "\n";
  } else {
    $app->param('DEBUG') and warn "received an empty response\n";
    $ret = {};
  }

  my $ctl = $app->param('ctlconn');

  $app->header_add(-type => 'application/json');

  $ret->{auth_random}   = ce_gen_random_str();
  $ret->{timestamp}   = time();

  $$output = encode_json($ret);

  my $auth_ref = $app->param('auth_data');
  if($auth_ref &&
    ce_was_successful(my $rs = $ctl->op('sign_data',
                       { uuid => $auth_ref->{uuid},
                         data => $$output }
                                 ))) {

    $app->header_add('-'. CE_HEADER_SIGNATURE_STR, $rs->{sig});
  }

}

sub teardown {
  my $app = shift;
  # clean session variable for next request
  $app->delete('auth_ref');
  $app->delete('r');
}

sub create_server {
  my $app = shift;
  my $cgi = $app->query;

  my $ctlop = $app->param('ctlconn');
 
  my $req = {}; 

  $req->{hostname} = $cgi->param('hostname');
  $req->{uuid}     = $cgi->param('uuid');
  $req->{hosting_company_id} = $cgi->param('hosting_company_id');

  $req->{dashboard_act_id} = $cgi->param('dashboard_act_id');

  if($cgi->param('install_software')) {
    $req->{install_software} = 1;
    $req->{ip_address}    = $cgi->param('ip_address');
    $req->{root_user}     = $cgi->param('root_user');
    $req->{root_pw}       = $cgi->param('root_pw');
    $req->{tasks_api_url} = $app->param('tasks_api_url');
    $req->{bootstrap_file} = $app->param('bootstrap_file');
    $req->{internal_exec_server} = $app->param('internal_exec_server');
  }

  $app->param('r', $ctlop->op('create_server', $req));

  return;
}

sub exists_mode {
  my $app = shift;

  $app->param('r', ce_ret_success());

  return 1;
}

sub server_reboot {
  my $app = shift;
  my $cgi = $app->query;

  my $ctl = $app->param('ctlconn');
  my $uuid = $cgi->param('server');

  $ctl->op('server_reboot', { uuid => $uuid });

  $app->param('r', $ctl->op('server_reboot', { uuid => $uuid }));

  return 1;
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
    $app->param('r', ce_ret_internal_error({}, $msg));
  } elsif(!$app->param('r')) {
    $app->param('r', ce_ret_internal_error());
  }

  return 0;
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

sub get_server_info {
  my $app = shift;
  my $cgi = $app->query;

  my $ctl = $app->param('ctlconn');

  my @uuids = $cgi->param('uuid');

  $app->param('r', $ctl->op('get_server_info', { uuid => \@uuids }));

  return 1;
}

sub list_activities {
  my $app = shift;
  my $cgi = $app->query;
  my $ctl = $app->param('ctlconn');

  # the list of activities is explicitly entered
  my $p;
  my $req = {};

  my @ids = $cgi->param('id');
  my @dash_act_ids = $cgi->param('dashboard_act_id');

  if(@ids) {
    $req->{id} = \@ids;
  } elsif(@dash_act_ids) {
    $req->{dashboard_act_id} = \@dash_act_ids;
  }

  $app->param('r', $ctl->op('list_activities', $req));

  return;
}

sub list_tasks {
  my $app = shift;
  my $cgi = $app->query;
  my $ctl = $app->param('ctlconn');

  my $act_id = $cgi->param('act_id');

  $app->param('r', $ctl->op('list_tasks', { act_id => $act_id }));

  return;
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

sub get_activity_report {
  my $app = shift;
  my $cgi = $app->query;

  my $ctl = $app->param('ctlconn');

  my $req = {};
  if(defined($cgi->param('id'))) {
    $req->{id} = $cgi->param('id');
  } elsif(defined($cgi->param('dashboard_act_id'))) {
    $req->{dashboard_act_id} = $cgi->param('dashboard_act_id');
  }

  $app->param('r', $ctl->op('get_activity_report', $req));

  return;
}

sub get_task_status {
  my $app = shift;
  my $cgi = $app->query;

  my $ctl = $app->param('ctlconn');

  my $req = {};
  $req->{id} = $cgi->param('id');

  $app->param('r', $ctl->op('get_task_status', $req));

  return;
}

sub retry_activity {
  my $app = shift;
  my $cgi = $app->query;

  my $ctl = $app->param('ctlconn');

  my $req = {};
  $req->{id} = $cgi->param('id');

  $app->param('r', $ctl->op('retry_activity', $req));

  return;
}

sub cancel_activity {
  my $app = shift;
  my $cgi = $app->query;

  my $ctl = $app->param('ctlconn');

  my $req = {};
  $req->{id} = $cgi->param('id');

  $app->param('r', $ctl->op('cancel_activity', $req));

  return;
}

sub public_key_vhost {
  my $app = shift;
  my $cgi = $app->query;

  my $ctl = $app->param('ctlconn');

  my $req = {};

  my @add_keys = $cgi->param('add_key');
  my @del_keys = $cgi->param('del_key');

  $req->{server} = $cgi->param('server');
  $req->{vhost}  = $cgi->param('vhost');

  if(@add_keys) {
    $req->{add_key} = \@add_keys;
  }
  if(@del_keys) {
    $req->{del_key} = \@del_keys;
  }

  $app->param('r', $ctl->op('public_key_vhost', $req));

  return;
}

sub list_hosting_companies {
  my $app = shift;
  my $cgi = $app->query;

  my $ctl = $app->param('ctlconn');

  $app->param('r', $ctl->op('list_hosting_companies'));

  return;
}

1;
