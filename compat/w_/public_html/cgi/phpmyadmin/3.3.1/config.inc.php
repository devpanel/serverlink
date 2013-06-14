<?php
$i = 0;
$i++;
$cfg['Servers'][$i]['extension']     = 'mysqli';
$cfg['Servers'][$i]['auth_type']     = 'signon';
$cfg['Servers'][$i]['SignonSession'] = 'DPSignonSession';
$cfg['Servers'][$i]['SignonURL']     = 'dp_signon.php';
$cfg['Servers'][$i]['LogoutURL']     = 'dp_logout.php';
?>
