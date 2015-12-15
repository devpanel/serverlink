<?php

$curr_path = dirname(__FILE__);
require_once($curr_path . "/../../../../lib/php/webapp_token_access.inc.php");

$app_name = "phpmyadmin";

session_name("devpanel_$app_name");
$vhost = dp_derive_gen_vhost();

$is_logged_in = dp_is_already_logged_to_app($app_name);

if(!$is_logged_in) {
  if(($token = dp_get_app_token_from_url()) && dp_has_valid_token($vhost, $app_name, $token)) {
    dp_start_app_session($vhost, $app_name, $token);
    header('Location: ' . str_replace("/$token", "", $_SERVER['SCRIPT_URI']) . '/index.php');
    exit(0);
  } else {
    echo "Access denied. Unable to verify app token.\n";
    exit(1);
  }
}

if(isset($_SERVER["PATH_INFO"])) {
  if($_SERVER["PATH_INFO"] == "/" . $_SESSION["token"]) {
    $file = "index.php";
  } else {
    $file = $_SERVER["PATH_INFO"];
  }
} else {
  header('Location: ' . str_replace("/$token", "/", $_SERVER['SCRIPT_URI']) . '/index.php');
  exit;
}

$file_dir  = sprintf("%s/../%s/current", dirname(__FILE__), $app_name);
$file_path = "$file_dir/$file";
if(!@stat($file_path)) {
  // if the user is logged in, but the url passed doesn't translate to a file,
  // then redirect to index.php
  header('Location: ' . str_replace($_SERVER["PATH_INFO"], "", $_SERVER['SCRIPT_URI']) . '/index.php');
  exit(0);
}

$_SERVER["PATH_INFO"] = $_SERVER["SCRIPT_NAME"];
$_SERVER["SCRIPT_NAME"] = $file;

set_include_path(sprintf("%s:%s", $file_dir, get_include_path()));
chdir($file_dir);

session_write_close(); // phpmyadmin is picky...it wants to open it's own session or returns error
require_once($file_path);
?>
