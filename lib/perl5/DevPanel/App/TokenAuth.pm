package DevPanel::App::TokenAuth;
use strict;
use warnings;
use DevPanel::Constants;

our $error_str = '';

sub authenticate {
  my(@opts) = @_;

  my %vars = (
    dir_path     => undef,
    app          => undef,
    token_length => DEVPANEL_APPTOKEN_LENGTH,
    vhost        => undef,
    token_str    => undef,
  );

  if($#opts % 2 == 0) { # if the last element is even, the number of entered
                        # arguments is odd
    $error_str = "authenticate(): Error: received an odd number of arguments";
    return 0;
  }

  for(my $i=0; $i < $#opts; $i++) {
    my $key = $opts[$i];
    my $val = defined($opts[++$i]) ? $opts[$i] : undef;

    if(exists($vars{$key})) {
      $vars{$key} = $val;
    }
  }

  if(!defined($vars{dir_path})) {
    use FindBin (qw( $RealBin ));
    use Cwd     (qw( abs_path ));

    $vars{dir_path} = abs_path($RealBin . "/../../../../var/tokens");
    if(!defined($vars{dir_path})) {
      $error_str = "unable to determine tokens directory path";
      return 0;
    } elsif(! -e $vars{dir_path}) {
      $error_str = "path '$vars{dir_path}' doesn't exist";
      return 0;
    } elsif(! -d $vars{dir_path}) {
      $error_str = "path '$vars{dir_path}' is not a directory";
      return 0;
    }
  }

  if(!defined($vars{vhost})) {
    my @curr_user_ar = getpwuid($>);
    if(!@curr_user_ar) {
      $error_str = "uname to get the current user information";
      return 0;
    }

    if(length($curr_user_ar[0]) > 2 && substr($curr_user_ar[0], 0, 2) eq "w_") {
      $vars{vhost} = substr($curr_user_ar[0], 2);
    } else {
      $vars{vhost} = $curr_user_ar[0];
    }
  }

  foreach my $param (qw( app token_str )) {
    if(!exists($vars{$param}) || !defined($vars{$param})) {
      $error_str = "authenticate(): missing parameter $param";
      return 0;
    } elsif(length($vars{$param}) == 0) {
      $error_str = "authenticate(): empty value for parameter $param";
    }
  }

  if(!&is_valid_token_str($vars{token_str})) {
    return 0;
  }

  my $token_file = &get_tokenfile_path($vars{token_str}, $vars{vhost},
                                       $vars{app}, $vars{dir_path});

  if(!&is_valid_tokenfile($token_file)) {
    return 0;
  }

  &invalidate_token_file($token_file);
  $error_str = ""; # ignoring the errors on previous function, if any
  return 1;
}

sub get_tokenfile_path {
  my($token_str, $vhost, $app, $dir_path) = @_;

  my $token_file = sprintf("%s/%s.%s.%s", $dir_path, $vhost, $app, $token_str);

  return $token_file;
}

sub is_valid_token_str {
  my($token_str) = @_;

  if(length($token_str) != DEVPANEL_APPTOKEN_LENGTH) {
    $error_str = "invalid token length";
    return 0;
  } elsif($token_str !~ /^[A-Za-z0-9_]+$/) {
    $error_str = "invalid token format";
    return 0;
  } elsif(length($token_str) == DEVPANEL_APPTOKEN_LENGTH && $token_str =~ /^[A-Za-z0-9_]+$/) {
    return 1;
  } 

  return 0;
}

sub is_valid_tokenfile {
  my($token_file) = @_;

  if(!-e $token_file) {
    $error_str = "file '$token_file' doesn't exist";
    return 0;
  } elsif(! -f $token_file) {
    $error_str = "path '$token_file' is not a regular file";
    return 0;
  }

  my @token_stat_ar = stat($token_file);
  if(!@token_stat_ar) {
    $error_str = "couldn't stat token file '$token_file': $!\n";
    return 0;
  }

  if($token_stat_ar[9] == 0) { # if mtime == 0, return authentication denied
    $error_str = "token has already been used";
    return 0;
  }

  if(-e $token_file && $token_stat_ar[9] > 0) {
    $error_str = "";
    return 1;
  } else {
    $error_str = "unknown token validation error";
    return 0;
  }
}

sub invalidate_token_file {
  my($token_file) = @_;

  if(!utime(0, 0, $token_file)) {
    $error_str = "unable to touch file '$token_file': $!";
    return 0;
  } else {
    return 1;
  }
}

1;
