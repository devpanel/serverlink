#!/usr/bin/env php
<?php

/* 
  jeff@initsoft.com
  based on core/authentication_api.php (this is the default encryption format for Mantis 1.1.x)
*/

$f = STDIN;
$password = fgets($f);
$value = md5(preg_replace('/\n$/', '', $password));
echo("$value\n");

?>
