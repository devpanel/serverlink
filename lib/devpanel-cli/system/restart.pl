my $run = sub {
  my($conf, $rp, $rsp) = @_;

  print "Reloading subsystems...\n";

  system('/sbin/initctl reload taskd');
  system('/opt/webenabled/config/os/pathnames/sbin/apachectl stop');
  system('/opt/webenabled/config/os/pathnames/sbin/apachectl start');
  system('/sbin/initctl stop  dbmgr');
  system('/sbin/initctl start dbmgr');
};

my $ref = {
  'op'            => '',
  'desc'          => 'Reloads all software related to Webenabled',
  'method'        => 'post',
  'is_local'      => 1,
};

