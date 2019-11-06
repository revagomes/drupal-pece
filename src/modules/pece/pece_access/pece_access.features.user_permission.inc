<?php

/**
 * @file
 * pece_access.features.user_permission.inc
 */

/**
 * Implements hook_user_default_permissions().
 */
function pece_access_user_default_permissions() {
  $permissions = array();

  // Exported permission: 'edit page-pece_essay_items in page manager'.
  $permissions['edit page-pece_essay_items in page manager'] = array(
    'name' => 'edit page-pece_essay_items in page manager',
    'roles' => array(
      'administrator' => 'administrator',
    ),
    'module' => 'pmp',
  );

  return $permissions;
}
