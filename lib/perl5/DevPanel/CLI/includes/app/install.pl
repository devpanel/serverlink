my $prerun = sub {
  my($conf, $rp, $req_params) = @_;

  $req_params->{server} = $conf->{server_uuid};
};

my $run = sub {
  my($conf, $rp, $http_rsp) = @_;

  if(ce_was_successful($http_rsp)) {
    print "Site successfully scheduled for creation. You can track the status with: sites list.\n";
  }
};

my $ref = {
  'op'     => 'create_site',
  'desc'   => 'Creates a new site with the app installed',
  'method' => 'post',
  'req_params' => {
    'app_id' => 'id of the application to be installed (as returned by: app list)',
    'name'   => 'friendly name for the new site. E.g. "My new project"',
  },
  'getopt_params' => {
    'app_id|i=i'        => \$ro{app_id},
    'name=s'          => \$ro{name},
    'linux_username=s' => \$ro{linux_username},
    'version_id=i'    => \$ro{version_id},
    'description=s'   => \$ro{description},
    'app_password=s'   => \$ro{app_password},
  },
  'opt_params' => {
    'linux_username'  => 'the username to use in sftp and ssh',
    'version_id'      => 'id of the version to install (as returned by app list_versions)',
    'description'     => 'a short description of the site',
    'app_password'    => 'the password for the admin user of the app being installed',
  },
  'prerun' => $prerun,
  'run'    => $run,
};
