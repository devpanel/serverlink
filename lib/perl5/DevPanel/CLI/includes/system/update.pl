my $run = sub {
  my $update_bin = '/opt/webenabled/current/libexec/update-incr';
  system($update_bin, '-y');
  return $?;
};

my $ref = {
  'op'            => '',
  'desc'          => 'Attempts to update the software installed in this server',
  'method'        => 'post',
  'getopt_params' => { },
  'is_local'      => 1,
  'run'           => $run,
};
