package Cloudenabled::Controller::Database::DBI;
use strict;
use warnings;
use Cloudenabled::Constants;
use Cloudenabled::Controller::Constants;
use Cloudenabled::Util;
use DBI (qw( :sql_types ));

our $debug = 1;

sub new {
  my($class, @params) = @_;
  my $self = {};

  if(!@params) {
    warn __PACKAGE__, " constructor didn't receive any parameter";
    return undef;
  }

  my($db_type, $db_url, $db_user, $db_pass, $db_opts);

  for(my $i=0; $i < $#params; $i++) {
    my $key = $params[$i];
    my $val = $params[++$i];

    if($key eq 'db_url') {
      $db_url = $val;
    } elsif($key eq 'db_user') {
      $db_user = $val;
    } elsif($key eq 'db_pass') {
      $db_pass = $val;
    } elsif($key eq 'db_opts') {
      $db_opts = $val;
    }
  }

  if(!defined($db_url)) {
    warn "Error: missing parameter db_url";
    return 0;
  }

  $db_user = defined($db_user) ? $db_user : '';
  $db_pass = defined($db_pass) ? $db_pass : '';
  $db_opts = defined($db_opts) && ref($db_opts) eq 'HASH' ? $db_opts : {};

  my $dbh = eval { DBI->connect($db_url, $db_user, $db_pass, $db_opts); };
  if(!$dbh) {
    warn __PACKAGE__, " - unable to connect to database:\n$@";
    return 0;
  }
  $self->{_dbh}     = $dbh;
  ($self->{_db_type} = __PACKAGE__) =~ s/^.+:://;

  $self->{__skip_commit} = 0;

  bless($self);
  return $self;
}

# private method, not exposed to external modules
my $_get_row = sub {
  my($dbh, $table, $params) = @_;

  my @bind_values;
  my $sql = "SELECT * FROM $table";
  my $row;

  my @fields = ();
  foreach my $p (keys %$params) {
    push(@fields, "$p = ?");
    push(@bind_values, $params->{$p});
  }

  if($#fields >= 0) {
    $sql .= " WHERE " . join(' AND ', @fields);
  }

  $row = $dbh->selectrow_hashref($sql, {}, @bind_values);
  if($dbh->err) {
    warn __PACKAGE__, ' - _get_row(): ', $dbh->errstr;
    return 0;
  } else {
    return $row;
  }
};

my $_get_entry_n_return = sub {
  my($dbh, $table, $info) = @_;

  my $ref = &$_get_row($dbh, $table, $info);

  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  } elsif(!$ref) {
    return ce_ret_not_found();
  } else {
    return ce_ret_success({ entry => $ref });
  }
};

sub get_activity_name_entry {
  my($self, $name) = @_;
  my $dbh = $self->{_dbh};

  return &$_get_entry_n_return($dbh, 'Activity_Names', { name => $name });
}

sub get_command_entry {
  my($self, $name) = @_;
  my $dbh = $self->{_dbh};

  return &$_get_entry_n_return($dbh, 'Commands', { name => $name });
}

sub get_command_name {
  my($self, $id) = @_;
  my $dbh = $self->{_dbh};

  return &$_get_entry_n_return($dbh, 'Commands', { id => $id });
}

