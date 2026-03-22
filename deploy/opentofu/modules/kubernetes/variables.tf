# Kubernetes Module Variables
# All variables required by the kubernetes module for creating core infrastructure resources

# ==============================================================================
# Project and Environment
# ==============================================================================

variable "namespace" {
  description = "Kubernetes namespace for PECE deployment"
  type        = string
}

variable "project_name" {
  description = "Project name used for resource naming and labeling"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Common annotations to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# Container Images
# ==============================================================================

variable "php_image" {
  description = "Full PHP-FPM container image name with tag (including registry)"
  type        = string
}

variable "nginx_image" {
  description = "Full Nginx container image name with tag (including registry)"
  type        = string
}

variable "mariadb_image" {
  description = "Full MariaDB container image name with tag"
  type        = string
}

# ==============================================================================
# Replicas
# ==============================================================================

variable "php_replicas" {
  description = "Number of PHP-FPM pod replicas"
  type        = number
}

variable "nginx_replicas" {
  description = "Number of Nginx pod replicas"
  type        = number
}

# ==============================================================================
# Resource Limits - PHP-FPM
# ==============================================================================

variable "php_cpu_request" {
  description = "CPU request for PHP-FPM pods"
  type        = string
}

variable "php_cpu_limit" {
  description = "CPU limit for PHP-FPM pods"
  type        = string
}

variable "php_memory_request" {
  description = "Memory request for PHP-FPM pods"
  type        = string
}

variable "php_memory_limit" {
  description = "Memory limit for PHP-FPM pods (also used as PHP_MEMORY_LIMIT env var)"
  type        = string
}

# ==============================================================================
# Resource Limits - Nginx
# ==============================================================================

variable "nginx_cpu_request" {
  description = "CPU request for Nginx pods"
  type        = string
}

variable "nginx_cpu_limit" {
  description = "CPU limit for Nginx pods"
  type        = string
}

variable "nginx_memory_request" {
  description = "Memory request for Nginx pods"
  type        = string
}

variable "nginx_memory_limit" {
  description = "Memory limit for Nginx pods"
  type        = string
}

# ==============================================================================
# Resource Limits - MariaDB
# ==============================================================================

variable "mariadb_cpu_request" {
  description = "CPU request for MariaDB pods"
  type        = string
}

variable "mariadb_cpu_limit" {
  description = "CPU limit for MariaDB pods"
  type        = string
}

variable "mariadb_memory_request" {
  description = "Memory request for MariaDB pods"
  type        = string
}

variable "mariadb_memory_limit" {
  description = "Memory limit for MariaDB pods"
  type        = string
}

# ==============================================================================
# Database Configuration
# ==============================================================================

variable "db_name" {
  description = "Drupal database name"
  type        = string
}

variable "db_user" {
  description = "Drupal database username"
  type        = string
}

variable "db_password" {
  description = "Drupal database password - SENSITIVE"
  type        = string
  sensitive   = true
}

variable "db_root_password" {
  description = "MariaDB root password - SENSITIVE"
  type        = string
  sensitive   = true
}

variable "db_host" {
  description = "Database host (service name in Kubernetes)"
  type        = string
}

variable "db_port" {
  description = "Database port"
  type        = number
}

# ==============================================================================
# Storage Configuration
# ==============================================================================

variable "storage_class" {
  description = "Kubernetes storage class for PersistentVolumes"
  type        = string
}

variable "drupal_files_storage_size" {
  description = "Storage size for Drupal files directory (sites/default/files)"
  type        = string
}

variable "mariadb_storage_size" {
  description = "Storage size for MariaDB data directory"
  type        = string
}

variable "drupal_files_access_mode" {
  description = "Access mode for Drupal files PVC (ReadWriteMany for shared across pods)"
  type        = string
}

# ==============================================================================
# Drupal Configuration
# ==============================================================================

variable "drupal_admin_username" {
  description = "Drupal admin account username"
  type        = string
}

variable "drupal_admin_password" {
  description = "Drupal admin account password - SENSITIVE"
  type        = string
  sensitive   = true
}

variable "drupal_admin_email" {
  description = "Drupal admin account email"
  type        = string
}

variable "drupal_hash_salt" {
  description = "Drupal hash salt for security - SENSITIVE"
  type        = string
  sensitive   = true
}

variable "drupal_trusted_host_patterns" {
  description = "Drupal trusted host patterns (regex list)"
  type        = list(string)
}

variable "site_language" {
  description = "Site language"
  type        = string
}

# ==============================================================================
# Networking Configuration
# ==============================================================================

variable "domain" {
  description = "Primary domain name for the application"
  type        = string
}

# ==============================================================================
# Optional Services
# ==============================================================================

variable "redis_enabled" {
  description = "Enable Redis cache service"
  type        = bool
}

variable "redis_image_tag" {
  description = "Redis image tag"
  type        = string
}

variable "solr_enabled" {
  description = "Enable Solr search service"
  type        = bool
}

variable "solr_image_tag" {
  description = "Solr image tag"
  type        = string
}

variable "solr_config_set" {
  description = "Solr config set name"
  type        = string
}

# ==============================================================================
# Feature Flags
# ==============================================================================

variable "enable_init_container" {
  description = "Enable init container for database migration and setup"
  type        = bool
}

variable "enable_health_checks" {
  description = "Enable liveness and readiness probes"
  type        = bool
}

variable "enable_network_policies" {
  description = "Enable Kubernetes network policies for security"
  type        = bool
}

variable "debug_mode" {
  description = "Enable debug mode with verbose logging"
  type        = bool
}
