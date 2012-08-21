#!/usr/bin/perl


#use lib qw(/home/clients/websites/w_cgit/perl/lib/perl5/site_perl/5.8.8/);

use CGI qw(:standard);
use CGI::Cookie;
use Digest::HMAC_SHA1 qw(hmac_sha1 hmac_sha1_hex);
#use DateTime;
use POSIX qw(strftime);

$hmac_key_cookie = "";

$base_repo_path = "/home/clients/repos/";
$cgit_path = '/home/clients/websites/w_cgit/bin/cgit';
$add_repo_path = "/repos/";
$user = "";
$hmac_secret_path = "/.cgit-hmac-secret";
$public_path = "/.cgit-public-ok";
$cache_path = "/.cgit-cache";

$git_path = "/opt/git/current/bin/";
#$git_path = "";
if ($git_path ne "") {
    $ENV{PATH} .= ":".$git_path;
    #print "$ENV{PATH}\n";
}

@safe_qs = (
#"r", #NO!
#"p", #NO!
 #"url", #NO!
 "qt", #OK
 "q", #OK
 "h", #OK XXX: maybe also filter by branch? :)
 "id", #OK
 "id2", #OK
 "ofs", #OK
 #"path", #NO!
 #"name", #NO!
 "mimetype", #OK
 "s", #OK
 "showmsg", #OK
 "period", #OK
 "ss", #OK
 "all", #HUH?
 "context", #OK
 "ignorews" #OK
);


#print header;
if (0) {
    print header;
    foreach $key (sort keys(%ENV)) {
        print "$key = $ENV{$key}<p>";
    }
}

sub error {
    my $msg = $_[0];

    if ($hmac_key_cookie) {
        print header(-cookie=>[$hmac_key_cookie]);
    } else {
        print header;
    }

    print "Error: $msg";
    exit 1;
}

sub delete_cookie {
    $hmac_key_cookie = new CGI::Cookie(
            -name =>'key',
            -expires => '0',
            -path => "/$user/",
            -value => '');
}

sub get_user_key {
    my %cookies = fetch CGI::Cookie;
    my $user_key = "";
    if (defined $cookies{'key'}) {
        $user_key = $cookies{'key'}->value;
    } elsif (defined param("key")) {
        $user_key = param('key');
    }

    return $user_key;
}

sub read_hmac_secret {
    my $fname = $base_repo_path . $user . $hmac_secret_path;
    #print "<p>path = ".$fname."<p>";
    
    open(F, '<', $fname) or error("No such repository");
    my @lines = <F>;
    close(F);
    #print "<p>secret = '".$lines[0]."'<p>";
    chomp($lines[0]);
    return $lines[0];
}

sub check_key {
    my ($secret, $delta, $key) = @_;

    my $stamp = strftime "%Y-%m-%d-%H", (gmtime(time+$delta));
    my $hmac = Digest::HMAC_SHA1->new($secret);
    my $msg = $stamp;

    $hmac->add($msg);
    my $result = $hmac->hexdigest;

    #print header;
    #print "result = $result<p>";

    if ($result eq $key) {
        $hmac_key_cookie = new CGI::Cookie(
                -name =>'key',
                -path => "/$user/",
                -expires => "+1h",
                -value => $key);
        return 1;
    }
    return 0;
}

sub is_public_repo {
    my $repo = $_[0];
    if (defined $repo) {
        return -e $base_repo_path.$user.$add_repo_path.$repo.$public_path;
    } else {
        return -e $base_repo_path.$user.$add_repo_path.$public_path;
    }
}

sub check_permissions {
    my $repo = $_[0];
    my $secret_key = read_hmac_secret;
    my $user_key = get_user_key;

    if (not check_key($secret_key, 0, $user_key) and
        not check_key($secret_key, 3600, $user_key) and
        not check_key($secret_key, -3600, $user_key) and
        not is_public_repo($repo))
    {
        delete_cookie;
        error("Access denied (wrong key)");
    }
}

sub run_cgit {
    my $cache_root = $base_repo_path.$user.$cache_path;

    if ($hmac_key_cookie) {
        print header(-cookie=>[$hmac_key_cookie]);
    } else {
        print header;
    }

    exec $cgit_path, 'cgit', '--nohttp', "--cache=$cache_root";
    error("Access denied");
}

$uri = $ENV{SCRIPT_NAME};

$clean_qs = "";
if (1) {
    foreach $p (@safe_qs) {
        if (param($p)) {
            $clean_qs .= "&$p=".param($p);
        }
    }
    #print "qs = $clean_qs<p>";
}

# /user/
if (($user) = ($uri =~ /^\/([a-zA-Z0-9_-]+)\/*$/)) {
    #print "User = " .$user."<p>";
    $ENV{CGIT_CONFIG} = $base_repo_path . $user . $add_repo_path . "/cgitrc";
    $ENV{QUERY_STRING} = $clean_qs;

    check_permissions;

    #print "CGIT_CONFIG = $ENV{CGIT_CONFIG}, QUERY_STRING = $ENV{QUERY_STRING}<p>";
    run_cgit;
}

# /user/repo/?query
if (($user, $repo, $add) = ($uri =~ /^\/([a-zA-Z0-9_-]+)\/+([a-zA-Z0-9_-]+)(\/+.*)?$/)) {
    #print "User = " .$user.", repo = ".$repo.", query = $safe_qs";
    $ENV{CGIT_CONFIG} = $base_repo_path . $user . $add_repo_path . $repo . "/cgitrc";
    $ENV{QUERY_STRING} = "url=".$repo.$add."&".$clean_qs;
    $ENV{SCRIPT_NAME} = "/".$user;

    check_permissions($repo);

    run_cgit;
}

error("Bad URL");
