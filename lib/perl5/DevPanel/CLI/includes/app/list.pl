my $run = sub {
  my($conf, $args, $http_rsp) = @_;

  if($#{ $http_rsp->{apps} } < 0) {
    print "Returned zero applications.\n";
    return 0;
  }

  my $fmt = "%-5s %-33s %-7s %-s\n";
  printf($fmt, 'ID', 'Name', 'Type', 'Vendor URL');
  foreach my $srv (@{ $http_rsp->{apps} }) {
    printf($fmt, $srv->{id}, $srv->{name}, $srv->{type}, $srv->{vendorUrl});
  }

  return 0;
};

my $defs = {
    'op'      => 'list_apps',
    'method'  => 'get',
    'desc'    => 'Lists applications available for installing',
    'run'     => $run,
};
