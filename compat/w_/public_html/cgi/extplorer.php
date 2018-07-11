<?php

$curr_path = dirname(__FILE__);
require_once($curr_path . "/../../../../lib/php/webapp_token_access.inc.php");

$app_name = "extplorer";
session_name("devpanel_$app_name");

$vhost = dp_get_vhost_from_user();

$is_logged_in = dp_is_already_logged_to_app($app_name);

$token = dp_get_app_token_from_url();
if(!$is_logged_in) {
  if(empty($token)) {
    echo "Access denied. Unable to verify app token.\n";
    exit(1);
  }

  if(dp_has_valid_token($vhost, $app_name, $token)) {
    dp_start_app_session($vhost, $app_name, $token);
    header('Location: ' . str_replace("/$token", "", $_SERVER['SCRIPT_URI']) . '/index.php');
    exit;
  } else {
    echo "Access denied. Unable to verify app token.\n";
    exit(1);
  }
} else {
  if(empty($token)) {
    header('Location: ' . $_SERVER['SCRIPT_URI'] . '/index.php');
  } else {
    header('Location: ' . str_replace("/$token", "", $_SERVER['SCRIPT_URI']) . '/index.php');
  }
  exit;
}
