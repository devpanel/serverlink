package Cloudenabled::Controller::Operations;
use warnings;
use strict;
use Cloudenabled::Constants;
use Cloudenabled::Util;
use Cloudenabled::Controller::Util;
use JSON::XS;

our $debug = 0;

sub new {
  my($class, @opts) = @_;
  my $self = {};

  if($#opts % 2 == 0) { # if the last element is even, the number of entered
                        # arguments is odd
    warn "Error: received an odd number of arguments\n";
    return 0;
  }

  my($db_type, $db_url, $db_user, $db_pass, $db_opts);
  
  for(my $i=0; $i < $#opts; $i++) {
    my $key = $opts[$i];
    my $val = defined($opts[++$i]) ? $opts[$i] : undef;

    if($key eq 'db_type') {
      $db_type = $val;
    } elsif($key eq 'db_url') {
      $db_url = $val;
    } elsif($key eq 'db_user') {
      $db_user = $val;
    } elsif($key eq 'db_pass') {
      $db_pass = $val;
    } elsif($key eq 'db_opts') {
      $db_opts = $val;
    } elsif($key eq 'debug') {
      $debug = defined($val) && $val ? 1 : 0;
      use Data::Dumper;
    }
  }

  if(!defined($db_type)) {
    warn "Error: missing parameter db_type";
    return 0;
  } elsif(!defined($db_url)) {
    warn "Error: missing parameter db_url";
    return 0;
  }

  my $base_pkg;
  ($base_pkg = __PACKAGE__) =~ s/::[^:]+?$//; # remove the latest :: from the
                                              # package name

  our $db_pkg = $base_pkg . '::Database::' . uc($db_type);
  eval "use $db_pkg;";
  if($@) {
    warn "Error: there's no corresponding module to this database type - $@";
    return 0;
  }
  
  my $dbh = $db_pkg->new('db_url' => $db_url,
    'db_user' => defined($db_user) ? $db_user : '',
    'db_pass' => defined($db_pass) ? $db_pass : '',
    'db_opts' => defined($db_opts) ? $db_opts : {}
  );

  if($dbh) {
    $self->{_dbh} = $dbh;
  } else {
    warn "Error: unable to connect to the database.";
    return 0;
  }

  return bless($self, $class || __PACKAGE__);
}

my $_assemble_activity = sub {
  my($self, $act_ref) = @_;
  my $ctldb  = $self->{_dbh};

  if(!exists($act_ref->{activity_name})) {
    return ce_ret_missing_required({}, 'activity_name');
  }

  my $name_ref = $ctldb->get_activity_name_entry($act_ref->{activity_name});
  if(!ce_was_successful($name_ref)) {
    if($name_ref->{status} == CE_OP_ST_NOT_FOUND) {
      $name_ref->{errmsg} = "activity_name not found";
    }
    return $name_ref;
  }

  $act_ref->{__name_ref} = $name_ref->{entry};
  $act_ref->{name_id}    = $name_ref->{entry}->{id};

  foreach my $p (qw( flags priority dashboard_act_id )) {
    if(!exists($act_ref->{$p}) || !defined($act_ref->{$p})) {
      $act_ref->{$p} = 0;
    }
  }

  if(!exists($act_ref->{state}) || !defined($act_ref->{state})) {
    $act_ref->{state} = CE_TASK_ST_WAITING;
  }

  return ce_ret_success({ activity => $act_ref });

};

my $_validate_activity = sub {
  my($self, $act_ref) = @_;

  my $ctldb = $self->{_dbh};

  foreach my $p (qw( name_id dashboard_act_id state priority flags )) {
    if(!exists($act_ref->{$p}) || !defined($act_ref->{$p})) {
      return ce_ret_missing_required({}, $p);
    }
  }

  return ce_ret_success();
};

my $_create_activity = sub {
  my($self, $info) = @_;
  my $ctldb = $self->{_dbh};

  if(!ce_was_successful(my $v_ret = &$_validate_activity($self, $info))) {
    return $v_ret;
  }


  my $res = $ctldb->create_activity($info);
  return $res;
};

