#!/opt/webenabled/config/os/pathnames/bin/php -q
<?php
// integrated by Vinicius Mello  http://vmmello.eti.br/

// from includes/GlobalFunctions.php
function wfGenerateToken( $salt = '' ) {
  $salt = serialize($salt);
  return md5( mt_rand( 0, 0x7fffffff ) . $salt );
}

// from includes/User.php :: function crypt()
// not copied verbatim
function mediawiki_crypt($password, $salt) {
  return ':B:' . $salt . ':' . md5( $salt . '-' . md5( $password ) );
}

$f = STDIN;
$password = fgets($f);
$salt  = substr(wfGenerateToken(), 0, 8);
$value = mediawiki_crypt($password, $salt);
echo("$value\n");

?>
