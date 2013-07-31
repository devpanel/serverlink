package dbMgr::Config;

use strict;
use dbMgr::Log;
use dbMgr::Utils;

sub new {
    my $this = shift;
    my $config_dir = shift;
    my $option = shift;
    my $class = ref($this) || $this;
    my $self = {};
    $self->{config_dir} = $config_dir;
    $self->{options} = { relaxed => (defined($option) && ($option eq 'relaxed')) ? 1 : 0 };
    $self->{db_types} = ();
    $self->{daemons} = ();
    $self->{log} = new dbMgr::Log($FindBin::Script, 'pid,cons,nowait', 'user');
    bless $self, $class;
    defined $config_dir ? $self->{log}->debug("[dbMgr::Config] object created with arguments: config_dir = '%s'", $config_dir) :
	$self->{log}->debug("[dbMgr::Config] temporary uninitialized object created");
    $self->initialize() if (defined $self->{config_dir});
    return $self;
}

sub initialize {
    my $self = shift;
    $self->{initialized} = 1;

    if (defined $self->{config_dir}) {
    
	if (!($self->{config_dir} =~ /\/$/)) {
	    $self->{config_dir} .= "/";
	}
	
	$self->read_config() if (defined $self->{config_dir});
    }
    $self->{log}->debug("[dbMgr::Config] object was initialized successfully");
}

sub parse_db_types {
    my $self = shift;
    my $filename = shift;
    
    unless ( -f "$filename") {
        $self->{log}->debug("[dbMgr::Config] parse_db_types: file not found '%s'", $filename);
        $self->{log}->err("file not found '%s'", $filename);
	die "cannot find $filename at ";
    }

    if (!open(CONFIG, $filename)) {
        $self->{log}->debug("[dbMgr::Config] parse_db_types: cannot open file '%s'", $filename);
        $self->{log}->err("cannot open file '%s'", $filename);
	die "cannot open $filename at ";
    }

    lock_file(*CONFIG);

    while (<CONFIG>) {
	chomp;
	
	s/#.*$//;
	s/^\s+//;
	s/\s+$//;
	next if /^$/;
	 
	my (
	    $db_name,
	    $db_prefix,
	    $db_IPs,
	    $db_ports
	) = split(/:/);

	unless (defined $db_name) {
	    # XXX: Implement line counter
            $self->{log}->debug("[dbMgr::Config] parse_db_types: db_name undefined in '%s:%d'", $filename, 1);
	    $self->{log}->warning("skipping database configuration in '%s:%d' due missing db_name field", $filename, 1);
	    print "Warning: skipping database configuration in '$filename:1' due missing db_name field\n";
	    next;
	}

        $db_prefix = $self->{config_dir} . "/" . $db_prefix unless $db_prefix =~ /^\//;
	unless (defined $db_prefix && -d $db_prefix) {
	    # XXX: Implement line counter
            $self->{log}->debug("[dbMgr::Config] parse_db_types: db_prefix undefined in '%s:%d' or '$db_prefix' is not a directory", $filename, 1);
	    $self->{log}->warning("skipping database configuration in '%s:%d' due invalid db_prefix field", $filename, 1);
	    print "Warning: skipping database configuration in '$filename:1' due undefined db_prefix or '$db_prefix' is not a directory\n";
	    next;
	}
	
	unless ($db_prefix =~ /\/$/) {
            $self->{log}->debug("[dbMgr::Config] parse_db_types: fixing db_prefix directory name with ending slash");
	    $db_prefix .= "/";
	}

	$self->{db_types}->{$db_name} = {
						prefix => $db_prefix,
						addresses => $db_IPs,
						ports => $db_ports
					};

        $self->{log}->debug("[dbMgr::Config] parse_db_types: adding '$db_name' database with prefix '$db_prefix', addresses '$db_IPs' and ports '$db_ports'");
    }
    
    unlock_file(*CONFIG);
    
    if (!close(CONFIG)) {
        $self->{log}->debug("[dbMgr::Config] parse_db_types: cannot close file '%s'", $filename);
        $self->{log}->warning("cannot close file '%s'", $filename);
    }
}

