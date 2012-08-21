<?php
/* vim: set expandtab sw=4 ts=4 sts=4: */
/**
 * phpMyAdmin sample configuration, you can use it as base for
 * manual configuration. For easier setup you can use setup/
 *
 * All directives are explained in Documentation.html and on phpMyAdmin
 * wiki <http://wiki.phpmyadmin.net>.
 *
 * @version $Id: config.sample.inc.php 13111 2009-11-09 15:02:21Z lem9 $
 * @package phpMyAdmin
 */

/*
 * This is needed for cookie based authentication to encrypt password in
 * cookie
 */
$cfg['blowfish_secret'] = 'Oh, Lilian! Look what you have done...'; /* YOU MUST FILL IN THIS FOR COOKIE AUTH! */

$cfg['PmaNoRelation_DisableWarning'] = true;
$cfg['SuhosinDisableWarning'] = true;
$cfg['MysqlDisableWarning'] = true;

/*
 * Servers configuration
 */
$i = 0;
require_once('../config/asp.config.inc');  // Dynamic servers list
/*
 * End of servers configuration
 */

/*
 * Directories for saving/loading files from server
 */
$cfg['UploadDir'] = '';
$cfg['SaveDir'] = '';

?>
