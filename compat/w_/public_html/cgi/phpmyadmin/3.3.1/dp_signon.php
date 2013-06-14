<?php
/* vim: set expandtab sw=4 ts=4 sts=4: */

require_once('/opt/webenabled/lib/php/webapp_token_access.inc.php');

function show_error($msg)
{
    header('Content-Type: text/html; charset=utf-8');
    echo '<?xml version="1.0" encoding="utf-8"?>' . "\n";
    ?>
<!DOCTYPE HTML>
<html lang="en" dir="ltr">
<head>
    <link rel="icon" href="favicon.ico" type="image/x-icon" />
    <link rel="shortcut icon" href="../favicon.ico" type="image/x-icon" />
    <meta charset="utf-8" />
    <title>DP phpMyAdmin</title>
    <style>body{font-family: monospace;}</style>
</head>
<body>
  <h1>Error</h1>
  <p><?php echo $msg ?></p>
</body>
</html>
<?php

exit;
}


$token = dp_get_token_from_params();
if (!$token) {
    show_error('Authentication token missing');
}

$vhost = dp_derive_gen_vhost();
$app   = 'phpmyadmin';
if (!dp_has_valid_token($vhost, $app, $token)) {
    show_error('Invalid token');
}

/* Need to have cookie visible from parent directory */
session_set_cookie_params(0, dirname($_SERVER['REQUEST_URI']) . '/', '', 0);
session_name('DPSignonSession');
session_start();

$user_info = posix_getpwuid(posix_geteuid());
$mysql_ini = sprintf("%s/.my.cnf", $user_info["dir"]);

if(!file_exists($mysql_ini)) {
  show_error('missing ~/.my.cnf on the target vhost');
}

$mysql_info = parse_ini_file($mysql_ini);

$_SESSION['PMA_single_signon_user']     = $mysql_info['user'];
$_SESSION['PMA_single_signon_password'] = $mysql_info['password'];
$_SESSION['PMA_single_signon_host']     = $mysql_info['host'];
$_SESSION['PMA_single_signon_port']     = $mysql_info['port'];

session_write_close();

header('Location: ' . dirname($_SERVER['SCRIPT_URI']) . '/index.php');
?>