my $_encode_task_data = sub {
  my($data) = @_;

  if(!defined($data)) {
    $data = {};
  }
  
  undef($@);
  my $encoded = eval { encode_json($data); };
  if($@) {
    warn __PACKAGE__, " encode_task_data(): unable to encode input_data to JSON: $@\n";
    return 0;
  } else {
    return $encoded;
  }
};

my $_assemble_task = sub {
  my($self, $op_r, $data_r) = @_;
  my $ctldb = $self->{_dbh};

  foreach my $p (qw( command_name exec_server_id )) {
    if(!exists($op_r->{$p})) {
      return ce_ret_missing_required({}, $p);
    }
  }

  if(exists($op_r->{activity_id}) && defined($op_r->{activity_id})) {
    my $act_ref = $ctldb->get_activity_entry($op_r->{activity_id});
    if(!ce_was_successful($act_ref)) {
      $act_ref->{errmsg} = "activity_id not found";
      return $act_ref;
    }
    $op_r->{__actref} = $act_ref->{entry};
  }

  my $cmd_ref = $ctldb->get_command_entry($op_r->{command_name});
  if(!ce_was_successful($cmd_ref)) {
    $cmd_ref->{errmsg} = "command_name not found";
    return $cmd_ref;
  }
  $op_r->{__cmdref}   = $cmd_ref->{entry};
  $op_r->{command_id} = $cmd_ref->{entry}->{id};

  my $srv_ref = $ctldb->get_server_entry($op_r->{exec_server_id});
  if(!ce_was_successful($srv_ref)) {
    $srv_ref->{errmsg} = "server_exec_id not found";
    return $srv_ref;
  }
  $op_r->{__srvref}       = $srv_ref->{entry};
  $op_r->{exec_server_id} = $srv_ref->{entry}->{id};


  if(!defined($data_r)) {
    $data_r = {};
  }

  if(!exists($op_r->{state}) || !defined($op_r->{state})) {
    $op_r->{state} = CE_TASK_ST_WAITING;
  }

  if(!exists($op_r->{flags}) || !defined($op_r->{flags})) {
    $op_r->{flags} = 0;
  }

  if(!($op_r->{input_data} = &$_encode_task_data($data_r))) {
    return ce_ret_internal_error({}, "unable to encode input_data to JSON: $@");
  }

  return ce_ret_success({ task => $op_r });

};

my $_validate_task = sub {
  my($self, $task_ref) = @_;

  my $ctldb = $self->{_dbh};

  foreach my $p (qw( command_id activity_id exec_server_id input_data flags )) {
    if(!exists($task_ref->{$p}) || !defined($task_ref->{$p})) {
      return ce_ret_missing_required({}, $p);
    }
  }

  return ce_ret_success();
};

my $_create_task = sub {
  my($self, $info, $data) = @_;
  my $ctldb = $self->{_dbh};

  if(!ce_was_successful(my $v_ret = &$_validate_task($self, $info))) {
    return $v_ret;
  }

  return $ctldb->create_task($info);
};

my $_create_activity_n_tasks = sub {
  my($self, $act_ref, $tasks_ref) = @_;

  return $self->{_dbh}->create_activity_n_tasks($act_ref, $tasks_ref);
};

my $_create_install_token = sub {
  my($self, $server_id) = @_;

  my $dbh = $self->{_dbh};

  my $token_str = ce_gen_random_str(12);

  my $ret = $dbh->create_install_token($server_id, $token_str);
  if(ce_was_successful($ret)) {
    $ret->{token_str} = $token_str;
  }

  return $ret;
};

sub execute {
  my($self, $req) = @_;

  if(!exists($req->{op})) {
    return ce_ret_missing_required({}, 'op');
  }

  my $op = $req->{op};
  delete($req->{op});
  if(!$self->can($op)) {
    return ce_ret_invalid_value({}, 'op', 'unknown operation');
  }

  $self->$op($req);
}

