#!/usr/bin/env php
<?php
$f = STDIN;
$password = fgets($f);
$salt = substr(md5(microtime() . rand()), 0, 8);
$value = md5($password . $salt);
$secret = md5(rand() . microtime());
echo("$value $salt $secret");
?>
