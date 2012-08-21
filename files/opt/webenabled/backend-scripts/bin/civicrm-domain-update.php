#!/opt/webenabled/config/os/pathnames/bin/php -q
<?php
$f = STDIN;
$f = fgets($f);
$domain_config = unserialize($f);

$domain_config['configAndLogDir'] = '/home/clients/websites/'. $argv[1] .'/public_html/'. str_replace('w_' ,'', $argv[1]) .'/sites/default/files/civicrm/templates_c/en_US/ConfigAndLog/';
$domain_config['uploadDir'] = '/home/clients/websites/'. $argv[1] .'/public_html/'. str_replace('w_' ,'', $argv[1]) .'/sites/default/files/civicrm/upload/';
$domain_config['imageUploadDir'] = '/home/clients/websites/'. $argv[1] .'/public_html/'. str_replace('w_' ,'', $argv[1]) .'/sites/default/files/civicrm/persist/contribute/';
$domain_config['customFileUploadDir'] = '/home/clients/websites/'. $argv[1] .'/public_html/'. str_replace('w_' ,'', $argv[1]) .'/sites/default/files/civicrm/custom/';
$domain_config['imageUploadURL'] = 'http://'. $argv[2] .'/sites/default/files/civicrm/persist/contribute/';
$domain_config['userFrameworkResourceURL'] = 'http://'. $argv[2] .'/sites/all/modules/civicrm/';

echo(serialize($domain_config));
?>
