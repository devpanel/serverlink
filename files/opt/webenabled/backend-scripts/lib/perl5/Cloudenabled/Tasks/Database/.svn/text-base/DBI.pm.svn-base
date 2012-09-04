package Cloudenabled::Tasks::Database::DBI;
use strict;
use warnings;
use base 'Cloudenabled::ErrorHandling';
use DBI;

sub new {
  my($class, @params) = @_;
  my $self = {};

  if(!@params) {
    warn __PACKAGE__, " constructor didn't receive any parameter";
    return undef;
  }

  my($db_type, $db_url, $db_user, $db_pass, $db_opts);

  for(my $i=0; $i < $#params; $i++) {
    my $key = $params[$i];
    my $val = $params[++$i];

    if($key eq 'db_url') {
      $db_url = $val;
    } elsif($key eq 'db_user') {
      $db_user = $val;
    } elsif($key eq 'db_pass') {
      $db_pass = $val;
    } elsif($key eq 'db_opts') {
      $db_opts = $val;
    }
  }

  if(!defined($db_url)) {
    warn "Error: missing parameter db_url";
    return 0;
  }

  $db_user = defined($db_user) ? $db_user : '';
  $db_pass = defined($db_pass) ? $db_pass : '';
  $db_opts = defined($db_opts) && ref($db_opts) eq 'HASH' ? $db_opts : {};

  my $dbh = eval { DBI->connect($db_url, $db_user, $db_pass, $db_opts); };
  if(!$dbh) {
    warn __PACKAGE__, " - unable to connect to database:\n$@";
    return 0;
  }
  $self->{_dbh}      = $dbh;
  ($self->{_db_type} = __PACKAGE__) =~ s/^.+:://;

  bless($self, $class || __PACKAGE__);
  return $self;
}

sub add_msg {
  my($self, $p) = @_;
  my $dbh = $self->{_dbh};
  my $sql_str = "INSERT INTO Messages(type_id, server_id, contents) VALUES(?, ?, ?)";
  $dbh->do($sql_str, {}, $p->{type_id}, $p->{server_id}, $p->{contents});
  
  if($dbh->err) {
    $self->set_error($dbh->err, $dbh->errstr);
    return 0;
  } else {
    $self->clear_error();
    return 1;
  }
}

1;
