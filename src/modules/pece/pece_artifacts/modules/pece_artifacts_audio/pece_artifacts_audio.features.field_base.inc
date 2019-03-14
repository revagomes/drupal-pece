<?php

/**
 * @file
 * pece_artifacts_audio.features.field_base.inc
 */

/**
 * Implements hook_field_default_field_bases().
 */
function pece_artifacts_audio_field_default_field_bases() {
  $field_bases = array();

  // Exported field_base: 'field_pece_file__format'.
  $field_bases['field_pece_file__format'] = array(
    'active' => 1,
    'cardinality' => 1,
    'deleted' => 0,
    'entity_types' => array(),
    'field_name' => 'field_pece_file__format',
    'indexes' => array(
      'value' => array(
        0 => 'value',
      ),
    ),
    'locked' => 0,
    'module' => 'list',
    'settings' => array(
      'allowed_values' => array(
        'mp3' => 'mp3',
        'mp4' => 'mp4',
        'aac' => 'aac',
        'wav' => 'wav',
        'm4a' => 'm4a',
        'ogg' => 'ogg',
        'oga' => 'oga',
        'weba' => 'weba',
        'webm' => 'webm',
      ),
      'allowed_values_function' => '',
      'profile2_private' => FALSE,
    ),
    'translatable' => 0,
    'type' => 'list_text',
  );

  // Exported field_base: 'field_pece_media_audio'.
  $field_bases['field_pece_media_audio'] = array(
    'active' => 1,
    'cardinality' => 1,
    'deleted' => 0,
    'entity_types' => array(),
    'field_name' => 'field_pece_media_audio',
    'indexes' => array(
      'fid' => array(
        0 => 'fid',
      ),
    ),
    'locked' => 0,
    'module' => 'file',
    'settings' => array(
      'display_default' => 0,
      'display_field' => 0,
      'profile2_private' => FALSE,
      'uri_scheme' => 'private',
    ),
    'translatable' => 0,
    'type' => 'file',
  );

  return $field_bases;
}