sub sign_data {
  my($self, $req) = @_;

  if(!exists($req->{data})) {
    return ce_ret_missing_required({}, 'data');
  } elsif(!exists($req->{uuid})) {
    return ce_ret_missing_required({}, 'uuid');
  }
    
  my $auth_ref;
  if(!ce_was_successful(my $ref = $self->{_dbh}->get_authentication_entry($req->{uuid}))) {
    return $ref;
  } else {
    $auth_ref = $ref->{entry};
  }

  my $r = { sig => cloudenabled_sign_data($req->{data}, $auth_ref->{key}) };

  return ce_ret_success($r);
}

sub sign_server_data {
  my($self, $req) = @_;

  if(!exists($req->{data})) {
    return ce_ret_missing_required({}, 'data');
  } elsif(!exists($req->{uuid})) {
    return ce_ret_missing_required({}, 'uuid');
  }
    
  my $srv_ref;
  if(!ce_was_successful(my $ref = $self->{_dbh}->get_server_entry($req->{uuid}))) {
    return $ref;
  } else {
    $srv_ref = $ref->{entry};
  }

  my $r = { sig => cloudenabled_sign_data($req->{data}, $srv_ref->{key}) };

  return ce_ret_success($r);
}


sub validate_signature {
  my($self, $req) = @_;

  if(!defined($req->{uuid})) {
    return ce_ret_missing_required({}, 'uuid');
  } elsif(!defined($req->{exp_sig})) {
    return ce_ret_missing_required({}, 'exp_sig');
  } elsif(!defined($req->{data})) {
    return ce_ret_missing_required({}, 'data');
  }

  my $auth_uuid    = $req->{uuid};
  my $expected_sig = $req->{exp_sig};
  my $data         = $req->{data};
  
  my $auth_ref;
  if(!ce_was_successful(my $ref = $self->{_dbh}->get_authentication_entry($auth_uuid))) {
    return ce_ret_invalid_value({}, 'uuid', 'unknown authentication uuid');
  } else {
    $auth_ref = $ref->{entry};
  }

  my $sig = cloudenabled_sign_data($data, $auth_ref->{key});
  if($sig eq $expected_sig) {
    return ce_ret_success();
  } else {
    return ce_ret_invalid_signature();
  }
}

sub validate_server_signature {
  my($self, $req) = @_;

  if(!defined($req->{uuid})) {
    return ce_ret_missing_required({}, 'uuid');
  } elsif(!defined($req->{exp_sig})) {
    return ce_ret_missing_required({}, 'exp_sig');
  } elsif(!defined($req->{data})) {
    return ce_ret_missing_required({}, 'data');
  }

  my $server_uuid  = $req->{uuid};
  my $expected_sig = $req->{exp_sig};
  my $data         = $req->{data};
  
  my $srv_ref;
  if(!ce_was_successful(my $ref = $self->{_dbh}->get_server_entry($server_uuid))) {
    return ce_ret_not_found();
  } else {
    $srv_ref = $ref->{entry};
  }

  my $sig = cloudenabled_sign_data($data, $srv_ref->{key});
  if($sig eq $expected_sig) {
    return ce_ret_success();
  } else {
    return ce_ret_signature_error();
  }
}


sub list_activities {
  my($self, $req) = @_;

  return $self->{_dbh}->list_activities($req);
}

sub list_tasks {
  my($self,$req) = @_;

  my $id = defined($req->{act_id}) ? $req->{act_id} : undef;
  if(!defined($id)) {
    return ce_ret_missing_required({}, 'act_id');
  }

  my $rsp = $self->{_dbh}->get_activity_entry($req->{act_id});
  if(!ce_was_successful($rsp)) {
    return $rsp;
  }

  return $self->{_dbh}->list_tasks($req->{act_id});
}

sub cancel_activity {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};
  my $act_ret;

  my @accepted_states = ( CE_TASK_ST_WAITING, CE_TASK_ST_STAND_BY );
  if(ce_was_successful(my $ret = $ctldb->get_activity_entry($req->{id}))) {
    $act_ret = $ret->{entry};
  } else {
    return $ret;
  }

  my $valid_state = 0;
  foreach my $st (@accepted_states) {
    if($act_ret->{state} == $st) {
      $valid_state = 1;
      last;
    }
  }

  if(!$valid_state) {
    return ce_ret_permission_denied({}, 'activity is in a state not allowed to be canceled');
  }

  if(ce_was_successful(my $ret = $ctldb->cancel_activity($req->{id}))) {
    return ce_ret_success();
  } else {
    return $ret;
  }

}

