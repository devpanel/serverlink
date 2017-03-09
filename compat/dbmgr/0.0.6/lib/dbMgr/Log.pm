package dbMgr::Log;

use strict;
use FindBin;
use Sys::Syslog;

sub new {
    my $this = shift;
    my ($ident, $logopt, $facility) = @_;
    my $class = ref($this) || $this;
    my $self = {};
    bless $self, $class;

    unless (defined($ident)) {
	$ident = $FindBin::Script;
    }

    unless (defined($logopt)) {
	$logopt = 'pid,cons,nowait';
    }

    unless (defined($facility)) {
	$facility = 'user';
    }

    $self->open($ident, $logopt, $facility);

    return $self;
}

sub open($$$) {
    my $self = shift;
    my ($ident, $logopt, $facility) = @_;
    openlog($ident, $logopt, $facility);
}

sub write($$@) {
    my $self = shift;
    my ($priority, $format, @args) = @_;
    syslog($priority, $format, @args);
}

sub setmask($) {
    my $self = shift;
    my $logmask = shift;
    return setlogmask($logmask);
}

sub close() {
    my $self = shift;
    closelog();
}

sub emerg {
    my $self = shift;
    $self->write('LOG_EMERG',@_);
}

sub alert {
    my $self = shift;
    $self->write('LOG_ALERT',@_);
}

sub crit {
    my $self = shift;
    $self->write('LOG_CRIT',@_);
}

sub err {
    my $self = shift;
    $self->write('LOG_ERR',@_);
}

sub warning {
    my $self = shift;
    $self->write('LOG_WARNING',@_);
}

sub notice {
    my $self = shift;
    $self->write('LOG_NOTICE',@_);
}
sub info {
    my $self = shift;
    $self->write('LOG_INFO',@_);
}
sub debug {
    my $self = shift;
    $self->write('LOG_DEBUG',@_);
}

1;
