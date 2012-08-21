<?php 
	// ensure this file is being included by a parent file
	if( !defined( '_JEXEC' ) && !defined( '_VALID_MOS' ) ) die( 'Restricted access' );
        $current_user = rtrim(`id -un 2>/dev/null`); // get_current_user();
        if ($current_user[0] == 'w' && $current_user[1] === '_') {
            #$current_user = preg_replace("/^w_/","b_",$current_user);
        } else return false;
        $home = $_SERVER['DOCUMENT_ROOT']."/../..";
        function get_password($current_user, $home)
        {
          
          if (!($f = fopen("$home/.mysql.passwd", "r"))) die();
          $l = strlen($current_user);
          while(($s = fgets($f)) != FALSE)
          {
            $s = rtrim($s);
            if (strlen($s) <= $l + 2 || substr($s, 0, $l) != $current_user || $s[$l] != ':') continue;
            return substr($s, $l+1);
          }
        }
        if (strlen($current_user) <= 0) return false;
        $password = get_password($current_user, $home);
        if (strlen($password) <= 0) return false;
	$GLOBALS["users"]=array(
	array($current_user,md5($password),$home,"http://localhost",1,"",7,1),
); 
?>
