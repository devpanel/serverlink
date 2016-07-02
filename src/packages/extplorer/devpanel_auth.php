<?php

$curr_path = dirname(__FILE__);
require_once($curr_path . "/../../../../../../lib/php/webapp_token_access.inc.php");

$app_name = "extplorer";

session_name("devpanel_$app_name");
$vhost = dp_derive_gen_vhost();

$user_info = posix_getpwuid(posix_geteuid());

$is_logged_in = dp_is_already_logged_to_app($app_name);

if(!$is_logged_in) {
  echo "Access denied. Unable to verify app token.\n";
  exit(1);
}

global $GLOBALS;

$GLOBALS["require_login"] = false;
$GLOBALS["home_dir"     ] = $user_info["dir"];

?>
