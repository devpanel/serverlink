my $run = sub {
  my($conf, $rp, $http_rsp) = @_;

  if(ce_was_successful($http_rsp)) {
    if($#{ $http_rsp->{sites} } < 0) {
      print "Returned zero sites.\n";
      exit(0);
    }

    my $fmt = "%-5s %-30s %-15s %-10s %-20s %-s\n";
    printf($fmt, 'ID', 'Name', 'Application', 'Version', 'State', 'URL');

    my $port_suffix;
    if(exists($conf->{custom_http_port})) {
      $port_suffix = sprintf(":%s/", $conf->{custom_http_port});
    } else {
      $port_suffix = "";
    }

    foreach my $site (@{ $http_rsp->{sites} }) {
      my $state;
      if($site->{state} == 0) {
        $state = 'Active';
      } elsif($site->{state} == 1) {
        $state = 'Awaiting deployment';
      } else {
        $state = 'Unknown';
      }
      printf($fmt, $site->{id}, $site->{name}, $site->{app}, $site->{version},
              $state, $site->{url} . $port_suffix);
    }
  }
};

my $ref = {
  'desc'   => 'Lists all sites installed in this server',
  'op'     => 'list_sites',
  'method' => 'get',
  'run'    => $run,
};
