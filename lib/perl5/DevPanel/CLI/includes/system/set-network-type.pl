my $run = sub {
  my($conf, $rp, $rsp) = @_;

  my $type = lc($rp->{type});
  if($type ne 'nat' && $type ne 'bridge') {
    warn "Error: network type should be either: nat or bridge\n";
    return 1;
  }

  open(CONF_RUN, "|/opt/webenabled/backend-scripts/libexec/config-values set-or-replace vm_network_type /opt/webenabled/config/devpanel.conf");
  print CONF_RUN $type, "\n";
  close(CONF_RUN);

  if($type eq 'nat') {
    open(CONF_RUN, '|/opt/webenabled/backend-scripts/libexec/config-values set custom_http_port /opt/webenabled/config/devpanel.conf');
    print CONF_RUN "8080", "\n";
    close(CONF_RUN);
    system('/opt/webenabled/backend-scripts/libexec/config-values delete local_ip_in_dns /opt/webenabled/config/taskd.conf');
  } elsif($type eq 'bridge') {
    open(CONF_RUN, '|/opt/webenabled/backend-scripts/libexec/config-values set local_ip_in_dns /opt/webenabled/config/taskd.conf');
    print CONF_RUN "1", "\n";
    close(CONF_RUN);
    system('/opt/webenabled/backend-scripts/libexec/config-values delete custom_http_port /opt/webenabled/config/devpanel.conf');
  }

  print "Successfully set network type to: $type\n";

};

my $ref = {
  'op'            => '',
  'desc'          => 'Sets the network type of the VM',
  'method'        => 'post',
  'req_params'    => {
    'type'        => 'The network type: nat or bridge',
  },
  'getopt_params' => {
    'type|t=s'    => \$ro{type},
  },
  'is_local'      => 1,
  'run'           => $run,
};

