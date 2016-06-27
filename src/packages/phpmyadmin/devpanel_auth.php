<?php

$curr_path = dirname(__FILE__);
require_once($curr_path . "/../../../../../../lib/php/webapp_token_access.inc.php");

$app_name = "phpmyadmin";

session_name("devpanel_$app_name");
$vhost = dp_derive_gen_vhost();

$user_info = posix_getpwuid(posix_geteuid());

$is_logged_in = dp_is_already_logged_to_app($app_name);

if(!$is_logged_in) {
  echo "Access denied. Unable to verify app token.\n";
  exit(1);
}

// some default settings, that can be overwritten by $local_config and 
// $vhost_config (see both below)
$mysql_ini = sprintf("%s/.my.cnf", $user_info["dir"]);
if(file_exists($mysql_ini)) {
  global $cfg;
  $mysql_info = parse_ini_file($mysql_ini);
  $cfg["ServerDefault"] = 1;
  $cfg["Servers"][1]["auth_type"] = "config";
  $cfg["Servers"][1]["host"] = $mysql_info["host"] ;
  $cfg["Servers"][1]["port"] = $mysql_info["port"];
  $cfg["Servers"][1]["user"] = $mysql_info["user"];
  $cfg["Servers"][1]["password"] = $mysql_info["password"];
} else {
  echo "Error: missing ~/.my.cnf on the target vhost";
  exit(1);
}

$local_config = "$curr_path/config.local.inc.php";
$vhost_config = sprintf("%s/.devpanel/phpmyadmin/config.inc.php", $user_info["dir"]);

if(file_exists($local_config)) {
  require_once($local_config);
}

if(file_exists($vhost_config)) {
  require_once($vhost_config);
}

?>
