my $run = sub {
  my($config, $ro, $http_r) = @_;

  # my $service = ($^O =~ /^darwin/) ? "com.devpanel.taskd" : "devpanel-taskd";
  my $service = "devpanel-taskd";
  my $status_script = "$DevPanel::CLI::main_dir/libexec/system-services";
  # system("$status_script $service start >/dev/null 2>&1");
  system("$status_script $service stop");
  my $ret = $? >> 8;
  if($ret == 0) {
    print "Stopped devPanel connection (taskd)\n";
  } else {
    print "Failed to stop connection to devPanel (taskd).\n";
    return 1;
  }

  
  if(exists($config->{globals}->{provisioner}) &&
    $config->{globals}->{provisioner}) {

    print "Stopping vagrant VMs...\n";

    my($uid, $home) = (getpwnam("devpanel"))[2,7];
    if($? != 0) {
      die "Error: unable to get uid of user devpanel.\n";
    }

    my $gids = ce_get_user_gids("devpanel");
    if(!ce_drop_privs($uid, $gids)) {
      exit(1);
    }

    my $vagrant_dir = "$home/vagrant";
    if(!opendir(DP_HOME, $vagrant_dir)) {
      die "Error: unable to open home dir $home: $!\n";
    }

    while(my $entry = readdir(DP_HOME)) {
      print "Evaluating entry $entry\n";

      if(substr($entry, 0, 1) eq ".") {
        print "Skipping entry: $entry\n";
        next;
      }

      my $full_path = "$home/vagrant/$entry";

      if(! -d $full_path) {
        print "Skipping entry: $entry (not dir)\n";
        next;
      }

      print "Evaluating dir $full_path\n";

      chdir($full_path);
      if($? != 0) {
        warn "Error: unable to cd into dir $full_path: $!\n";
        next;
      }

      system("vagrant status | fgrep -q 'is running'");
      my $ret = $? >> 0;
      if($? != 0) {
        warn "Error: $!\n";
        next;
      }

      if($ret != 0) {
        next; # VM is NOT running
      }

      printf "Stopping VM %s\n", $entry;

      system("vagrant halt");
      if($? != 0) {
        warn "Error: $!\n";
        next;
      }

      print "\n\n";

    }

    print "devPanel successfully stopped.\n";
    close(DP_HOME);
    exit(0);
  }

};

my $ref = {
  'op'            => '',
  'short_txt'     => 'Starts devPanel connector',
  'desc'          => 'Starts devPanel connector',
  'method'        => '',
  'getopt_params' => { },
  'requires_auth' => 0,
  'is_local'      => 1,
  'run'           => $run,
};