sub create_activity {
  my($self, $op_info) = @_;
  my @opts_avail = ();

  my $dbh      = $self->{_dbh};

  my %columns = (
    'name_id'          => SQL_INTEGER,
    'state'            => SQL_INTEGER,
    'priority'         => SQL_INTEGER,
    'flags'            => SQL_INTEGER,
    'dashboard_act_id' => SQL_VARCHAR
  );

  foreach my $k (keys %columns) {
    if(exists($op_info->{$k})) {
      push(@opts_avail, $k);
    }
  }

  my $sql_insrt = sprintf('INSERT INTO Activities(%s) VALUES(%s)', 
                          join(',', @opts_avail), join(',', ('?') x ($#opts_avail + 1) ));
  $debug and warn sprintf("%s: %s: %s\n", __PACKAGE__, 'create_activity()', $sql_insrt);

  my $sth = $dbh->prepare($sql_insrt);
  for(my $i=0; $i <= $#opts_avail; $i++) {
    my $col = $opts_avail[$i];
    $sth->bind_param($i+1, $op_info->{$col}, $columns{$col});
    $debug and warn sprintf("%s: %s: binding col = %s, val = %s\n",
                              __PACKAGE__, 'create_activity():', $col, $op_info->{$col});
  }

  $sth->execute();
  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  } else {
    return ce_ret_success({ activity_id => $dbh->last_insert_id(undef, undef, undef, undef) });
  }
}

sub create_task {
  my($self, $op_info) = @_;

  my $dbh      = $self->{_dbh};

  if(!$self->{__skip_commit}) {
    $dbh->begin_work();
  }

  my %columns = (
    'command_id'     => SQL_INTEGER,
    'exec_server_id' => SQL_INTEGER,
    'flags'          => SQL_INTEGER,
    'activity_id'    => SQL_VARCHAR,
    'input_data'     => SQL_VARCHAR
  );

  my @opts_avail = ();

  foreach my $k (keys %columns) {
    if(exists($op_info->{$k})) {
      push(@opts_avail, $k);
    }
  }

  my $sql_insrt = sprintf('INSERT INTO Tasks(%s) VALUES(%s)', join(',', @opts_avail), join(',', ('?') x ($#opts_avail + 1) ));
  $debug and warn sprintf("%s: %s: %s\n", __PACKAGE__, 'create_task()', $sql_insrt);

  my $sth = $dbh->prepare($sql_insrt);
  for(my $i=0; $i <= $#opts_avail; $i++) {
    my $col = $opts_avail[$i];
    $sth->bind_param($i+1, $op_info->{$col}, $columns{$col});
    $debug and warn sprintf("%s: %s: binding col = %s, val = %s\n",
                              __PACKAGE__, 'create_task()', $col, $op_info->{$col});
  }

  my $status = $sth->execute();
  if($sth->err) {
    $dbh->rollback() if(!$self->{__skip_commit});
    return ce_ret_internal_error({}, $sth->errstr);
  }

  my $task_id = $dbh->last_insert_id(undef, undef, undef, undef);

  my $attempt_insrt = "INSERT INTO Task_Attempts(task_id, state) VALUES (?, ?)";
  if(!$dbh->do($attempt_insrt, {}, $task_id, $op_info->{state})) {
    $dbh->rollback() if(!$self->{__skip_commit});
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  my $attempt_id = $dbh->last_insert_id(undef, undef, undef, undef);
  my $upd_task   = "UPDATE Tasks SET last_attempt_id = ? WHERE id = ?";
  if($dbh->do($upd_task, {}, $attempt_id, $task_id)) {
    $dbh->commit() if(!$self->{__skip_commit});
    return ce_ret_success({ task_id => $task_id, attempt_id => $attempt_id });
  } else {
    $dbh->rollback() if(!$self->{__skip_commit});
    return ce_ret_internal_error({}, $dbh->errstr);
  }

}

sub create_activity_n_tasks {
  my($self, $act_ref, $tasks_ref) = @_;

  my $dbh = $self->{_dbh};

  $self->{__skip_commit} = 1;
  $dbh->begin_work(); # start transaction

  my $global_ret = {};
  if(!ce_was_successful(my $ret = $self->create_activity($act_ref))) {
    $dbh->rollback();
    return $ret;
  } else {
    $global_ret->{activity_id} = $ret->{activity_id};
    $global_ret->{task_ids}     = [];
  }

  foreach my $t_r (@$tasks_ref) {
    $t_r->{activity_id} = $global_ret->{activity_id};
    if(!ce_was_successful(my $ret = $self->create_task($t_r))) {
      $dbh->rollback();
      return $ret;
    } else {
      push(@{ $global_ret->{task_ids} }, $ret->{task_id});
    }
  }

  $self->{__skip_commit} = 0;

  if($dbh->commit()) {
    return ce_ret_success($global_ret);
  } elsif($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }

}

sub get_server_entry {
  my($self, $id) = @_;
  my $dbh = $self->{_dbh};

  my $p;
  if(!defined($id) || ref($id)) {
    return ce_ret_local_error({}, 'get_server_entry: invalid format of id (1)'); # invalid format
  } elsif($id =~ /^\d+$/) {
    $p = 'id';
  } elsif($id =~ /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/) {
    $p = 'uuid';
  } else {
    return ce_ret_format_error({}, 'uuid'); # invalid format 2
  }

  my $sql_srv = "SELECT Srv.*,Sess.ip_address last_ip, Sess.taskd_version,
                 IFNULL(strftime('%s', Sess.last_checkin), 0) last_checkin_epoch
                 FROM Servers Srv LEFT JOIN Sessions Sess ON 
                 Srv.id = Sess.server_id WHERE Srv.$p = ?";

  my $sth = $dbh->prepare($sql_srv);
  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  }

  $sth->bind_param(1, $id);
  $sth->execute();
  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  }

  return ce_ret_success({ entry => $sth->fetchrow_hashref() });
}

sub get_activity_entry {
  my($self, $id) = @_;
  my $dbh = $self->{_dbh};

  return &$_get_entry_n_return($dbh, 'Activities', { id => $id });
}

sub get_task_entry {
  my($self, $params_r) = @_;
  my $dbh = $self->{_dbh};

  return &$_get_entry_n_return($dbh, 'Tasks', $params_r);
}

sub get_task_status {
  my($self, $id) = @_;

  my $sql_items = "SELECT T.id, T.activity_id, TA.state, TA.return_code, TA.output,
                    TA.start_time, TA.end_time, TA.exec_time, S.hostname
                    FROM Tasks T, Task_Attempts TA, Servers S WHERE T.id = ? 
                    AND T.last_attempt_id = TA.id AND T.exec_server_id = S.id";

  my $dbh = $self->{_dbh};
  my $sth = $dbh->prepare($sql_items);

  $sth->bind_param(1, $id, SQL_INTEGER);

  my $items;
  my $ret;
  $sth->execute();

  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  }

  my $task = $sth->fetchrow_hashref();
  if(!$task) {
    return ce_ret_not_found();
  }

  return ce_ret_success({ task_data => [ $task ] });
}

my $update_table_entry = sub {
  my($dbh, $table, $entry_key, $params) = @_;

  if(scalar(keys(%$params)) <= 1) {
    warn __PACKAGE__, ": update_table_entry - error: insuficient number of parameters passed";
    return 0;
  }

  if(!exists($params->{$entry_key})) {
    warn __PACKAGE__, ": update_table_entry - error: missing key value";
    return 0;
  }

  my $sql_fmt = "UPDATE $table SET %s WHERE $entry_key = :$entry_key";

  my $entry_value = $params->{$entry_key};
  delete($params->{$entry_key});

  my $param_exp = '';

  my @keys = keys(%$params);
  for(my $i=0; $i <= $#keys; $i++) {
    my $key = $keys[$i];

    $param_exp .= "$key = :$key";
    if($i != $#keys) {
      $param_exp .= ', ';
    }
  }

  my $sql = sprintf($sql_fmt, $param_exp);
  $debug and warn __PACKAGE__, ' - ', 'update_table_entry(): ', "sql = $sql\n";

  my $sth = $dbh->prepare($sql);
  if(!$sth || $sth->err) {
    return 0;
  }

  foreach my $k (@keys) {
    $sth->bind_param(":$k", $params->{$k});
  }
  $sth->bind_param(":$entry_key", $entry_value);
  $sth->execute();

  if(!$sth->err) {
    return ce_ret_success();
  } else {
    warn __PACKAGE__, " - update_table_entry(): ", $sth->errstr;
    return ce_ret_internal_error({}, $sth->errstr);
  }
};

sub update_activity_entry {
  my($self, $params) = @_;
  my $dbh = $self->{_dbh};

  if(ce_was_success(my $ret = &$update_table_entry($dbh, 'Activities', 'id', $params))) {
    return ce_ret_success();
  } else {
    return $ret;
  }
}

sub update_server_entry {
  my($self, $uuid, $params) = @_;
  my $dbh = $self->{_dbh};

  if(&$update_table_entry($dbh, 'Servers', 'uuid', $params)) {
    return ce_ret_success({});
  } else {
    return ce_ret_internal_error({});
  }
}

sub create_server {
  my($self, $req) = @_;

  my $dbh = $self->{_dbh};

  my $sql = "INSERT INTO Servers(uuid, key, hostname, hosting_company_id) VALUES (?, ?, ?, ?)";
  my $vps_uuid   = $req->{uuid};
  my $vps_key    = $req->{vps_key};
  my $hn         = $req->{hostname};
  my $hid        = $req->{hosting_company_id};

  $dbh->do($sql, {}, $vps_uuid, $vps_key, $hn, $hid);
  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }
  my $server_id = $dbh->last_insert_id(undef, undef, undef, undef);

  return ce_ret_success({ server_id => $server_id });
}

sub list_hosting_companies {
  my($self) = @_;
  my $dbh = $self->{_dbh};

  my $sql_items = "SELECT * FROM Hosting_Companies";
  my $h_ref = $dbh->selectall_arrayref($sql_items, { Slice => {} });

  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  return ce_ret_success({ hosting_companies => $h_ref });
}

sub list_activities {
  my($self,$req) = @_;
  my $dbh = $self->{_dbh};

  # the list of activities is explicitly entered
  my $p;
  if(exists($req->{id})) {
    $p = 'id';
  } elsif(exists($req->{dashboard_act_id})) {
    $p = 'dashboard_act_id';
  }

  my($n, @cond_str, @cond_columns, @cond_values, @v, $cpl, $inn);
  if(defined($p) && ref($req->{$p}) eq 'ARRAY') {
    @v = @{ $req->{$p} };
  } elsif(defined($p)) {
    @v = ($req->{$p});
  }

  if(@v) {
    $inn = join(',', @v);
    push(@cond_str, "A.$p IN ($inn)");

    # $cpl = "A.$p IN($inn) AND";
  }

  # SQL query used to list activities
  my $sql_tmpl = "SELECT A.*,AN.name,COUNT(*) AS n_tasks FROM Activities A,
                  Tasks T, Activity_Names AN WHERE A.id = T.activity_id 
                  AND A.name_id = AN.id %s GROUP BY A.id %s";

  my $suplement   = ' ';
  if(exists($req->{reverse})) {
    $suplement .= ' ORDER BY A.id DESC';
  }

  my %opt_types = (
    'id' => SQL_INTEGER,
    'dashboard_act_id' => SQL_VARCHAR,
    'after_id' => SQL_INTEGER,
  );

  if(exists($req->{after_id})) {
    push(@cond_str, "A.id > ?");
    push(@cond_columns, 'after_id');
    push(@cond_values, $req->{after_id});
  }

  if(exists($req->{limit})) {
    $suplement .= " LIMIT " . $req->{limit};
  } else {
    $suplement .= " LIMIT -1 ";
  }

  if(exists($req->{offset})) {
    $suplement  .= " OFFSET " . $req->{offset};
  }

  my $sql_count = "SELECT COUNT(*) n FROM Activities A ";
  if(@cond_str) {
    $sql_count .= " WHERE " . join(" AND ", @cond_str);
  }

  $debug and warn __PACKAGE__, ' list_activities(): ', "sql_count = $sql_count\n";

  my $c_sth = $dbh->prepare($sql_count);
  for(my $i=0; $i <= $#cond_columns; $i++) {
    $c_sth->bind_param($i+1, $cond_values[$i], $opt_types{$cond_columns[$i]});
    warn sprintf("col = %s, val = %s\n", $cond_columns[$i], $cond_values[$i]);
  }
  $c_sth->execute();
  $n = $c_sth->fetchrow_hashref()->{n};


  my $cond_str = ' ';
  if(@cond_str) {
    $cond_str .= " AND " . join(" AND ", @cond_str);
  }
  my $sql_items = sprintf($sql_tmpl, $cond_str, $suplement);

  my $sth = $dbh->prepare($sql_items);
  if(!$sth) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }
  $debug and warn __PACKAGE__, ' list_activities(): ', " sql = ", $sql_items, "\n";

  my $items;
  my $ret;

  for(my $i=0; $i <= $#cond_columns; $i++) {
    $sth->bind_param($i+1, $cond_values[$i], $opt_types{$cond_columns[$i]});
    warn __PACKAGE__, ' list_activities(): ', sprintf("col = %s, val = %s\n", $cond_columns[$i], $cond_values[$i]);
  }
  $sth->execute();

  undef(@cond_columns); # trying to avoid memleaks (1)
  undef(@cond_values);  # (2)
  undef(@cond_str);

  if(!$sth->err) {
    return ce_ret_success({ activity_count => $n , activities => $sth->fetchall_arrayref({ }) });
  } else {
    return ce_ret_internal_error({}, $sth->errstr);
  }
}

sub cancel_activity {
  my($self, $id) = @_;
  my $dbh = $self->{_dbh};

  $dbh->begin_work;

  my $sql_upd_act = "UPDATE Activities SET state = ? WHERE id = ?";

  my $sql_list_ats = "SELECT TA.* FROM Tasks T, Task_Attempts TA WHERE
                      T.activity_id = ? AND T.id = TA.task_id AND
                      T.last_attempt_id = TA.id";

  my $sql_upd_ats = "UPDATE Task_Attempts SET state = ? WHERE id = ?";

  my $ta_refs = $dbh->selectall_arrayref($sql_list_ats, { Slice => {} }, $id);
  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  } elsif(!$ta_refs) {
    return ce_ret_internal_error({}, 'activity has no tasks');
  }

  foreach my $t_r (@$ta_refs) {
    if($t_r->{state} == CE_TASK_ST_COMPLETED || $t_r->{state} == CE_TASK_ST_FAILED) {
      next; # let's skip completed or failed tasks
    }
    $dbh->do($sql_upd_ats, {}, CE_TASK_ST_CANCELED, $t_r->{id});
    if($dbh->err) {
      $dbh->rollback();
      return ce_ret_internal_error({}, $dbh->errstr);
    }
  }

  $dbh->do($sql_upd_act, {}, CE_TASK_ST_CANCELED, $id);
  if($dbh->err) {
    $dbh->rollback();
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  if($dbh->commit()) {
    return ce_ret_success();
  } else {
    return ce_ret_internal_error({}, $dbh->errstr);
  }
}

sub list_tasks {
  my($self, $id) = @_;
  my $dbh = $self->{_dbh};

  my $sql_items = "SELECT T.id, T.activity_id, T.command_id, T.exec_server_id,
                    TA.state, TA.return_code, TA.output, TA.start_time, TA.end_time,
                    TA.exec_time, TA.created_on, TA.last_update,
                    COUNT(*) AS n_attempts,
                    C.name AS command_name, S.uuid AS server_uuid
                    FROM Activities A, Tasks T, Task_Attempts TA, Commands C,
                         Servers S
                    WHERE A.id = ?  AND A.id = T.activity_id AND T.id = TA.task_id
                    AND T.command_id = C.id AND S.id = T.exec_server_id
                    GROUP BY T.id";

  my $sth = $dbh->prepare($sql_items);
  $sth->execute($id);
  if(!$sth->err) {
    return ce_ret_success({ tasks => $sth->fetchall_arrayref({ }) });
  } elsif($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  }
}

sub get_authentication_entry {
  my($self, $id) = @_;
  my $dbh = $self->{_dbh};

  return &$_get_entry_n_return($dbh, 'Authentication', { uuid => $id });
}

sub update_authentication_entry {
  my($self, $params) = @_;
  my $dbh = $self->{_dbh};

  if(&$update_table_entry($dbh, 'Authentication', 'uuid', $params)) {
    return ce_ret_success({});
  } else {
    return ce_ret_internal_error({});
  }
}

sub retry_activity {
  my($self, $id) = @_;
  my $dbh = $self->{_dbh};

  my @accepted_states = ( CE_TASK_ST_FAILED,   CE_TASK_ST_CANCELED,
                          CE_TASK_ST_STAND_BY, CE_TASK_ST_PARENT_FAILED );

  my $sql_tasks = "SELECT T.id, TA.id at_id, T.flags FROM Tasks T, Task_Attempts TA
                   WHERE T.activity_id = ? AND T.last_attempt_id = TA.id AND
                   TA.state IN (?, ?, ?, ?)";

  my $tasks_ret;
  my $sth = $dbh->prepare($sql_tasks);
  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  $sth->bind_param(1, $id, SQL_INTEGER);

  for(my $i=0; $i <= $#accepted_states; $i++) {
    $sth->bind_param($i+2, $accepted_states[$i], SQL_INTEGER);
  }
  $sth->execute();

  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  }

  my $tasks = $sth->fetchall_arrayref({});
  if($#{ $tasks } == -1) {
    return ce_ret_nothing_updated({}, 'No tasks to be retried');
  }
  # $debug and warn __PACKAGE__, ' - ', Dumper($tasks), "\n";

  my $sql_act = "UPDATE Activities SET state = ? WHERE id = ?";
  my $sql_tsk = "UPDATE Tasks SET last_attempt_id = ? WHERE id = ?";
  my $sql_ta  = "INSERT INTO Task_Attempts(task_id, flags) VALUES(?, ?)";

  my $sth_tsk  = $dbh->prepare($sql_tsk);
  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  my $sth_ta   = $dbh->prepare($sql_ta);
  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  $dbh->begin_work;
  $dbh->do($sql_act, {}, CE_TASK_ST_WAITING, $id);
  foreach my $t (@$tasks) {
    # add a new task attempt
    $dbh->do($sql_ta, {}, $t->{id}, $t->{flags});

    # update the Tasks table with the id of the new attempt
    my $ta_id = $dbh->sqlite_last_insert_rowid();
    $debug and warn __PACKAGE__, ' - ', "ta_id = $ta_id, task = " . $t->{id};
    $dbh->do($sql_tsk, {}, $ta_id, $t->{id});
  }

  $dbh->commit();
  if($dbh->err) {
    $dbh->rollback();
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  return ce_ret_success();
}

sub list2run {
  my($self, $req) = @_;
  my $dbh = $self->{_dbh};

  my $sql_items = "SELECT T.id,T.activity_id,T.flags,T.command_id,
                  T.exec_server_id,T.last_attempt_id,T.input_data
                  FROM Activities A, Tasks T, Task_Attempts TA
                  WHERE T.exec_server_id = ? AND T.last_attempt_id = TA.id
                  AND TA.state = ? AND T.activity_id = A.id
                  ORDER BY A.priority DESC, T.activity_id, T.id";

  if(exists($req->{max}) && $req->{max} =~ /^\d+$/ && $req->{max} > 0) {
    $sql_items .= ' LIMIT ' . $req->{max};
  }

  my $items = $dbh->selectall_arrayref($sql_items, { Slice => {} },
                                  $req->{server_id}, CE_TASK_ST_WAITING);

  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  return ce_ret_success({ tasks => $items });
}

sub get_cmd_defs {
  my($self, $ids) = @_;
  my $dbh = $self->{_dbh};

  my $in = join(',', ('?') x ($#{$ids} + 1));

  my $sql_cmd = "SELECT id,cmd_env,cmd_path,cmd_args,
                 IFNULL(strftime('%s', last_update), 0) last_update
                 FROM Commands WHERE id IN ($in)";

  my $sth = $dbh->prepare($sql_cmd);
  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  for(my $i=0; $i <= $#{$ids}; $i++) {
    $sth->bind_param($i+1, $ids->[$i], SQL_INTEGER);
  }

  $sth->execute();
  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  }

  return ce_ret_success({ cmd_defs => $sth->fetchall_hashref('id') });
}

sub create_server_session {
  my($self, $req) = @_;
  my $dbh = $self->{_dbh};

  my $sql_insrt = "INSERT INTO Sessions(server_id, ip_address) VALUES(?,?)";
  $dbh->do($sql_insrt, {}, $req->{server_id}, $req->{ip_address});
  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  my $sess_id = $dbh->sqlite_last_insert_rowid();
  return ce_ret_success({ id => $sess_id });
}

sub get_active_server_session {
  my($self, $req) = @_;
  my $dbh = $self->{_dbh};

  my $sql_sess = "SELECT Ss.id, Ss.server_id, Sv.uuid server_uuid,
  IFNULL(strftime('%s', Ss.started_on), 0) started_on,
  IFNULL(strftime('%s', Ss.ended_on), 0) ended_on,
  IFNULL(strftime('%s', Ss.last_checkin), 0) last_checkin,
  Ss.ip_address, Ss.flags
  FROM Sessions Ss, Servers Sv WHERE
  Ss.server_id = ? AND Ss.flags & ? = 0 AND Ss.server_id = Sv.id";

  my $sth = $dbh->prepare($sql_sess);
  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  }

  $sth->bind_param(1, $req->{server_id},    SQL_INTEGER);
  $sth->bind_param(2, CE_FL_SESSION_CLOSED, SQL_INTEGER);

  $sth->execute();
  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  }

  my $entry = $sth->fetchrow_hashref();
  if(!$entry) {
    return ce_ret_not_found({});
  }

  return ce_ret_success({ entry => $entry });
}

