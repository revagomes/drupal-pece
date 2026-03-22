# Kubernetes Module Outputs
# Exports resource names and metadata for use by parent module or other resources

# ==============================================================================
# Namespace Outputs
# ==============================================================================

output "namespace_name" {
  description = "Name of the created Kubernetes namespace"
  value       = kubernetes_namespace_v1.pece.metadata[0].name
}

output "namespace_id" {
  description = "ID of the created Kubernetes namespace"
  value       = kubernetes_namespace_v1.pece.metadata[0].uid
}

# ==============================================================================
# ConfigMap Outputs
# ==============================================================================

output "configmap_name" {
  description = "Name of the primary configuration ConfigMap"
  value       = kubernetes_config_map_v1.pece.metadata[0].name
}

output "configmap_namespace" {
  description = "Namespace of the configuration ConfigMap"
  value       = kubernetes_config_map_v1.pece.metadata[0].namespace
}

output "redis_configmap_name" {
  description = "Name of the Redis ConfigMap (null if Redis is disabled)"
  value       = var.redis_enabled ? kubernetes_config_map_v1.redis[0].metadata[0].name : null
}

output "solr_configmap_name" {
  description = "Name of the Solr ConfigMap (null if Solr is disabled)"
  value       = var.solr_enabled ? kubernetes_config_map_v1.solr[0].metadata[0].name : null
}

# ==============================================================================
# Secrets Outputs
# ==============================================================================

output "secrets_name" {
  description = "Name of the primary secrets resource"
  value       = kubernetes_secret_v1.pece.metadata[0].name
}

output "secrets_namespace" {
  description = "Namespace of the secrets resource"
  value       = kubernetes_secret_v1.pece.metadata[0].namespace
}

# ==============================================================================
# PersistentVolumeClaim Outputs
# ==============================================================================

output "drupal_files_pvc_name" {
  description = "Name of the Drupal files PersistentVolumeClaim"
  value       = kubernetes_persistent_volume_claim_v1.drupal_files.metadata[0].name
}

output "mariadb_data_pvc_name" {
  description = "Name of the MariaDB data PersistentVolumeClaim"
  value       = kubernetes_persistent_volume_claim_v1.mariadb_data.metadata[0].name
}

output "redis_data_pvc_name" {
  description = "Name of the Redis data PersistentVolumeClaim (null if Redis is disabled)"
  value       = var.redis_enabled ? kubernetes_persistent_volume_claim_v1.redis_data[0].metadata[0].name : null
}

output "solr_data_pvc_name" {
  description = "Name of the Solr data PersistentVolumeClaim (null if Solr is disabled)"
  value       = var.solr_enabled ? kubernetes_persistent_volume_claim_v1.solr_data[0].metadata[0].name : null
}

# ==============================================================================
# Storage Information
# ==============================================================================

output "drupal_files_storage_size" {
  description = "Storage size allocated for Drupal files"
  value       = var.drupal_files_storage_size
}

output "mariadb_storage_size" {
  description = "Storage size allocated for MariaDB data"
  value       = var.mariadb_storage_size
}

output "storage_class" {
  description = "Kubernetes storage class used for all PersistentVolumes"
  value       = var.storage_class
}

# ==============================================================================
# Network Policy Outputs
# ==============================================================================

output "mariadb_network_policy_name" {
  description = "Name of the MariaDB network policy (null if disabled)"
  value       = var.enable_network_policies ? kubernetes_network_policy_v1.mariadb_access[0].metadata[0].name : null
}

output "redis_network_policy_name" {
  description = "Name of the Redis network policy (null if Redis or network policies are disabled)"
  value       = var.redis_enabled && var.enable_network_policies ? kubernetes_network_policy_v1.redis_access[0].metadata[0].name : null
}

output "solr_network_policy_name" {
  description = "Name of the Solr network policy (null if Solr or network policies are disabled)"
  value       = var.solr_enabled && var.enable_network_policies ? kubernetes_network_policy_v1.solr_access[0].metadata[0].name : null
}

# ==============================================================================
# Resource Summary
# ==============================================================================

output "resource_summary" {
  description = "Summary of created Kubernetes resources"
  value = {
    namespace          = kubernetes_namespace_v1.pece.metadata[0].name
    configmaps_count   = 1 + (var.redis_enabled ? 1 : 0) + (var.solr_enabled ? 1 : 0)
    secrets_count      = 1
    pvcs_count         = 2 + (var.redis_enabled ? 1 : 0) + (var.solr_enabled ? 1 : 0)
    network_policies   = var.enable_network_policies ? (1 + (var.redis_enabled ? 1 : 0) + (var.solr_enabled ? 1 : 0)) : 0
    redis_enabled      = var.redis_enabled
    solr_enabled       = var.solr_enabled
    network_policies_enabled = var.enable_network_policies
  }
}

# ==============================================================================
# Database Connection Information
# ==============================================================================

output "database_connection" {
  description = "Database connection information (non-sensitive)"
  value = {
    host = var.db_host
    port = var.db_port
    name = var.db_name
    user = var.db_user
  }
}

# ==============================================================================
# Service Configuration
# ==============================================================================

output "service_flags" {
  description = "Enabled service flags"
  value = {
    redis               = var.redis_enabled
    solr                = var.solr_enabled
    init_container      = var.enable_init_container
    health_checks       = var.enable_health_checks
    network_policies    = var.enable_network_policies
    debug_mode          = var.debug_mode
  }
}