sub retry_activity {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};
  my $act_ret;

  my @accepted_states = (  CE_TASK_ST_FAILED, CE_TASK_ST_STAND_BY );

  if(ce_was_successful(my $ret = $ctldb->get_activity_entry($req->{id}))) {
    $act_ret = $ret->{entry};
  } else {
    return $ret;
  }

  my $valid_state = 0;
  foreach my $st (@accepted_states) {
    if($act_ret->{state} == $st) {
      $valid_state = 1;
      last;
    }
  }

  if(!$valid_state) {
    return ce_ret_permission_denied({}, 'activity is in a state not allowed to be retried');
  }
 
  if(ce_was_successful(my $ret = $ctldb->retry_activity($req->{id}))) {
    return ce_ret_success();
  } else {
    return $ret;
  }
}

sub list_hosting_companies {
  my($self) = @_;

  return $self->{_dbh}->list_hosting_companies();
}

sub get_task_status {
  my($self, $req) = @_;

  return $self->{_dbh}->get_task_status($req->{id});
}

sub get_server_info {
  my($self, $req) = @_;

  my $server_uuid = $req->{uuid};

  my $srv_list;
  if(!defined($server_uuid)) {
    return ce_ret_missing_required({}, 'uuid');
  } elsif(ref($server_uuid) eq "ARRAY") {
    $srv_list = $server_uuid;
  } elsif(!ref($server_uuid)) {
    $srv_list = [ $server_uuid ];
  } else {
    return ce_ret_invalid_value({}, 'uuid');
  }

  my @srv_info = ();
  foreach my $uuid (@$srv_list) {
    my $ref = $self->{_dbh}->get_server_entry($uuid);

    if($ref) {
      delete($ref->{entry}->{key}) if(exists($ref->{entry}->{key}));
      push(@srv_info, $ref->{entry});
    }
  }

  return ce_ret_success({ server => \@srv_info });
}

sub update_server_entry {
  my($self, $req) = @_;

  if(exists($req->{key})) {
    return ce_ret_permission_denied({}, 'cannot update the key using this op');
  }

  my $uuid = $req->{uuid};
  $self->{_dbh}->update_server_entry($uuid, $req);
}
  
sub public_key_vhost {
  my($self, $req) = @_;
  my($a_r, $t_r);
  my($add_keys,$del_keys, $key_actions);
  my $ctldb = $self->{_dbh};

  my $op_r = { command_name => 'public_key_vhost' };

  my $da_r = { vhost => $req->{vhost} };

  my $srv_ref;
  if(ce_was_successful(my $vret = $ctldb->get_server_entry($req->{server}))) {
    $srv_ref = $vret->{entry};
    $op_r->{exec_server_id} = $srv_ref->{id};
  } else {
    return $vret;
  }

  if(exists($req->{add_key})) {
    $add_keys = $req->{add_key};
    foreach my $k (@$add_keys) {
      $key_actions .= "+:$k\n";
    }
  }

  if(exists($req->{del_key})) {
    $del_keys = $req->{del_key};
    foreach my $k (@$del_keys) {
      $key_actions .= "-:$k\n";
    }
  }

  $da_r->{stdin_data} = $key_actions;

  if(ce_was_successful(my $vret = &$_assemble_activity($self, { activity_name => 'public_key_vhost' }))) {
    $a_r = $vret->{activity};
  } else {
    return $vret;
  }

  $t_r = &$_assemble_task($self, $op_r, $da_r);
  if(ce_was_successful($t_r)) {
    return &$_create_activity_n_tasks($self, $a_r, [ $t_r->{task} ]);
  } else {
    return $t_r;
  }
}

