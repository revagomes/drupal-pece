# OpenTofu Variables for PECE Drupal Kubernetes Deployment
# Based on patterns from .env.example

# ==============================================================================
# Project and Environment
# ==============================================================================

variable "namespace" {
  description = "Kubernetes namespace for PECE deployment"
  type        = string
  default     = "pece"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name used for resource labeling"
  type        = string
  default     = "pece"
}

# ==============================================================================
# Container Images
# ==============================================================================

variable "container_registry" {
  description = "Container registry URL (e.g., registry.example.com)"
  type        = string
  default     = ""
}

variable "php_image" {
  description = "PHP-FPM container image name"
  type        = string
  default     = "pece-php"
}

variable "php_image_tag" {
  description = "PHP-FPM container image tag"
  type        = string
  default     = "8.3"
}

variable "nginx_image" {
  description = "Nginx container image name"
  type        = string
  default     = "pece-nginx"
}

variable "nginx_image_tag" {
  description = "Nginx container image tag"
  type        = string
  default     = "1.25"
}

variable "mariadb_image" {
  description = "MariaDB container image"
  type        = string
  default     = "mariadb"
}

variable "mariadb_image_tag" {
  description = "MariaDB container image tag (from .env MARIADB_TAG)"
  type        = string
  default     = "10.9"
}

# ==============================================================================
# Replicas and Scaling
# ==============================================================================

variable "php_replicas" {
  description = "Number of PHP-FPM pod replicas"
  type        = number
  default     = 2
  validation {
    condition     = var.php_replicas >= 1 && var.php_replicas <= 20
    error_message = "PHP replicas must be between 1 and 20."
  }
}

variable "nginx_replicas" {
  description = "Number of Nginx pod replicas"
  type        = number
  default     = 2
  validation {
    condition     = var.nginx_replicas >= 1 && var.nginx_replicas <= 20
    error_message = "Nginx replicas must be between 1 and 20."
  }
}

variable "php_autoscaling_enabled" {
  description = "Enable HorizontalPodAutoscaler for PHP-FPM"
  type        = bool
  default     = true
}

variable "php_autoscaling_min_replicas" {
  description = "Minimum replicas for PHP-FPM autoscaling"
  type        = number
  default     = 2
}

variable "php_autoscaling_max_replicas" {
  description = "Maximum replicas for PHP-FPM autoscaling"
  type        = number
  default     = 10
}

variable "php_autoscaling_cpu_threshold" {
  description = "CPU utilization percentage to trigger autoscaling"
  type        = number
  default     = 70
}

# ==============================================================================
# Resource Limits - PHP-FPM
# ==============================================================================

variable "php_cpu_request" {
  description = "CPU request for PHP-FPM pods"
  type        = string
  default     = "500m"
}

variable "php_cpu_limit" {
  description = "CPU limit for PHP-FPM pods"
  type        = string
  default     = "2000m"
}

variable "php_memory_request" {
  description = "Memory request for PHP-FPM pods"
  type        = string
  default     = "512Mi"
}

variable "php_memory_limit" {
  description = "Memory limit for PHP-FPM pods"
  type        = string
  default     = "2Gi"
}

# ==============================================================================
# Resource Limits - Nginx
# ==============================================================================

variable "nginx_cpu_request" {
  description = "CPU request for Nginx pods"
  type        = string
  default     = "100m"
}

variable "nginx_cpu_limit" {
  description = "CPU limit for Nginx pods"
  type        = string
  default     = "500m"
}

variable "nginx_memory_request" {
  description = "Memory request for Nginx pods"
  type        = string
  default     = "128Mi"
}

variable "nginx_memory_limit" {
  description = "Memory limit for Nginx pods"
  type        = string
  default     = "512Mi"
}

# ==============================================================================
# Resource Limits - MariaDB
# ==============================================================================

variable "mariadb_cpu_request" {
  description = "CPU request for MariaDB pods"
  type        = string
  default     = "500m"
}

variable "mariadb_cpu_limit" {
  description = "CPU limit for MariaDB pods"
  type        = string
  default     = "2000m"
}

variable "mariadb_memory_request" {
  description = "Memory request for MariaDB pods"
  type        = string
  default     = "1Gi"
}

variable "mariadb_memory_limit" {
  description = "Memory limit for MariaDB pods"
  type        = string
  default     = "4Gi"
}

# ==============================================================================
# Database Configuration
# ==============================================================================

variable "db_name" {
  description = "Drupal database name (from .env DB_NAME)"
  type        = string
  default     = "drupal"
}

variable "db_user" {
  description = "Drupal database username (from .env DB_USER)"
  type        = string
  default     = "drupal"
}