sub parse_db_daemons {
    my $self = shift;
    my $filename = shift;
    
    unless ( -f "$filename") {
        $self->{log}->debug("[dbMgr::Config] parse_db_daemons: file not found '%s'", $filename);
        $self->{log}->err("file not found '%s'", $filename);
	die "cannot find $filename at ";
    }
    
    if (!open(CONFIG, $filename)) {
        $self->{log}->debug("[dbMgr::Config] parse_db_daemons: cannot open file '%s'", $filename);
        $self->{log}->err("cannot open file '%s'", $filename);
	die "cannot open $filename at ";
    }

    lock_file(*CONFIG);

    while (<CONFIG>) {
	chomp;
	
	s/#.*$//;
	s/^\s+//;
	s/\s+$//;
	next if /^$/;
	 
	my %record = ();
	
	(
	    $record{user},
	    $record{type},
	    $record{version},
	    $record{datadir},
	    $record{host},
	    $record{port},
	    $record{limits},
	    $record{contact},
	    $record{password}
	) = split(/:/);

	# Deal with * in version
	undef $record{version} if (defined($record{version}) && $record{version} =~ /^\*$/);

	unless ($self->add_daemon(\%record)) {
	    $self->{log}->warning("[dbMgr::Config] parse_db_daemons: cannot add daemon configuration for user '%s'", defined($record{user}) ? $record{user} : "(unknown)");
	};
    }

    unlock_file(*CONFIG);

    if (!close(CONFIG)) {
        $self->{log}->debug("[dbMgr::Config] parse_db_daemons: cannot close file '%s'", $filename);
        $self->{log}->warning("cannot close file '%s'", $filename);
    }
}

sub read_config {
    my $self = shift;

    unless (defined $self->{initialized} || $self->{initalized}) {
        $self->{log}->debug("[dbMgr::Config] read_config: calling read_config() on not initialized Config object");
        $self->{log}->err("calling read_config() on not initialized Config object");
	die "Error: calling read_config() on not initialized Config object at ";
    }

    unless (defined $self->{config_dir} && -d  $self->{config_dir}) {
        $self->{log}->debug("[dbMgr::Config] read_config: undefined config_dir or '%s' is not a directory", $self->{config_dir});
        $self->{log}->err("undefined config_dir or '%s' is not a directory",  $self->{config_dir});
	die "Error: undefined config_dir or '" . $self->{config_dir} . "' is not a directory";
    }

    $self->parse_db_types($self->{config_dir} . "db-types.conf");
    $self->parse_db_daemons($self->{config_dir} . "db-shadow.conf");
}

sub write_config {
    my $self = shift;
    die "unimplemented!\n";
}

sub dump_config {
    my $self = shift;
    print "db_types:\n========\n";
    foreach my $key (keys %{$self->{db_types}}) {
	print "$key = (\n";
	my $details = \%{$self->{db_types}{$key}};
	foreach my $key2 (keys %{$details}) {
	    print "\t$key2 = $details->{$key2}\n";
	}
	print ")\n\n";
    }

    print "daemons:\n=======\n";
    foreach my $key (keys %{$self->{daemons}}) {
	print "$key = (\n";
	my $details = \@{$self->{daemons}->{$key}};
	my $details_len = $#{$details};
	for (my $i = 0; $i <= $details_len; $i++) {
	    print "\t\t#$i = {\n";
	    foreach my $key2 (keys %{@{$details}[$i]}) {
		print "\t\t\t$key2 = @{$details}[$i]->{$key2}\n";
	    }
	    print "\t\t}\n";
	}
	print ")\n\n";
    }
}

