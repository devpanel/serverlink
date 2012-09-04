package Cloudenabled::ErrorHandling;
use strict;
use warnings;

sub clear_error {
  my($self) = @_;

  delete($self->{error})  if exists($self->{error});
  delete($self->{errmsg}) if exists($self->{errmsg});

  return 1;
}

sub error {
  my($self) = @_;

  if(exists($self->{error})) {
    return $self->{error};
  } else {
    return undef;
  }
}

sub errmsg {
  my($self) = @_;

  if(exists($self->{errmsg})) {
    return $self->{errmsg};
  } else {
    return undef;
  }
}

sub set_error {
  if($#_ < 1) { # less than 2 arguments
    return 0;
  }

  my($self, $err, $errmsg) = @_;
  $self->{error} = $err;
  if(defined($errmsg)) {
    $self->{errmsg} = $errmsg;
  }

  return 1;
}

1;
