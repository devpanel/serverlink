#!/usr/bin/env php
<?php
$u_hash   = posix_getpwuid(posix_geteuid());
$user     = $u_hash['name'];

$vhost_link = realpath(dirname(__FILE__) . "/../../..") . "/config/key_value/linuxuser-vhost/{$user}";
if(!($vhost = readlink($vhost_link))) {
  error_log("Error: unable to find vhost for current user");
  exit(1);
}

$random_int_inc = $u_hash["dir"] . "/public_html/{$vhost}/vendor/paragonie/random_compat/lib/random.php";
$pass_hash_inc  = $u_hash["dir"] . "/public_html/{$vhost}/inc/PassHash.class.php";

if(!file_exists($random_int_inc)) {
  error_log("Error: missing file $random_int_inc");
  exit(1);
} else if(!file_exists($pass_hash_inc)) {
  error_log("Error: missing file $pass_hash_inc");
  exit(1);
}


require_once($random_int_inc);
require_once($pass_hash_inc);

$fh = fopen("php://stdin", "r");
if(posix_isatty($fh)) {
  echo "Reading password from STDIN: ";
}

$password = fgets($fh);
if(is_null($password) || strlen($password) == 0 || strlen(rtrim($password)) == 0) {
  echo "Error: got an empty password.\n";
}
fclose($fh);

$password = rtrim($password);

$pass_hash_obj = new PassHash();
$hashed_pw = $pass_hash_obj->hash_smd5($password);

echo("$hashed_pw");
?>

