<?php
setcookie('DPSignonSession', '', 1, dirname($_SERVER['REQUEST_URI']) . '/');
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
  <h1>Logged out</h1>
  <p>You can close the window now.</p>
</body>
</html>

