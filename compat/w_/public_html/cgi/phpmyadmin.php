<?php

$curr_path = dirname(__FILE__);
require_once($curr_path . "/../../../../lib/php/webapp_token_access.inc.php");

$app_name = "phpmyadmin";

session_name("devpanel_$app_name");
$vhost = dp_derive_gen_vhost();

$is_logged_in = dp_is_already_logged_to_app($app_name);

if(!$is_logged_in) {
  if(($token = dp_get_app_token_from_url()) && dp_has_valid_token($vhost, $app_name, $token)) {
    dp_start_app_session($vhost, $app_name);
    header('Location: ' . str_replace("/$token", "/", $_SERVER['SCRIPT_URI']) . '/index.php');
    exit(0);
  } else {
    echo "Access denied. Unable to verify app token.\n";
    exit(1);
  }
}

if(isset($_SERVER["PATH_INFO"])) {
  $file = $_SERVER["PATH_INFO"];
} else {
  header('Location: ' . str_replace("/$token", "/", $_SERVER['SCRIPT_URI']) . '/index.php');
  exit;
}

$file_path = sprintf("%s/../%s/current/%s", dirname(__FILE__), $app_name, $file);
$_SERVER["PATH_INFO"] = $_SERVER["SCRIPT_NAME"];
$_SERVER["SCRIPT_NAME"] = $file;
chdir(dirname($file_path));
require_once($file_path);
?>
