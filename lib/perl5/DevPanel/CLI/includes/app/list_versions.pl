my $run = sub {
  my($conf, $rp, $rsp) = @_;

  if(ce_was_successful($rsp)) {
    if($#{ $rsp->{versions} } < 0) {
      print "Returned zero versions.\n";
      return 0;
    }

    print "Application: ", $rsp->{app_name}, "\n\n";
    my $fmt = "%-5s %-s\n";
    printf($fmt, 'ID', 'Version');
    foreach my $srv (@{ $rsp->{versions} }) {
      printf($fmt, $srv->{id}, $srv->{name});
    }
  }
};

my $req = {
  'op'         => 'list_app_versions',
  'method'     => 'get',
  'desc'       => 'Lists all versions available for a given application',
  'req_params' => {
    'app_id'   => 'id of the application (as returned by: app list)',
  },
  'getopt_params' => {
    'app-id=i' => \$ro{'app_id'},
  },
  'run' => $run,
};
