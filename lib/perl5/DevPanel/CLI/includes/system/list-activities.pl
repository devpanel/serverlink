my $run = sub {
  my($conf, $rp, $rsp) = @_;

  if(!exists($rsp->{activities})) {
    print "There are no activities in the queue.\n";
    return 0;
  }

  foreach my $act (@{ $rsp->{activities} }) {
    print Dumper($act);
  }
};

my $ref = {
  'op'            => 'list_queue_activities',
  'desc'          => 'Lists all queue activities related to the user',
  'method'        => 'get',
  'run'           => $run,
};
