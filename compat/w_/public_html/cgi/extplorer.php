<?php

$curr_path = dirname(__FILE__);
require_once($curr_path . "/../../../../lib/php/webapp_token_access.inc.php");
$extplorer_dir = sprintf("%s/../extplorer/current", $curr_path);

$app_name = "extplorer";
session_name($app_name);

$vhost = dp_derive_gen_vhost();

$is_logged_in = dp_is_already_logged_to_app($app_name);

if(!$is_logged_in && !($token = dp_get_app_token_from_url())) {
  echo "Access denied. Unable to verify app token.\n";
  exit(1);
} else if(!$is_logged_in && dp_has_valid_token($vhost, $app_name, $token)) {
  dp_start_app_session($vhost, $app_name, $token);
  header('Location: ' . str_replace("/$token", "", $_SERVER['SCRIPT_URI']) . '/index.php');
  exit;
} else if($is_logged_in && dp_get_app_token_from_url()) {
  $file = 'index.php';
}

$file = isset($file) ? $file : basename($_SERVER['PATH_INFO']);

if ($file == '') {
        header('Location: ' . str_replace("/$token", "", $_SERVER['SCRIPT_URI']) . '/index.php');
        exit;
}

if ($file == 'index.php')
{
	if (isset($_GET['action']) && $_GET['action'] == 'logout')
		setcookie('we_logout');

	if (isset($_GET['mode']) && $_GET['mode'] == '1')
		$_SESSION['xtp_wrapper_advanced_user'] = true;
	elseif (empty($_GET['mode']))
		$_SESSION['xtp_wrapper_advanced_user'] = false;
}

$home = isset($_ENV['XTP_HOME']) ? $_ENV['XTP_HOME'] : '';
if ($home == '')
{
	$user_info = posix_getpwuid(posix_geteuid());
	$home = $user_info['dir'];
}

$_SERVER['DOCUMENT_ROOT'] = $home;

chdir($extplorer_dir);
require_once($file); //($file == '' ? 'index.php' : $file));

?>
