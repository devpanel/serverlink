my $run = sub {
  my $service = ($^O =~ /^darwin/) ? "com.devpanel.taskd" : "devpanel-taskd";
  my $status_script = "$DevPanel::CLI::main_dir/libexec/system-services";

  print "\n";

  system("$status_script $service status >/dev/null 2>&1");
  my $ret = $? >> 8;
  if($ret == 0) {
    print "devPanel is connected\n";
  } else {
    print "devPanel IS NOT connected. Try running: devpanel start\n";
  }

  my($user, $uid, $home) = (getpwnam("devpanel"))[0,2,7];
  if($? != 0) {
    die "Error: unable to get uid of user devpanel.\n";
  }

  my $gids = ce_get_user_gids("devpanel");
  if(!ce_drop_privs($uid, $gids)) {
    exit(1);
  }

  my $vagrant_dir = "$home/vagrant";
  if(!-d $vagrant_dir) {
    exit(0);
  }

  if(!opendir(DP_HOME, $vagrant_dir)) {
    die "Error: unable to open home dir $home: $!\n";
  }

  print "
The list of Vagrant boxes on this machine.

";

  while(my $entry = readdir(DP_HOME)) {
    if(substr($entry, 0, 1) eq ".") {
      next;
    }

    my $full_path = "$vagrant_dir/$entry";

    if(! -d $full_path) {
      next;
    }

    chdir($full_path);
    if($? != 0) {
      next;
    }

    system("vagrant status | fgrep -q 'is running'");
    my $ret = $? >> 0;

    if($? != 0) {
      warn "Error: $!\n";
    }

    if($ret == 0) {
      printf "  %s (running)\n", $entry;
    } else {
      printf "  %s (not running)\n", $entry;
    }
  }

  print "\n";

  close(DP_HOME);

};

my $ref = {
  'op'            => '',
  'short_txt'     => 'Gets the status of the local installation',
  'desc'          => 'Gets the status of the local installation',
  'method'        => 'post',
  'getopt_params' => { },
  'requires_auth' => 0,
  'is_local'      => 1,
  'run'           => $run,
};
