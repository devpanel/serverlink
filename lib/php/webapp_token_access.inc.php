<?php

define('DEVPANEL_TOKEN_LEN', 50);
define('DEVPANEL_DIR', realpath(dirname(__FILE__) . "/../.."));

// for apps that set an unwritable save_path (e.g. extplorer),
// it's needed to workaround with this
$session_path = ini_get('session.save_path');
if(!empty($session_path) && !@is_writable($session_path)) {
  ini_set('session.save_path', "/tmp");
}

function dp_has_valid_token($vhost, $app, $token_str) {
  $ret = false;
  $token_file = sprintf("%s/var/tokens/%s.%s.%s", DEVPANEL_DIR, $vhost, $app, $token_str);

  /* open file for read/write, fail if doesn't exist */
  $token_fd = fopen($token_file, 'r');
  if (!$token_fd) {
    return false;
  }

  $ret =
    /* try to acquire exclusive lock, fail otherwise */
    flock($token_fd, LOCK_EX | LOCK_NB) &&
    /* mtime == 0 means the token has been already used */
    (filemtime($token_file) != 0) &&
    /* touch the file to mark it as used */
    touch($token_file, 0);

  /* closing the file releases the lock */
  fclose($token_fd);
  return $ret;
}

function dp_is_already_logged_to_app($app) {
  // if(session_status() == PHP_SESSION_ACTIVE) {
  if(!empty($_SESSION)) {
    // there's an existing session
    if(session_name != "devpanel_$app") {
      $previous_session_name = session_name();
      session_write_close();
      if(!empty($_COOKIE["devpanel_$app"])) {
        session_id($_COOKIE["devpanel_$app"]);
      } else {
        return false;
      }
      session_name("devpanel_$app");
      session_start();
    }
  } else {
    // no session available
    if(!empty($_COOKIE["devpanel_$app"])) {
      session_id($_COOKIE["devpanel_$app"]);
    } else {
      return false;
    }
    session_name("devpanel_$app");
    session_start();
  }

  if(!empty($_SESSION) && !empty($_SESSION['app']) && $_SESSION['app'] == $app) {
    session_write_close();

    // if there was another session before, then re-open it
    if(!empty($previous_session_name)) {
      session_name($previous_session_name);
      session_start();
    }

    return true;
  } else {
    return false;
  }
}

function dp_get_config_array() {
  $ini_file = sprintf("%s/config/defaults.ini", DEVPANEL_DIR);
  if($cfg_ar = parse_ini_file($ini_file, TRUE)) {
    $cfg_ar["paths"]["lamp"]["config_dir"] = 
      sprintf("%s/lamp", $cfg_ar["paths"]["local_config_dir"]);

    $cfg_ar["paths"]["lamp"]["vhosts"]["config_dir"] = 
      sprintf("%s/vhosts", $cfg_ar["paths"]["lamp"]["config_dir"]);

    $cfg_ar["paths"]["lamp"]["user_vhost_map"] = 
      sprintf("%s/linuxuser-vhost-map", $cfg_ar["paths"]["lamp"]["config_dir"]);


    return $cfg_ar;
  } else {
    error_log("failed to load ini file '$ini_file'");
    return FALSE;
  }
}

function dp_get_vhost_config_array($vhost) {
  $dp_config_ar = dp_get_config_array();

  $vhost_config_dir = sprintf("%s/%s",
    $dp_config_ar["paths"]["lamp"]["vhosts"]["config_dir"],
    $vhost);

  $vhost_ini_file = sprintf("%s/config.ini", $vhost_config_dir);

  if($cfg_r = parse_ini_file($vhost_ini_file, TRUE)) {
    $cfg_r["paths"]["config_dir"] = $vhost_config_dir;

    if(isset($cfg_r["mysql"]["instance"])) {
      $my_cnf_file = sprintf("%s/mysql/my.cnf", $cfg_r["paths"]["config_dir"]);
      if(file_exists($my_cnf_file) && is_readable($my_cnf_file)) {
        $cfg_r["paths"]["mysql"]["my_cnf"] = $my_cnf_file;
      }
    }

    return $cfg_r;
  } else {
    error_log("error parsing file '$vhost_ini_file'");
    return FALSE;
  }
}