sub get_active_server_session_byid {
  my($self, $id) = @_;
  my $dbh = $self->{_dbh};

  my $sql_sess = "SELECT Ss.id, Ss.server_id, Sv.uuid server_uuid,
  IFNULL(strftime('%s', Ss.started_on), 0) started_on,
  IFNULL(strftime('%s', Ss.ended_on), 0) ended_on,
  IFNULL(strftime('%s', Ss.last_checkin), 0) last_checkin,
  Ss.ip_address, Ss.flags
  FROM Sessions Ss, Servers Sv WHERE
  Ss.id = ? AND Ss.flags & ? = 0 AND Ss.server_id = Sv.id";

  my $sth = $dbh->prepare($sql_sess);
  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  }

  $sth->bind_param(1, $id, SQL_INTEGER);
  $sth->bind_param(2, CE_FL_SESSION_CLOSED, SQL_INTEGER);

  $sth->execute();
  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  }

  my $entry = $sth->fetchrow_hashref();
  if(!$entry) {
    return ce_ret_not_found({});
  }

  return ce_ret_success({ entry => $entry });
}

sub close_server_session {
  my($self, $req) = @_;
  my $dbh = $self->{_dbh};
  # my $sql_sess = "SELECT * FROM Sessions WHERE id = ? AND server_id = ?";
  # my $sess_ref = $dbh->selectrow_hashref($sql_sess, $req->{session_id}, $req->{server_id});
  # if($dbh->err) {
  #   return ce_ret_internal_error({}, $dbh->errstr);
  # }

  # if($sess_ref->{flags} & CE_FL_SESSION_CLOSED) {
  # return ce_ret_nothing_updated();

  my $sql_close = "UPDATE Sessions SET flags = (flags | ?),
                  ended_on = CURRENT_TIMESTAMP WHERE id = ? AND server_id = ?";
  my $sth = $dbh->prepare($sql_close);
  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  }

  $sth->bind_param(1, CE_FL_SESSION_CLOSED, SQL_INTEGER);
  $sth->bind_param(2, $req->{id}, SQL_INTEGER);
  $sth->bind_param(3, $req->{server_id}, SQL_INTEGER);

  $sth->execute();
  if($sth->err) {
    return ce_ret_internal_error({}, $sth->errstr);
  } else {
    return ce_ret_success();
  }
}

