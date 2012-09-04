package Cloudenabled::Tasks::Install_Token;
use base 'CGI::Application';

use Socket;
use Cloudenabled::Constants;
use Cloudenabled::Util;
use Cloudenabled::Tasks::Util;
use Cloudenabled::Controller::Util;
use Cloudenabled::RPCComm;

our $param_separator = ';';

sub setup {
  my $app = shift;
  my @modes = (
                  'install_token'         => 'install_token',
                  'AUTOLOAD'              => 'error_log',
              );
              #    validation_error error_log sig_err list set_state report 
              #    get_next list2run update_dns set_running );
  
  $app->mode_param('op');
  $app->start_mode('error_log'); # unknown modes go here
  $app->error_mode('error_log');
  $app->run_modes(@modes);
}

sub cgiapp_init {
  my $app = shift;

  my $ctlconn = Cloudenabled::RPCComm->new( connect_address => 'unix:/tmp/controllerd_socket');
  if(!$ctlconn) {
    warn "Error: unable to connect to controller\n";
    exit(1);
  }

  $app->param('ctlconn', $ctlconn);
}

sub cgiapp_postrun {
  my($app, $output) = @_;

  my $output_len = length($$output);
  if($output_len > 0 && substr($$output, $output_len-1) ne "\n") {
    $$output .= "\n";
  }
}

sub error_log {
  my($app, $msg) = @_;

  return $msg || 'unknown error';
}

sub install_token {
  my $app = shift;
  my $cgi = $app->query;
  my $ctl = $app->param('ctlconn');

  my $token = $cgi->param('token');

  if(!$token) {
    return 'missing token';
  } elsif(length($token) != 12 || $token !~ /^\w+$/) {
    return 'invalid token format';
  }

  my $ret_r = $ctl->op('get_install_info', { token_str => $token });

  my $uuid       = $ret_r->{uuid};
  my $secret_key = $ret_r->{secret_key};
  my $file       = $app->param('install_script_file');
  my $sed_path   = $app->param('sed_path');

  my $output;
  if(ce_was_successful($ret_r)) {
    $output = qx|$sed_path -e "s/%%SERVER_UUID%%/$uuid/; s/%%SECRET_KEY%%/$secret_key/;" $file|;
    return $output;
  } else {
    return "error, unable to retrieve the information";
  }
}

1;
