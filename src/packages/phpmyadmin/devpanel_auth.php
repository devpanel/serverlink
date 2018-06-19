<?php

$curr_path = dirname(__FILE__);
require_once($curr_path . "/../../../../../lib/php/webapp_token_access.inc.php");

$app_name = "phpmyadmin";

session_name("devpanel_$app_name");

$is_logged_in = dp_is_already_logged_to_app($app_name);

if(!$is_logged_in) {
  echo "Access denied. Unable to verify app token.\n";
  exit(1);
}

if(!($mysql_info_ar = devpanel_get_mysql_info_for_vhost())) {
  error_log("unable to read MySQL credentials");
  echo "Error: unable to read MySQL credentials\n";
  exit(1);
}

// some default settings, that can be overwritten by $local_config and 
// $vhost_config (see both below)

global $cfg;
$cfg["ServerDefault"] = 1;
$cfg["Servers"][1]["auth_type"] = "config";
$cfg["Servers"][1]["host"] = $mysql_info_ar["client"]["host"] ;
$cfg["Servers"][1]["port"] = $mysql_info_ar["client"]["port"];
$cfg["Servers"][1]["user"] = $mysql_info_ar["client"]["user"];
$cfg["Servers"][1]["password"] = $mysql_info_ar["client"]["password"];
$cfg["Servers"][1]["hide_db"] = '^(mysql|information_schema|performance_schema|sys)$';

// fix for PHPMyAdmin versions >= 4.8.0
$user_info = posix_getpwuid(posix_geteuid());

if(!isset($cfg['TempDir']) || (!file_exists($cfg['TempDir']) || !is_writable($cfg['TempDir']))) {
  $tmp_in_home_dir = "{$user_info["dir"]}/tmp/phpmyadmin";
  if(file_exists($tmp_in_home_dir)) {
    $cfg['TempDir'] = $tmp_in_home_dir;
  } else {
    if(@mkdir($tmp_in_home_dir, 0700, TRUE)) {
      $cfg['TempDir'] = $tmp_in_home_dir;
    }
  }
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