sub update_last_vps_checkin {
  my($self, $req) = @_;
  my $dbh = $self->{_dbh};

  my $sql_upd = "UPDATE Sessions SET last_checkin = CURRENT_TIMESTAMP WHERE
                 id = ? AND server_id = ?";

  $dbh->do($sql_upd, {}, $req->{session_id}, $req->{server_id});
  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  return ce_ret_success();
}

sub set_running {
  my($self, $req) = @_;
  my $dbh = $self->{_dbh};

  my $sql_upd = "UPDATE Task_Attempts SET start_time = CURRENT_TIMESTAMP, state = ? WHERE task_id = ? AND state = ?";

  $dbh->begin_work();
  my $sth = $dbh->prepare($sql_upd);

  foreach my $task_id (@{ $req->{task_id} }) {
    $sth->bind_param(1, CE_TASK_ST_RUNNING, SQL_INTEGER);
    $sth->bind_param(2, $task_id, SQL_INTEGER);
    $sth->bind_param(3, CE_TASK_ST_WAITING , SQL_INTEGER);

    $sth->execute();
    if($sth->err) {
      $dbh->rollback();
      return ce_ret_internal_error({}, $sth->errstr);
    }

    my $sql_act = "UPDATE Activities SET state = ? WHERE id = ?";
    $dbh->do($sql_act, {}, CE_TASK_ST_RUNNING,
                               $req->{activity_map}->{$task_id});
    if($dbh->err) {
      $dbh->rollback();
      return ce_ret_internal_error({}, $dbh->errstr);
    }
  }

  $dbh->commit();

  return ce_ret_success();
}

