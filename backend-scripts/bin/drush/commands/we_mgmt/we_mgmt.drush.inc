<?php
/**
 * Drush commands
 *
 *
 * This module mgmtides a framework for a Drupal site to manage and install new Drupal sites via WebEnabled.
 *
 * Each site has the following commands that can be run on it.
 *
 * Implemented : 
 *   reset - Reset and install a new Drupal site.
 */

// Do not allow the program to be run as the root user. ever
$name = posix_getpwuid(posix_geteuid());
if ($name['name'] == 'root') {
  return drush_set_error('PROVISION_IS_ROOT', dt('You are running the mgmtision script as the root user. Exiting'));
}

/**
 * Implementation of hook_drush_command().
 */
function we_mgmt_drush_command() {

  $items['we-mgmt-reset'] = array(
    'description' => dt('This will reset your Drupal install. Consider yourself warned.'),
    'bootstrap' => DRUSH_BOOTSTRAP_DRUPAL_ROOT
  );
  $items['we-mgmt-daemon'] = array(
    'description' => dt('Daemon helper. For WebEnabled controller only.'),
    'bootstrap' => DRUSH_BOOTSTRAP_DRUPAL_FULL
  );
  $items['we-mgmt-localize'] = array(
    'description' => dt('This will localize your Drupal.'),
    'bootstrap' => DRUSH_BOOTSTRAP_DRUPAL_FULL
  );

  return $items;
}

function drush_we_mgmt_reset() {
  $f = STDIN;
  $options = fgets($f);

  list($language, $email, $profile, $site_url) = explode(':', $options);

  drush_set_option('site_url', $site_url);
  drush_set_option('profile', $profile);
  drush_set_option('language', $language);
  drush_set_option('client_email', $email);

  exec('mysql -e '. escapeshellarg('drop database drupal; create database drupal;'), $output, $return);
  if ($return) {
    return drush_set_error('WE_MGMT_DB_RESET', dt('Unable to drop and create Drupal database.'));
  }

  require_once('install/install_6.inc');
  exec('mysql drupal -e '. escapeshellarg('update users set name = \'admin\', status = 1 where uid = 1;'), $output, $return);
}

function drush_we_mgmt_daemon() {
  _we_base_daemon();
}

function drush_we_mgmt_localize() {
  $f = STDIN;
  $options = fgets($f);
  $param = explode(':', $options);

  $dest = sprintf("/home/clients/websites/w_%s/public_html/%s/drupal-6.17.%s.po", $param[1], $param[1], $param[0]);
  $r = drush_shell_exec("wget -q --timeout=30 -O $dest http://ftp.drupal.org/files/translations/6.x/drupal/drupal-6.17.$param[0].po");
  $file->filepath = $dest;
  drush_set_option('language', $param[0]);

  #drush_bootstrap(DRUSH_BOOTSTRAP_DRUPAL_FULL);
  #module_list(TRUE, FALSE, FALSE, $module_list);
  drupal_load('module', 'system');
  drupal_load('module', 'locale');
  locale_inc_callback("locale_add_language", $param[0], NULL, NULL, 0, '', '', TRUE, TRUE);
  locale_inc_callback("_locale_import_po", $file, $param[0], 1, "default");

}
