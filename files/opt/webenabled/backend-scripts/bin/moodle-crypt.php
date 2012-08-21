#!/opt/webenabled/config/os/pathnames/bin/php -q
<?php
$u_hash   = posix_getpwuid(posix_geteuid());
$v_host   = $u_hash['name'];

if(preg_match('/^w_/', $u_hash['name'])) {
  $v_host = substr($u_hash['name'], 2);
}

$moodle_conf = $_SERVER['HOME'] . "/public_html/{$v_host}/config.php";

$fd = fopen($moodle_conf, "r");

# example line: $CFG->passwordsaltmain = 'hRlnUVZ=(@RU9?uHN&[<5EXLVdVd!O{1';
$str = '$CFG->passwordsaltmain =';

while($line = fgets($fd)) {
  if(substr($line, 0, strlen($str)) == "$str") {
    $salt = substr($line, strlen($str) + 2, strlen($line) - 2 - strlen($str) - 3);
    break;
  }
}
fclose($fd);

$stderr = fopen('php://stderr', 'w');
fprintf($stderr, "Olha o sal %s\n", $salt);

$f = STDIN;
$password = fgets($f);
if(!isset($salt)) {
  $value = md5($password);
} else {
  $value = md5($password . $salt);
}

echo("$value\n");
?>