sub task_report {
  my($self,$req) = @_;

  my $dbh = $self->{_dbh};

  my $tid       = $req->{id};
  my $ret       = $req->{ret};
  my $output    = $req->{output};
  my $server_id = $req->{server_id};
  my $end_time  = exists($req->{end_time}) ?  $req->{end_time} : time();

  my $do_pingback = 0;

  my $task_ref = $req->{task_ref};

  my $sql = "UPDATE Task_Attempts SET state = ?, return_code = ?, output = ?,
              end_time = CURRENT_TIMESTAMP WHERE id = ?";

  $dbh->begin_work();
  my $sth = $dbh->prepare($sql);

  my $state = $ret == 0 ? CE_TASK_ST_COMPLETED : CE_TASK_ST_FAILED;

  $sth->bind_param(1, $state,       SQL_INTEGER);
  $sth->bind_param(2, $ret,         SQL_INTEGER);
  $sth->bind_param(3, $output,      SQL_VARCHAR);
  $sth->bind_param(4, $task_ref->{last_attempt_id}, SQL_INTEGER);

  # update the current attempt with the state returned
  $sth->execute();
  if($sth->err) {
    goto REPORT_INTERNAL_ERROR;
  }

  # check if there are more tasks for the current activity
  my $sql_tasks_left = "SELECT TA.* FROM Tasks T, Task_Attempts TA WHERE
                        T.activity_id = ? AND TA.id = T.last_attempt_id
                        AND TA.state = ? ORDER BY T.id ASC";

  my $tl_ref = $dbh->selectall_arrayref($sql_tasks_left, { Slice => {} },
                                        $task_ref->{activity_id},
                                        CE_TASK_ST_WAITING_PARENT);
  if($dbh->err) {
    goto REPORT_INTERNAL_ERROR;
  }

  my $sql_upd_act  = "UPDATE Activities SET state = ? WHERE id = ?";

  if($state == CE_TASK_ST_FAILED && $#{ $tl_ref } == -1) {
    # task failed and there are no more tasks for this activity
    # then just update activity and exit
    $dbh->do($sql_upd_act, {}, $state, $task_ref->{activity_id});
    if($dbh->err) {
      goto REPORT_INTERNAL_ERROR;
    }

    # $r->{status} = CE_OP_ST_SUCCESS;
    $do_pingback = 1;
  } elsif($state == CE_TASK_ST_FAILED && $#{ $tl_ref } >= 0) {
    # task failed and there are more tasks for this activity
    # set the next tasks as PARENT_FAILED
    my $sql_upd_others = "UPDATE Task_Attempts SET state = ? WHERE id = ?";
    foreach my $t (@{ $tl_ref }) {
      $dbh->do($sql_upd_others, {}, CE_TASK_ST_PARENT_FAILED, $t->{id});
    }

    $dbh->do($sql_upd_act, {}, $state, $task_ref->{activity_id});
    if($dbh->err) {
      goto REPORT_INTERNAL_ERROR;
    }

    $do_pingback = 1;
  } elsif($state == CE_TASK_ST_COMPLETED && $#{ $tl_ref } == -1) {
    # no more tasks, update Activity state to COMPLETED or FAILED
    $dbh->do($sql_upd_act, {}, $state, $task_ref->{activity_id});
    if($dbh->err) {
      goto REPORT_INTERNAL_ERROR;
    }

    $do_pingback = 1;
  } elsif($#{ $tl_ref } >= 0 && $state == CE_TASK_ST_COMPLETED) {
    my $sql_next = "UPDATE Task_Attempts SET state = ? WHERE id = ?";
    # this task succeeded and there are more tasks.
    # Set the status of the next task to WAITING
    # No need to report anything
    $dbh->do($sql_next, {}, CE_TASK_ST_WAITING, $tl_ref->[0]->{id});
    if($dbh->err) {
      goto REPORT_INTERNAL_ERROR;
    }
  }

  $dbh->commit();
  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  } else {
    return ce_ret_success({ do_pingback => $do_pingback });
  }

