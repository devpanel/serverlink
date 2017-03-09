package dbMgr::DB;

use strict;
use FindBin;
use Getopt::Long;

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = {};
    $self->{user} = undef;
    $self->{db_type} = undef;
    $self->{db_version} = undef;
    $self->{datadir} = undef;
    $self->{ip} = undef;
    $self->{port} = undef;
    $self->{limits} = undef;
    $self->{contact} = undef;
    $self->{comment} = undef;
    bless $self, $class;

    return $self;
}

1;
