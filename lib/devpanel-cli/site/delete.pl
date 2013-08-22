my $run = sub {
  my($conf, $rp, $http_rsp) = @_;
  if(ce_was_successful($http_rsp)) {
    print "Site successfully scheduled for removal.\n";
  }

  return 0;
};

my $req = {
  'op'     => 'delete_site',
  'desc'   => 'Deletes a site from the server',
  'method' => 'post',
  'req_params' => {
    'site_id' => 'id of the site to be removed (id as returned by: sites list)',
  },
  'getopt_params' => {
    'site_id=i' => \$ro{site_id},
  },
  'run' => $run,
};