REPORT_INTERNAL_ERROR:
  $dbh->rollback();
  return ce_ret_internal_error({}, $dbh->errstr);
}

sub get_activity_report {
  my($self, $req) = @_;
  my $dbh = $self->{_dbh};

  my $p;
  if(exists($req->{id})) {
    $p = 'id';
  } elsif($req->{dashboard_act_id}) {
    $p = 'dashboard_act_id';
  }
  my $v = $req->{$p};

  my $sql_act = "SELECT * FROM Activities WHERE $p = ?";
  my $act_ref = $dbh->selectrow_hashref($sql_act, {}, $v);
  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  } elsif(!$act_ref) {
    return ce_ret_not_found({}, 'activity not found');
  }

  my $sql_tasks = "SELECT T.id, C.name command_name, TA.state, TA.return_code,
                    TA.output, TA.start_time, TA.end_time, S.uuid
                   FROM Activities A, Tasks T, Task_Attempts TA, Commands C,
                   Servers S
                   WHERE A.$p = ? AND T.activity_id = A.id AND
                   T.command_id = C.id AND T.last_attempt_id = TA.id AND
                   T.exec_server_id = S.id ORDER BY T.id";

  my $rpl = {};
  if(my $tasks_ref = $dbh->selectall_arrayref($sql_tasks, { Slice => {} }, $v)) {
    $rpl->{tasks} = $tasks_ref;
  }

  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  }

  foreach my $key (qw( priority created_on last_update name state )) {
    if(exists($act_ref->{$key})) {
      $rpl->{activity}->{$key} = $act_ref->{$key}
    }
  }

  return ce_ret_success($rpl);
}

sub create_install_token {
  my($self, $server_id, $token_str) = @_;
  my $dbh = $self->{_dbh};

  my $sql_insrt = "INSERT INTO Install_Tokens(server_id, token_str) VALUES (?, ?)";

  $dbh->do($sql_insrt, {}, $server_id, $token_str);
  if($dbh->err) {
    return ce_ret_internal_error({}, $dbh->errstr);
  } else {
    return ce_ret_success();
  }
}

sub get_install_token_entry {
  my($self, $params_r) = @_;
  my $dbh = $self->{_dbh};

  return &$_get_entry_n_return($dbh, 'Install_Tokens', $params_r);
}

sub get_server_entry_raw {
  my($self, $params_r) = @_;
  my $dbh = $self->{_dbh};

  return &$_get_entry_n_return($dbh, 'Servers', $params_r);
}

1;