# fields:
# user, type, version, datadir, port, limits, contact, password
sub select($$) {
    my $self = shift;
    my $field = shift;
    my $regexp = shift;
    my $class = ref($self) || $self;
    my $result = $class->new();

    if (defined $field && defined $regexp) {
        foreach my $key (keys %{$self->{daemons}}) {

	    if ($field eq 'user' && $key =~ /$regexp/) {
		$result->{daemons}->{$key} = $self->{daemons}->{$key};
		next;
	    }

	    foreach my $key2 (@{$self->{daemons}->{$key}}) {
		if (defined $key2->{$field} && $key2->{$field} =~ /$regexp/) {
		    push @{$result->{daemons}->{$key}}, $key2;
		}
	    }
	}
    }

    return $result;
}

sub foreach($) {
    my $self = shift;
    my $func = shift;
    my @func_params = @_;
    
    return unless (defined $func);
    
    foreach my $user (keys %{$self->{daemons}}) {
        foreach my $daemon (@{$self->{daemons}->{$user}}) {
	    my $record = $daemon;
	    $record->{user} = $user;
	    &$func($record, $daemon, @func_params);
        }
    }
}

sub add_daemon {
    my $self = shift;

    unless (@_ >= 1 && ref($_[0]) eq 'HASH') {
	die "usage Config->add_daemon(HASHREF, [is this new account?]) ";
    }

    my $definition = shift;
    my $is_new_user = shift;

    unless ($self->{options}->{relaxed}) {
    foreach my $key (keys %{$definition}) {

	if ($key eq 'user') {
	    unless (defined($definition->{user})) {
		print "Warning: undefined system account name, skipping\n";
		return 0;
	    }

	    unless (getpwnam($definition->{user})) {
		if (!defined($is_new_user) || $is_new_user == 0) {
		    print "Unknown system account: " . (defined($definition->{user}) ? $definition->{user} : "(unknown)") . "\n";
		    return 0;
		}
		print "Notice: system account '" . $definition->{user} . "' seems not to be exists, will be created\n";
	    }

	    next;
	}

	if ($key eq 'type' || $key eq 'version') { # XXX: Avoid 2 passes in future
	    unless (defined($definition->{type}) && exists($self->{db_types}->{$definition->{type}})) {
		print "Unknown database type: " . (defined($definition->{type}) ? $definition->{type} : "(unknown)") . "\n";
		return 0;
	    }

	    if (!defined($definition->{version}) &&
		defined(my $db_current_version = readlink($self->{db_types}->{$definition->{type}}->{prefix} . "current"))) {
		    print "No version specified, using current version: $db_current_version\n";
		    $definition->{version} = $db_current_version;
	    }

	    unless (-d $self->{db_types}->{$definition->{type}}->{prefix} . $definition->{version}) {
		print "Unknown database version: " . $definition->{version} . "\n";

		return 0;
	    }
	    next;
	}

	if ($key eq 'datadir') {

	    if (!defined($definition->{datadir})) {
		if (defined($definition->{user})) {
		    my (undef,undef,undef,undef,undef,undef,undef,$homedir,undef,undef) = getpwnam($definition->{user});
		    if (defined($homedir)) {

			if (!($homedir =~ /\/$/)) {
        		    $self->{log}->debug("[dbMgr::Config] add_daemon: fixing homedir directory name with ending slash");
			    $homedir .= "/";
			}
			
			if (defined($definition->{type}) && -d $homedir . $definition->{type}) {
			    print "Warning: no datadir specified, using guessed value '" .  $homedir . $definition->{type} . "'\n";
			    $definition->{datadir} = $homedir . $definition->{type};
			}
			else {
			    print "Warning: cannot guess datadir, try to specify it via --datadir\n";
			    return 0;
			}
		    }
		    else {
			if (!defined($is_new_user) || $is_new_user == 0) {
			    print "Unknown or invalid system account: " . $definition->{user} . "\n";
			}
			else {
			    print "Warning: cannot guess datadir, try to specify it via --datadir\n";
			}
			return 0;
		    }
		}
		else {
		    print "Warning: system account is not specified\n";
		    return 0;
		}
	    }

	    unless (-d $definition->{datadir}) {
		if (!defined($is_new_user) || $is_new_user == 0) {
		    print "Specified data directory does not exists: " . $definition->{datadir} . "\n";
		    return 0;
		}
	    }

	    if (!($definition->{datadir} =~ /\/$/)) {
        	$self->{log}->debug("[dbMgr::Config] add_daemon: fixing datadir directory name with ending slash");
		$definition->{datadir} .= "/";
	    }

	    next;
	}

	if ($key eq 'host') {

	    if (!defined($definition->{host}) || $definition->{host} =~ /default/i) {
		print "Warning: host is not specified, using default '127.0.0.1'\n";
		$definition->{host} = '127.0.0.1';
	    }

    	    unless ($definition->{host} =~ /(\d+){1,3}\.(\d+){1,3}\.(\d+){1,3}\.(\d+){1,3}$/ &&
#               $1 > 0 && $2 >= 0 && $3 >= 0 && $4 > 0 &&
                $1 < 255 && $2 < 255 && $3 < 255 && $4 < 255) {
        	print "Warning: bad host name or IP address specified\n";
		return 0;
    	    }

	    next;
	}

	if ($key eq 'port') {
	    if (!defined($definition->{port})) {
		unless (defined($definition->{type}) && ($definition->{port} = $self->get_unused_ports($definition->{type}))) {
		    print "Warning: cannot found free port for specified database type, try to specify it via --port\n";
		    return 0;
		};
		print "Warning: port is not specified, using first free one '" . $definition->{port} . "'\n";
	    }

	    next;
	}

	if ($key eq 'limits') {
	    unless (defined($definition->{limits})) {
		$definition->{limits} = "disk=30M";
	    }
	    next;
	}

	if ($key eq 'contact') {
	    unless (defined($definition->{contact})) {
		$definition->{contact} = 'admin@df.ru';
	    }
	    next;
	}

	if ($key eq 'password') {
	    unless (defined($definition->{password})) {
		if (!defined($is_new_user) || $is_new_user == 0) {
			print "Warning: fixing empty password for" . $definition->{user} . ", database might become unusable after restart!\n";
		}
		print "Generating root password ... ";
		$definition->{password} = `$self->{config_dir}/../current/bin/passgen 2>/dev/null`;
		chomp $definition->{password};
		print "done.\n";
	    }
	    next;
	}
	
	print "Warning: unknown parameter '$key', it will not be written to config file\n";
    } # foreach
    } # unless

#        # host + port pair
#        {
#            socket(tmpSocket, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die "Cannot create socket";
#            bind(tmpSocket,sockaddr_in($record->{port},inet_aton($record->{host}))) || die "bind() fails";
#            close(tmpSocket);
#        }

    
    push @{$self->{daemons}->{$definition->{user}}},	{
							    type	=> $definition->{type},
							    version	=> $definition->{version},
							    datadir	=> $definition->{datadir},
							    host	=> $definition->{host},
							    port	=> $definition->{port},
							    limits	=> $definition->{limits},
							    contact	=> $definition->{contact},
							    password	=> $definition->{password}
							};

    $self->{log}->debug("[dbMgr::Config] add_daemon: adding '%s' daemon configuration", $definition->{user});

    return 1;

}

