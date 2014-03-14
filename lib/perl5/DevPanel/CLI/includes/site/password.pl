my $run = sub {
  my($conf, $rp, $http_rsp) = @_;

  if(ce_was_successful($http_rsp)) {
    print "Password change will happen within a minute. Please wait.\n";
  }

  return 0;
};

my $ref = {
  'op'      => 'site_set_app_password',
  'desc'    => 'Changes the password of the application installed in a site',
  'method'  => 'post',
  'req_params' => {
    'site-id'      => 'id of the site to change the password (as returned by: show sites)',
    'new-password' => 'the new password to be set',
  },
  'getopt_params' => {
    'site-id=i'      => \$ro{'site-id'},
    'new-password=s' => \$ro{'new-password'},
  },
  'run' => $run,
};