function dp_get_vhost_from_user($username = NULL) {
  if(is_null($username)) {
    if($user_info = posix_getpwuid(posix_geteuid())) {
      $username = $user_info["name"];
    }
  }

  $dp_config_ar = dp_get_config_array();
  
  $ref_link_dir = $dp_config_ar["paths"]["lamp"]["user_vhost_map"];

  $link = sprintf("%s/%s", $ref_link_dir, $username);

  if(is_link($link)) {
    $vhost = readlink($link); 
    return $vhost;
  } else {
    error_log("missing link file '$link'");
    return NULL;
  }
}

function dp_derive_gen_vhost() {
  $user_info = posix_getpwuid(posix_geteuid());

  // try to get the user from the user -> vhost map
  $vhost = dp_get_vhost_from_user($user_info["name"]);
  if(!is_null($vhost)) {
    return $vhost;
  }

  // as there wasn't a user -> vhost map, then get the vhost name from the
  // username
  if(strlen($user_info['name']) > 2 && substr($user_info['name'], 0, 2) == "w_") {
    $vhost = substr($user_info['name'], 2);
  } else {
    $vhost = $user_info['name'];
  }

  return $vhost;
}

function devpanel_get_mysql_info_for_vhost($vhost = NULL) {
  if(is_null($vhost)) {
    if(!$vhost = dp_get_vhost_from_user()) {
      return FALSE;
    }
  }

  if($my_cnf_ar = dp_parse_vhost_my_cnf($vhost)) {
    return $my_cnf_ar;
  } else {
    return FALSE;
  }
}

function dp_parse_vhost_my_cnf($vhost) {
  if(!($vhost_cfg_ar = dp_get_vhost_config_array($vhost))) {
    error_log("failed to parse vhost config");
    return FALSE;
  }

  // PHP doesn't merge sections if the same section appears in more than one
  // file. So it's needed to do this merge here with array_merge_recursive()
  $my_cnf_ar = array();

  if(isset($vhost_cfg_ar["paths"]["mysql"]["my_cnf"])) {
    $my_cnf_file = $vhost_cfg_ar["paths"]["mysql"]["my_cnf"];
    if(!($raw_cnf_txt = file_get_contents($my_cnf_file))) {
      error_log("failed to get contents from file '$my_cnf_file'");
      return FALSE;
    }
  } else {
    error_log("missing my_cnf file");
    return FALSE;
  }

  $parsed_txt = "";

  $expl_ar = explode("\n", $raw_cnf_txt);

  foreach($expl_ar as $line) {
    if(strlen($line) > 10 && strpos($line, "!include ") !== FALSE &&
                             strpos($line, "!include ")  ==     0) {
      $count = 1;
      $file = trim(str_replace("!include ", " ", $line, $count));

      if($tmp_txt = file_get_contents($file)) {
        if($parsed_str_ar = parse_ini_string($tmp_txt, TRUE)) {
          $my_cnf_ar = array_merge_recursive($my_cnf_ar, $parsed_str_ar);
          continue;
        } else {
          error_log("failed to parse included file $file");
          return FALSE;
        }
      } else {
        error_log("failed to parse included file $file");
        return FALSE;
      }
    } else {
      // include anything else
      $parsed_txt .= $line . "\n";
    }
  }

  if($parsed_ar = parse_ini_string($parsed_txt, TRUE)) {
    $my_cnf_ar = array_merge_recursive($my_cnf_ar, $parsed_ar);
    return $my_cnf_ar;
  } else {
    error_log("failed parsing my_cnf ini string");
    return FALSE;
  }
}

function dp_get_app_token_from_url() {
  if(empty($_SERVER['PATH_INFO'])) {
    return false;
  }

  $token = trim($_SERVER['PATH_INFO'], "/");

  if(strlen($token) == DEVPANEL_TOKEN_LEN && preg_match('/^[A-Za-z0-9]+$/', $token)) {
    return $token;
  } else {
    return false;
  }
}

function dp_get_token_from_params() {
  if(!isset($_GET['token'])) {
    return false;
  }

  $token = $_GET['token'];

  if(strlen($token) == DEVPANEL_TOKEN_LEN && preg_match('/^[A-Za-z0-9]+$/', $token)) {
    return $token;
  } else {
    return false;
  }
}

function dp_start_app_session($vhost, $app, $token) {
  if(session_status() != PHP_SESSION_ACTIVE) {
    session_start();
  }

  session_cache_expire(120);
  session_cache_limiter("private");
  $_SESSION["app"]   = $app;
  $_SESSION["token"] = $token;

  session_write_close();
}

?>
