#!/usr/bin/env php
<?php
$f = STDIN;
$f = fgets($f);
$domain_config = unserialize($f);

$vhost_public_dir  = $argv[1];
$vhost_main_domain = $argv[2];
$ssl_enabled       = isset($argv[3]) ? strtolower($argv[3]) : "no";

$proto_prefix = ($ssl_enabled == "yes") ? "https" : "http";

$domain_config['configAndLogDir']          = "{$vhost_public_dir}/sites/default/files/civicrm/templates_c/en_US/ConfigAndLog/";
$domain_config['uploadDir']                = "{$vhost_public_dir}/sites/default/files/civicrm/upload/";
$domain_config['imageUploadDir']           = "{$vhost_public_dir}/sites/default/files/civicrm/persist/contribute/";
$domain_config['customFileUploadDir']      = "{$vhost_public_dir}/sites/default/files/civicrm/custom/";
$domain_config['imageUploadURL']           = "$proto_prefix://{$vhost_main_domain}/sites/default/files/civicrm/persist/contribute/";
$domain_config['userFrameworkResourceURL'] = "$proto_prefix://{$vhost_main_domain}/sites/all/modules/civicrm/";

$serialized_str = serialize($domain_config);

$serialized_escape_quote = str_replace("'", "\\'", $serialized_str);

echo($serialized_escape_quote);
?>
