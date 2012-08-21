#!/opt/webenabled/config/os/pathnames/bin/php -q
<?php

/*  grg@initsoft.com */

/* based on application/models/users/User.class.php */

$f = STDIN;
$password = fgets($f);
$salt = substr(sha1(uniqid(rand(), true)), rand(0, 25), 13);
$token = sha1($salt . $password);
echo("$token:$salt\n");

?>
