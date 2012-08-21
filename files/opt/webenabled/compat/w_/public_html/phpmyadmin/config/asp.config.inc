<?php
$current_user = rtrim(`id -un 2>/dev/null`); // get_current_user();
/* modified by grg for mod_php compatibility */
if (!($current_user[0] == 'w' && $current_user[1] === '_')) {
 if (preg_match('/^\/home\/clients\/websites\/(w_[^\/]+)/', $_SERVER["DOCUMENT_ROOT"], $matches))
   $current_user = $matches[1];
 else
  return 0;
}
$current_user = preg_replace("/^w_/","b_",$current_user);


$i = 0;
$db_daemons_handle = fopen('/opt/webenabled/config/os/pathnames/opt/dbmgr/config/db-daemons.conf', "r", 0);
if ($db_daemons_handle == false) {
	echo "Error reading db-daemons.conf, aborting!<br />";
	return false;
}

while (!feof($db_daemons_handle)) {
   if ($db_daemons_line = fgets($db_daemons_handle)) {
       if (preg_match('/^\s*(#.*)?$/', $db_daemons_line)) continue;
       list ($name,$type,$vers,$homedir,$ip,$port,$tail) = explode(':',$db_daemons_line,7);
       if ($name == $current_user) {
           $i++;
           $cfg['Servers'][$i]['host'] = "$ip:$port";
//           $cfg['Servers'][$i]['port'] = $port;
           $cfg['Servers'][$i]['socket'] = '';
           $cfg['Servers'][$i]['connect_type'] = 'tcp';
           $cfg['Servers'][$i]['extension'] = 'mysql';
           $cfg['Servers'][$i]['compress'] = false;
           $cfg['Servers'][$i]['auth_type'] = 'cookie';
       }
    } else {
        if ($db_daemons_line == false) break;
   }
}
fclose($db_daemons_handle);

unset($name,$type,$vers,$homedir,$ip,$port,$tail,$db_daemons_line,$db_daemons_handle,$current_user);
?>
