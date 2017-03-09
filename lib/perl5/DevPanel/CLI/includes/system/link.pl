my $prerun = sub {
  my($conf, $rp, $req_params) = @_;

  if(exists($conf->{server_uuid})) {
    warn "Warning: server already registered.\n" if(!$rp->{silent});
    exit(0);
  }
};

my $run = sub {
  my($conf, $rp, $rsp) = @_;

  $conf->{api_key}    = $rsp->{api_key};
  $conf->{api_secret} = $rsp->{api_secret};

  if(!open(CONF_FILE, ">$rp->{config_file}")) {
    warn "Error: unable to open config file '$rp->{config_file}'\n";
    return 1;
  }

  $conf->{server_uuid} = $rsp->{taskd_uuid};
  foreach my $key (keys %$conf) {
    printf CONF_FILE "%s = %s\n", $key, $conf->{$key};
  }
  close(CONF_FILE);

  my $taskd_conf = cloudenabled_parse_conf($rp->{taskd_config_file});
  if(!$taskd_conf) {
    return 1;
  }

  if(!open(TASKD_CONF, ">$rp->{taskd_config_file}")) {
    warn "Error: unable to open taskd config file '$rp->{taskd_config_file}': $!\n";
    return 1;
  }

  $taskd_conf->{uuid} = $rsp->{taskd_uuid};
  $taskd_conf->{key}  = $rsp->{taskd_key};

  foreach my $k (keys %$taskd_conf) {
    printf TASKD_CONF "%s = %s\n", $k, $taskd_conf->{$k};
  }
  close(TASKD_CONF);
  close(CONF_FILE);

  # system('/sbin/initctl stop  taskd');
  # system('/sbin/initctl start taskd');
  # system('/sbin/initctl stop  taskd >/dev/null');
  # system('/sbin/initctl start taskd >/dev/null');

  if(!$rp->{silent}) {
    print "Successfully linked server to DevPanel.\n";
  }
};

my $ref = {
  'op'            => 'create_anonymous_vm',
  'desc'          => 'Registers this server with DevPanel and makes it ready for use',
  'method'        => 'post',
  'opt_params'    => {
    'name' => 'A friendly name for this server. E.g. "My New server"',
  },
  'getopt_params' => {
    'name|n=s'      => \$ro{name},
  },
  'requires_auth' => 0,
  'run'    => $run,
  'prerun' => $prerun,
};

