#!/usr/bin/env php
<?php
$f = STDIN;
$f = fgets($f);
$domain_config = unserialize($f);

$vhost_public_dir  = $argv[1];
$vhost_main_domain = $argv[2];
$ssl_enabled       = isset($argv[3]) ? strtolower($argv[3]) : "no";

$default_files_dir = "{$vhost_public_dir}/sites/default/files/civicrm";

$proto_prefix = ($ssl_enabled == "yes") ? "https" : "http";
$site_base_url = "{$proto_prefix}://{$vhost_main_domain}";

$domain_config['configAndLogDir']          = "{$default_files_dir}/templates_c/en_US/ConfigAndLog/";
$domain_config['uploadDir']                = "{$default_files_dir}/upload/";
$domain_config['imageUploadDir']           = "{$default_files_dir}/persist/contribute/";
$domain_config['customFileUploadDir']      = "{$default_files_dir}/custom/";
$domain_config['imageUploadURL']           = "{$site_base_url}/sites/default/files/civicrm/persist/contribute/";
$domain_config['userFrameworkResourceURL'] = "{$site_base_url}/sites/all/modules/civicrm/";

$serialized_str = serialize($domain_config);

$serialized_escape_quote = str_replace("'", "\\'", $serialized_str);

echo($serialized_escape_quote);
?>
