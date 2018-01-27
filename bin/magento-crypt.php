#!/usr/bin/env php
<?php

/* 
  grg@initsoft.com
  based on app/code/core/Mage/Core/Helper/Data.php
*/

function getRandomString($len, $chars=null)
{
if (is_null($chars)) {
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
}
mt_srand(10000000*(double)microtime());
for ($i = 0, $str = '', $lc = strlen($chars)-1; $i < $len; $i++) {
    $str .= $chars[mt_rand(0, $lc)];
}
return $str;
}

/**
* Generate salted hash from password
*
* @param string $password
* @param string|integer|boolean $salt
*/
function getHash($password, $salt=false)
{
if (is_integer($salt)) {
    $salt = getRandomString($salt);
}
return $salt===false ? md5($password) : md5($salt.$password).':'.$salt;
}

$f = fopen("php://stdin","r");
$password = fgets($f);
$value = getHash($password, 2);
echo("$value\n");

?>
