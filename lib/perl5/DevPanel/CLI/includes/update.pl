my $run = sub {
  my $update_bin = '/opt/webenabled/libexec/update-scripts';
  system($update_bin);
  my $update_pkgs = '/opt/webenabled/libexec/update-packages';
  system($update_pkgs);
  return $?;
};

my $ref = {
  'op'            => '',
  'short_txt'     => 'Attempts to update the software installed on this server',
  'desc'          => 'Attempts to update the software installed on this server',
  'method'        => 'post',
  'getopt_params' => { },
  'requires_auth' => 0,
  'is_local'      => 1,
  'run'           => $run,
};
