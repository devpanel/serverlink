<?php

$curr_path = dirname(__FILE__);
require_once($curr_path . "/../../../../../../lib/php/webapp_token_access.inc.php");

$app_name = "extplorer";

session_name("devpanel_$app_name");
$vhost = dp_derive_gen_vhost();

$user_info = posix_getpwuid(posix_geteuid());

$is_logged_in = dp_is_already_logged_to_app($app_name);

if(!$is_logged_in) {
  header("Status: 401 Unauthorized");
  echo "Access denied. Unable to verify app token.\n";
  exit(1);
}

global $GLOBALS;

$GLOBALS["require_login"] = false;
$GLOBALS["home_dir"     ] = $user_info["dir"];

// when session.save_path is not defined, extplorer tries to create sessions 
// on it's own directory, but in devPanel's case it's not writable. So have 
// to set it to a writable path
if(empty(ini_get('session.save_path'))) {
  ini_set('session.save_path', "/tmp");
}

?>