variable "db_password" {
  description = "Drupal database password (from .env DB_PASSWORD) - SENSITIVE"
  type        = string
  sensitive   = true
}

variable "db_root_password" {
  description = "MariaDB root password (from .env DB_ROOT_PASSWORD) - SENSITIVE"
  type        = string
  sensitive   = true
}

variable "db_host" {
  description = "Database host (service name in Kubernetes)"
  type        = string
  default     = "mariadb"
}

variable "db_port" {
  description = "Database port (from .env DB_PORT)"
  type        = number
  default     = 3306
}

# ==============================================================================
# Storage Configuration
# ==============================================================================

variable "storage_class" {
  description = "Kubernetes storage class for PersistentVolumes"
  type        = string
  default     = "standard"
}

variable "drupal_files_storage_size" {
  description = "Storage size for Drupal files directory (sites/default/files)"
  type        = string
  default     = "10Gi"
}

variable "mariadb_storage_size" {
  description = "Storage size for MariaDB data directory"
  type        = string
  default     = "20Gi"
}

variable "drupal_files_access_mode" {
  description = "Access mode for Drupal files PVC (ReadWriteMany for shared across pods)"
  type        = string
  default     = "ReadWriteMany"
  validation {
    condition     = contains(["ReadWriteOnce", "ReadWriteMany", "ReadOnlyMany"], var.drupal_files_access_mode)
    error_message = "Access mode must be ReadWriteOnce, ReadWriteMany, or ReadOnlyMany."
  }
}

# ==============================================================================
# Drupal Configuration
# ==============================================================================

variable "drupal_admin_username" {
  description = "Drupal admin account username (from .env DRUPAL_ACCOUNT_USERNAME)"
  type        = string
  default     = "admin"
}

variable "drupal_admin_password" {
  description = "Drupal admin account password (from .env DRUPAL_ACCOUNT_PASSWORD) - SENSITIVE"
  type        = string
  sensitive   = true
}

variable "drupal_admin_email" {
  description = "Drupal admin account email (from .env DRUPAL_ACCOUNT_EMAIL)"
  type        = string
}

variable "drupal_hash_salt" {
  description = "Drupal hash salt for security - SENSITIVE (generate with: openssl rand -hex 32)"
  type        = string
  sensitive   = true
}

variable "drupal_trusted_host_patterns" {
  description = "Drupal trusted host patterns (regex list)"
  type        = list(string)
  default     = []
}

variable "site_language" {
  description = "Site language (from .env SITE_LANGUAGE)"
  type        = string
  default     = "English"
}

# ==============================================================================
# Networking Configuration
# ==============================================================================

variable "domain" {
  description = "Primary domain name for the application (from .env PROJECT_BASE_URL)"
  type        = string
}

variable "ingress_enabled" {
  description = "Enable Ingress resource creation"
  type        = bool
  default     = true
}

variable "ingress_class" {
  description = "Ingress class name (e.g., nginx, traefik)"
  type        = string
  default     = "nginx"
}

variable "ingress_annotations" {
  description = "Additional annotations for Ingress resource"
  type        = map(string)
  default     = {}
}

variable "tls_enabled" {
  description = "Enable TLS/SSL for Ingress"
  type        = bool
  default     = true
}

variable "tls_secret_name" {
  description = "Name of the Kubernetes secret containing TLS certificate"
  type        = string
  default     = "pece-tls"
}

# ==============================================================================
# Optional Services
# ==============================================================================

variable "redis_enabled" {
  description = "Enable Redis cache service"
  type        = bool
  default     = false
}

variable "redis_image_tag" {
  description = "Redis image tag (from .env REDIS_TAG)"
  type        = string
  default     = "7"
}

variable "solr_enabled" {
  description = "Enable Solr search service"
  type        = bool
  default     = false
}

variable "solr_image_tag" {
  description = "Solr image tag (from .env SOLR_TAG)"
  type        = string
  default     = "8"
}

variable "solr_config_set" {
  description = "Solr config set (from .env SOLR_CONFIG_SET)"
  type        = string
  default     = "search_api_solr_8.x-2.7"
}

# ==============================================================================
# Labels and Annotations
# ==============================================================================

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    app         = "pece"
    managed-by  = "opentofu"
  }
}

variable "common_annotations" {
  description = "Common annotations to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# Feature Flags
# ==============================================================================

variable "enable_init_container" {
  description = "Enable init container for database migration and setup"
  type        = bool
  default     = true
}

variable "enable_health_checks" {
  description = "Enable liveness and readiness probes"
  type        = bool
  default     = true
}

variable "enable_network_policies" {
  description = "Enable Kubernetes network policies for security"
  type        = bool
  default     = false
}

variable "debug_mode" {
  description = "Enable debug mode with verbose logging"
  type        = bool
  default     = false
}
