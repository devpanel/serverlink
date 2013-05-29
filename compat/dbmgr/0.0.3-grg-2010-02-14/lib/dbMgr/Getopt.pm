package Getopt;

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

    my $result = GetOptions(
	"user|u=s"		=> \$self->{user},
	"db_type|t=s"		=> \$self->{db_type},
	"db_version|v=s"	=> \$self->{db_version},
	"datadir|d=s"		=> \$self->{datadir},
	"ip|i=s"		=> \$self->{ip},
	"port|p=s"		=> \$self->{port},
	"limits|l=s"		=> \$self->{limits},
	"contact|c=s"		=> \$self->{contact},
	"comment|z=s"		=> \$self->{comment}
    );

    return $self;
}

1;
