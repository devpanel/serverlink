package dbMgr::Utils;

use strict;
use Carp;
use FindBin;
use Fcntl ':flock';

require Exporter;
our @ISA        = qw(Exporter);
our @EXPORT  = qw(lock_file
                     unlock_file
                     );
our $VERSION    = 0.01;

####################################################################

sub lock_file {
    my $filehandle = shift;
    my $mode = shift;
    my $operation = LOCK_SH;

    if (defined $mode) {
	if ($mode eq 'write') {
	    $operation = LOCK_EX;
	}
    }
    
    my $max_tries = 5;
    for (my $try=1; $try <= $max_tries; $try++) {
	return 1 if flock($filehandle, $operation | LOCK_NB);
	sleep($try) unless $try == $max_tries;
    }
    return 0;
}

sub unlock_file {
    my $filehandle = shift;
    
    my $max_tries = 5;
    for (my $try=1; $try <= $max_tries; $try++) {
	return 1 if flock($filehandle, LOCK_UN);
	sleep($try) unless $try == $max_tries;
    }
    return 0;
}

1;