sub check_ports {

    return unless defined wantarray; # in void context we cannot do anything

    my $self = shift;
    my $record = shift;
    my @ports = ();
    my @intervals = ();
    my $conversion_error = 0; # 0 - no error, 1 - some intervals were ignored, 2 - no valid intervals were found

    @intervals = split(/,/,$record);

    foreach (@intervals) {
	unless (/^\d+-?\d+$/) {
	    print "invalid port interval specified '$_', skipping\n";
	    $conversion_error = 1;
	    next;
	};

	my ($start, $end) = split(/-/);

	for (my $port = $start; $port <= (defined($end) ? $end : $start); $port++) {
	    push @ports, $port;
	}
    }

    @ports = sort {$a <=> $b} @ports;
    
    {
	my $prev_port = -1;
	my $index = 0;
	while ($index < @ports) {
	    if ($prev_port == $ports[$index]) {
		splice @ports, $index, 1;
	    }
	    else {
		$prev_port = $ports[$index++]
	    }
	}
    }

    $conversion_error = 2 unless (@ports  > 0);
    
    return wantarray ? ($conversion_error,@ports) : $conversion_error;
}

sub optimize_ports {

    return undef;
}

sub get_unused_ports {

    return unless defined wantarray; # in void context we cannot do anything

    my $self = shift;
    my $db_type = shift;
    my @ports = ();
    my @used_ports = ();
    my $status = 0;
    my $interval = undef;

    if (defined($db_type)) {
	unless (defined $self->{db_types}->{$db_type}) {
	    print "Warning: unknown database type '$db_type'\n";
	    return undef;	
	}

	$interval = $self->{db_types}->{$db_type}->{ports};
    }
    else {
	foreach my $key (keys %{$self->{db_types}}) {
	    if (defined($interval)) {
		$interval .= ',' . $self->{db_types}->{$key}->{ports};
	    }
	    else {
		$interval = $self->{db_types}->{$key}->{ports};
	    }
	}
    }

    ($status, @ports) = $self->check_ports($interval);

    if ($status > 0) {
	if ($status == 1) {
	    print "Warning: at least one port interval was invalid, we just skip it\n";
	}
	else {
	    print "Warning: cannot find usable port interval, bailing out\n";
	    return undef;
	}
    }
    
    foreach my $key (keys %{$self->{daemons}}) {
	foreach (@{$self->{daemons}->{$key}}) {
	    push @used_ports, $_->{port};
	}
    }
    
    {
	my $saved_element;
	my $index = 0;
	while ($index < @ports) {
	    $saved_element = $ports[$index];
	    foreach (@used_ports) {
		if ($_ == $ports[$index]) {
		    splice @ports, $index, 1;
		}
	    }
	    if ($saved_element == $ports[$index]) {
		$index++;
	    }
	}
    }
    
    return wantarray ? @ports : $ports[0];
}

