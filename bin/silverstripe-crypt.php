#!/usr/bin/env php
<?php

/* 
  jeff@initsoft.com
  based on sapphire/security/Security.php (this is the default encryption format for Silverstripe 2.x)
*/

$f = STDIN;
$password = preg_replace('/\n$/', '', fgets($f));
$algorithm = 'sha1';
$salt = '';

// If no salt was provided but we need one we just generate a random one
if(strlen(trim($salt)) == 0) {
  $salt = null;
}

$salt = sha1(mt_rand()) . time();
$salt = substr(base_convert($salt, 16, 36), 0, 50);

// Encrypt the password
if(function_exists('hash')) {
  $password = hash($algorithm, $password . $salt);
}
else {
  $password = call_user_func($algorithm, $password . $salt);
}

// Convert the base of the hexadecimal password to 36 to make it shorter
// In that way we can store also a SHA256 encrypted password in just 64
// letters.
// $password = substr(base_convert($password, 16, 36), 0, 64);

echo("$password $salt\n");
?>