sub get_pingback_url {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};
  my $srv_ref;

  if(!ce_was_successful(my $ret = $ctldb->get_authentication_entry($req->{uuid}))) {
    return $ret;
  } else {
    $srv_ref = $ret->{entry};
  }

  return ce_ret_success( { url => $srv_ref->{pingback_url} } );
}

sub set_pingback_url {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};
  my $srv_ref;

  if(!ce_was_successful(my $ret = $ctldb->get_authentication_entry($req->{uuid}))) {
    return $ret;
  } else {
    $srv_ref = $ret->{entry};
  }

  my $entry = { uuid => $req->{uuid}, pingback_url => $req->{pingback_url} };

  return $ctldb->update_authentication_entry($entry);
}

sub ping {
  return ce_ret_success({ op => 'pong' });
}

sub list2run {
  my($self, $req) = @_;

  my $ret = $self->{_dbh}->list2run($req);
  if(!ce_was_successful($ret)) {
    return $ret;
  }

  return ce_ret_success({ task_data => $ret->{tasks} });
}

sub create_server_session {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};

  my $ret = $ctldb->get_server_entry($req->{uuid});
  if(!ce_was_successful($ret)) {
    return $ret;
  }
  my $srv_ref = $ret->{entry};

  return $ctldb->create_server_session({
    server_id  => $srv_ref->{id},
    ip_address => $req->{ip_address},
  });
}

sub get_active_server_session {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};

  my $ret = $ctldb->get_server_entry($req->{uuid});
  if(!ce_was_successful($ret)) {
    return $ret;
  }
  my $srv_ref = $ret->{entry};

  return $ctldb->get_active_server_session(
                              { server_id  => $srv_ref->{id} });
}

sub close_server_session {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};

  my $ret = $ctldb->get_server_entry($req->{uuid});
  if(!ce_was_successful($ret)) {
    return $ret;
  }
  my $srv_ref = $ret->{entry};

  return $ctldb->close_server_session({ id => $req->{session_id}, server_id  => $srv_ref->{id} });
}

sub update_last_vps_checkin {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};

  return $ctldb->update_last_vps_checkin({
                          server_id  => $req->{server_id},
                          session_id => $req->{session_id},
                        });
}

sub get_active_server_session_byid {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};

  return $ctldb->get_active_server_session_byid($req->{id});
}

sub get_cmd_defs {
  my($self, $req) = @_;

  my $ctldb = $self->{_dbh};

  return $ctldb->get_cmd_defs($req->{id});
}

sub set_running {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};

  my $vps_id     = $req->{server_id};
  my $act_task_r = {};
  my $ret;
  foreach my $task_id (@{ $req->{task_id} }) {
    if(!ce_was_successful($ret = $ctldb->get_task_entry({
                                          exec_server_id => $vps_id,
                                          id   => $task_id,
                                          }))) {
      return $ret;
    } else {
      $act_task_r->{$task_id} = $ret->{entry}->{activity_id};
    }
  }
  
  return $ctldb->set_running({ task_id      => $req->{task_id},
                               activity_map => $act_task_r,
                             });
}

sub get_activity_entry {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};

  return $ctldb->get_activity_entry($req->{id});
}

sub get_task_entry {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};

  return $ctldb->get_task_entry($req);
}

sub task_report {
  my($self, $req) = @_;

  my $ctldb = $self->{_dbh};

  my $task_ref = $self->get_task_entry({
                            'id' => $req->{task_id},
                            'exec_server_id' => $req->{server_id}
  });

  if(!ce_was_successful($task_ref)) {
    return $task_ref;
  }

  $req->{task_ref} = $task_ref->{entry};

  my $rsp = $ctldb->task_report($req);
  if(ce_was_successful($rsp) && $rsp->{do_pingback}) {
    my $task_ref = $req->{task_ref};
    $rsp->{activity_id} = $task_ref->{activity_id};
    $rsp->{state}       = $req->{ret} == 0 ? CE_TASK_ST_COMPLETED : 
                                             CE_TASK_ST_FAILED    ;

    if($task_ref->{flags} & CE_TASK_FL_SEND_OUTPUT) {
      $rsp->{output} = $req->{output};
    }
  }
  undef($req);

  return $rsp;
}