sub del_daemon {
    my $self = shift;

    unless (@_ >= 1 && ref($_[0]) eq 'HASH') {
	die "usage Config->add_daemon(HASHREF) ";
    }

    my $definition = shift;
    my $option = shift;
    
    if (defined($definition)) {
	if (exists($definition->{datadir})) {
	    unless ($definition->{datadir} =~ /\/$/) {
        	$self->{log}->debug("[dbMgr::Config] del_daemon: fixing datadir directory name with ending slash");
		$definition->{datadir} .= "/";
	    }
	}
    }

    if (defined($option) && ($option eq 'relaxed')) {
	my $temp_defs = {};
	$temp_defs->{user} = $definition->{user} if defined($definition->{user});
	$temp_defs->{type} = $definition->{type} if defined($definition->{type});
	$temp_defs->{datadir} = $definition->{datadir} if defined($definition->{datadir});
	$temp_defs->{host} = $definition->{host} if defined($definition->{host});
	$temp_defs->{port} = $definition->{port} if defined($definition->{port});
	$definition = $temp_defs;
    }

    my $work_config = $self->select("user", "."); # Clone config

#    use Dumpvalue; my $dumper = new Dumpvalue; $dumper->dumpValue($work_config);
    foreach my $key (keys %{$definition}) {
	if (defined $definition->{$key}) {
#	print "Searching for " . $definition->{$key} . "\n";
	    $work_config = $work_config->select($key, "^" . $definition->{$key} . "\$");
	}
    }


    if (!defined($work_config->{daemons})) {
	print "Warning: specified daemon not found in the active configuration\n";
        return 1;
    }

    {
	sub search_n_destroy {
	    my $record = shift;
	    my $element = shift;
	    my $definition = shift;
	    
	    my $found = 1;
	    foreach my $key (keys %{$definition}) {
		last unless $found;
		if (defined($record->{$key}) && $record->{$key} ne $definition->{$key}) {
		    $found = 0;
		}
	    }
	    
	    if ($found) {
#		print "Notice: daemon record for system account '" . $record->{user} . "' will be deleted from active configuration\n";
		%$element = ();
	    }
	}
    
	$self->foreach(\&search_n_destroy, $definition);
	
	foreach my $key (keys %{$self->{daemons}}) {
	    my $index = 0;
	    while ($index < @{$self->{daemons}->{$key}}) {
#		print "$key [ $index ] :" . %{@{$self->{daemons}->{$key}}[$index]} . "\n";
		unless(%{@{$self->{daemons}->{$key}}[$index]}) {
		    splice @{$self->{daemons}->{$key}}, $index, 1;
		    next;
		}
		$index++;
	    }
	    delete $self->{daemons}->{$key} unless (@{$self->{daemons}->{$key}});
	}
    
    }

    return 1;
}

