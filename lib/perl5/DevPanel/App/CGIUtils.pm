package DevPanel::App::CGIUtils;
use strict;
use warnings;
use DevPanel::Constants;

our @ISA = ("Exporter");

our @EXPORT = (qw(
  is_valid_app_session
));

our $error_str = '';

sub is_valid_app_session {
  my($session, $app_name) = @_;

  if($session && ! $session->is_empty() && ! $session->is_expired() &&
    $session->param('app') eq $app_name) {
    return 1;
  } else {
    return 0;
  }
}


1;
