my $run = sub {
  my($cfg_r, $ro, $http_rsp) = @_;

  my $uninstall_script = "$main_dir/install/uninstall.sh";
  
  print "Executing uninstall script...\n";
  system($uninstall_script, '-y', $main_dir);
  my $ret = $? >> 8;
  if($? != 0) {
    warn "Error: $?\n";
    exit($ret);
  }
};

my $ref = {
  'op'            => '',
  'short_txt'     => 'Uninstalls devPanel software',
  'desc'          => "Completely uninstalls devPanel software " .
                     "deleting all sites and virtual machines " .
                     "on this server.\n\n" .
                     "ALL SITES and VMs will be DESTROYED, with no recovery",
  'method'        => '',
  'req_params' => {
    'yes' => 'confirm that you really want to uninstall',
  },
  'getopt_params' => {
    'yes' => \$ro{yes},
  },
  'requires_auth' => 0,
  'is_local'      => 1,
  'run'           => $run,
};