sub write_daemon {
    my $self = shift;
    my $class = ref($self) || $self;
    my $current_config = $class->new($self->{config_dir}, 'relaxed');

    sub remove_already_saved {
	my $record = shift;
	my $element = shift;
	my $config = shift;
	
	$config->del_daemon($record, 'relaxed') || die "Troubles during deleting daemons ";
	
    }
    $current_config->foreach(\&remove_already_saved, $self);

    my $filename = $self->{config_dir} . "db-shadow.conf";
    my $filename_pub = $self->{config_dir} . "db-daemons.conf";
    if (!open(CONFIG, ">>$filename")) {
        $self->{log}->debug("[dbMgr::Config] write_daemon: cannot open file '%s' for append", $filename);
        $self->{log}->err("cannot open file '%s' for append", $filename);
	die "cannot append to $filename at ";
    }
    if (!open(CONFIG_PUB, ">>$filename_pub")) {
        $self->{log}->debug("[dbMgr::Config] write_daemon: cannot open file '%s' for append", $filename_pub);
        $self->{log}->err("cannot open file '%s' for append", $filename_pub);
	die "cannot append to $filename_pub at ";
    }

    sub write_line {
	my $record = shift;
	my $element = shift;
	my $filehandle = shift;
	my $is_public = shift;
	
	my $user	= $record->{user}	? $record->{user}	: "";
	my $type	= $record->{type}	? $record->{type}	: "";
	my $version	= $record->{version}	? $record->{version}	: "";
	my $datadir	= $record->{datadir}	? $record->{datadir}	: "";
	my $host	= $record->{host}	? $record->{host}	: "";
	my $port	= $record->{port}	? $record->{port}	: "";
	my $limits	= $record->{limit}	? $record->{limit}	: "";
	my $contact	= $record->{contact}	? $record->{contact}	: "";
	my $password	= $record->{password}	? $record->{password}	: "";

	$datadir =~ s/\/$//; # Remove trailing slash
	print $filehandle "$user:$type:$version:$datadir:$host:$port:$limits:$contact:";
	print $filehandle "$password" unless (defined($is_public) && $is_public == 1);
	print $filehandle "\n";
    }
    lock_file(*CONFIG, 'write');
    lock_file(*CONFIG_PUB, 'write');
    seek(CONFIG, 0, 2); 
    seek(CONFIG_PUB, 0, 2); 
    $self->foreach(\&write_line, *CONFIG, 0);
    $self->foreach(\&write_line, *CONFIG_PUB, 1);
    unlock_file(*CONFIG_PUB);
    unlock_file(*CONFIG);
    close(CONFIG_PUB);
    close(CONFIG);

    return 1;
}

sub count {
    my $self = shift;
    my $class = ref($self) || $self;
    return scalar(keys %{$self->{daemons}});
}

1;