sub create_server {
  my($self, $req) = @_;

  my $ctldb = $self->{_dbh};

  if(ce_was_successful($ctldb->get_server_entry_raw(
        { uuid => $req->{uuid} }))) {
    return ce_ret_invalid_value({}, 'uuid', 'uuid already exists');
  } elsif(ce_was_successful($ctldb->get_server_entry_raw(
        { hostname => $req->{hostname} }))) {
    return ce_ret_invalid_value({}, 'hostname', 'hostname already exists');
  }

  $req->{vps_key} = ce_gen_random_str();

  my $ret = &$_assemble_activity($self, {
      activity_name => 'create_server',
      dashboard_act_id => exists($req->{dashboard_act_id}) ?
                                 $req->{dashboard_act_id} : 0
  });
  my $activity_r = $ret->{activity};

  my $rsp;
  if(!ce_was_successful($rsp = $ctldb->create_server($req))) {
    return $rsp;
  }
    
  my $server_id = $rsp->{server_id};

  my $install_software = exists($req->{install_software}) &&
                          $req->{install_software} ? 1 : 0;

  my @tasks = ();
  if($install_software) {
    my $root_user = $req->{root_user};
    my $root_pw   = $req->{root_pw};

    push(@tasks, &$_assemble_task($self, {
                                     command_name   => 'send_bootstrap_ssh',
                                     exec_server_id => $req->{internal_exec_server},
                                     flags          => CE_TASK_FL_READ_STDIN,
                                     state          => CE_TASK_ST_WAITING_PARENT
                                   },                                        
        
              {
                ssh_username   => $root_user,
                ssh_host       => $req->{ip_address},
                stdin_data     => $root_pw . "\n",
                vps_uuid       => $req->{uuid},
                vps_key        => $req->{vps_key},
                api_url        => $req->{tasks_api_url},
                bootstrap_file => $req->{bootstrap_file},
      })->{task}
    );
  }

  $rsp = $ctldb->create_activity_n_tasks($activity_r, \@tasks);
  if(!ce_was_successful($rsp)) {
    return $rsp;
  }

  my $ret_r = {
    vps_uuid   => $req->{uuid},
    secret_key => $req->{vps_key},
  };

  if(!$install_software && 
    ce_was_successful(my $token_r = &$_create_install_token($self, $server_id))) {
    $ret_r->{install_token} = $token_r->{token_str};
  } # don't care about errors in the token

  return ce_ret_success($ret_r);
}

sub server_reboot {
  my($self, $req) = @_;

  my $ctldb = $self->{_dbh};

  my $ret = &$_assemble_activity($self, { activity_name => 'server_reboot' });
  if(!ce_was_successful($ret)) {
    return ce_ret_internal_error({});
  }
  my $a_r = $ret->{activity};

  $ret = $ctldb->get_server_entry($req->{uuid});
  if(!ce_was_successful($ret)) {
    return $ret;
  }
  my $srv_ref = $ret->{entry};

  $ret = &$_assemble_task($self, {
                              command_name   => 'server_reboot',
                              exec_server_id => $srv_ref->{id},
                            },
                            { }

  );

  my @tasks = ( $ret->{task} );


  return $ctldb->create_activity_n_tasks($a_r, \@tasks);
}

sub get_activity_report {
  my($self, $req) = @_;
  my $ctldb = $self->{_dbh};

  return $ctldb->get_activity_report($req);
}

sub get_install_info {
  my($self, $req) = @_;

  my $ctldb = $self->{_dbh};

  my $token_r = $ctldb->get_install_token_entry(
    { token_str => $req->{token_str} }
  );
  if(!ce_was_successful($token_r)) {
    return $token_r;
  }

  my $srv_r = $ctldb->get_server_entry($token_r->{entry}->{server_id});
  if(!ce_was_successful($srv_r)) {
    return $srv_r;
  }

  my $ret_r = {
    uuid       => $srv_r->{entry}->{uuid},
    secret_key => $srv_r->{entry}->{key},
  };

  return ce_ret_success($ret_r);
}

1;
