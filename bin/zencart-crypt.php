#!/usr/bin/env php
<?php
  function zen_encrypt_password($plain) {
    $password = '';

    for ($i=0; $i<10; $i++) {
      $password .= zen_rand();
    }

    $salt = substr(md5($password), 0, 2);

    $password = md5($salt . $plain) . ':' . $salt;

    return $password;
  }

  function zen_rand($min = null, $max = null) {
    static $seeded;
    
    if (!$seeded) {
      mt_srand((double)microtime()*1000000);
      $seeded = true;
    }
      
    if (isset($min) && isset($max)) {
      if ($min >= $max) {
        return $min;
      } else {
        return mt_rand($min, $max);
      }
    } else {
      return mt_rand();
    }
  }

$f = STDIN;
$password = fgets($f);
$value = zen_encrypt_password($password);
echo("$value");
?>
