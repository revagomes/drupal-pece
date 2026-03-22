# OpenTofu Outputs for PECE Drupal Kubernetes Deployment
# Provides useful information about the deployed infrastructure

# ==============================================================================
# Deployment Information
# ==============================================================================

output "namespace" {
  description = "Kubernetes namespace where resources are deployed"
  value       = var.namespace
}

output "environment" {
  description = "Deployment environment (dev, staging, prod)"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

# ==============================================================================
# Service Names and Endpoints
# ==============================================================================

output "php_service_name" {
  description = "Name of the PHP-FPM service (for internal connections)"
  value       = local.php_service_name
}

output "nginx_service_name" {
  description = "Name of the Nginx service (for internal connections)"
  value       = local.nginx_service_name
}

output "mariadb_service_name" {
  description = "Name of the MariaDB service (for database connections)"
  value       = local.mariadb_service_name
}

output "database_host" {
  description = "Database connection host (service name in Kubernetes)"
  value       = var.db_host
}

output "database_port" {
  description = "Database connection port"
  value       = var.db_port
}

output "database_name" {
  description = "Database name"
  value       = var.db_name
  sensitive   = false
}

# ==============================================================================
# Ingress Information
# ==============================================================================

output "ingress_enabled" {
  description = "Whether Ingress resource is enabled"
  value       = var.ingress_enabled
}

output "ingress_url" {
  description = "Public URL for accessing the Drupal site via Ingress"
  value       = var.ingress_enabled ? (var.tls_enabled ? "https://${var.domain}" : "http://${var.domain}") : "Ingress disabled - use port-forward or LoadBalancer"
}

output "domain" {
  description = "Primary domain name for the application"
  value       = var.domain
}

output "tls_enabled" {
  description = "Whether TLS/SSL is enabled for Ingress"
  value       = var.tls_enabled
}

output "tls_secret_name" {
  description = "Name of the Kubernetes secret containing TLS certificate"
  value       = var.tls_enabled ? var.tls_secret_name : null
}

# ==============================================================================
# Container Images
# ==============================================================================

output "php_image" {
  description = "Full PHP-FPM container image name with tag"
  value       = local.php_image_full
}

output "nginx_image" {
  description = "Full Nginx container image name with tag"
  value       = local.nginx_image_full
}

output "mariadb_image" {
  description = "Full MariaDB container image name with tag"
  value       = local.mariadb_image_full
}

# ==============================================================================
# Scaling Configuration
# ==============================================================================

output "php_replicas" {
  description = "Number of PHP-FPM pod replicas"
  value       = var.php_replicas
}

output "nginx_replicas" {
  description = "Number of Nginx pod replicas"
  value       = var.nginx_replicas
}

output "php_autoscaling_enabled" {
  description = "Whether HorizontalPodAutoscaler is enabled for PHP-FPM"
  value       = var.php_autoscaling_enabled
}

output "php_autoscaling_range" {
  description = "PHP-FPM autoscaling replica range (min-max)"
  value       = var.php_autoscaling_enabled ? "${var.php_autoscaling_min_replicas}-${var.php_autoscaling_max_replicas}" : "autoscaling disabled"
}

# ==============================================================================
# Storage Information
# ==============================================================================

output "storage_class" {
  description = "Kubernetes storage class used for PersistentVolumes"
  value       = var.storage_class
}

output "drupal_files_storage_size" {
  description = "Storage size allocated for Drupal files"
  value       = var.drupal_files_storage_size
}

output "mariadb_storage_size" {
  description = "Storage size allocated for MariaDB data"
  value       = var.mariadb_storage_size
}

# ==============================================================================
# Optional Services
# ==============================================================================

output "redis_enabled" {
  description = "Whether Redis cache service is enabled"
  value       = var.redis_enabled
}

output "solr_enabled" {
  description = "Whether Solr search service is enabled"
  value       = var.solr_enabled
}

# ==============================================================================
# Module Outputs (from kubernetes module)
# ==============================================================================

output "kubernetes_module_outputs" {
  description = "Outputs from the Kubernetes infrastructure module"
  value       = module.kubernetes
  sensitive   = true
}

# ==============================================================================
# Connection Information
# ==============================================================================

output "connection_info" {
  description = "Quick reference for connecting to deployed services"
  value = {
    web_url          = var.ingress_enabled ? (var.tls_enabled ? "https://${var.domain}" : "http://${var.domain}") : "Use kubectl port-forward"
    admin_url        = var.ingress_enabled ? (var.tls_enabled ? "https://${var.domain}/user/login" : "http://${var.domain}/user/login") : "Use kubectl port-forward"
    namespace        = var.namespace
    php_service      = "${local.php_service_name}.${var.namespace}.svc.cluster.local:9000"
    nginx_service    = "${local.nginx_service_name}.${var.namespace}.svc.cluster.local:80"
    mariadb_service  = "${local.mariadb_service_name}.${var.namespace}.svc.cluster.local:3306"
  }
}

# ==============================================================================
# Kubectl Commands
# ==============================================================================

output "kubectl_commands" {
  description = "Useful kubectl commands for managing the deployment"
  value = {
    get_pods           = "kubectl get pods -n ${var.namespace}"
    get_services       = "kubectl get services -n ${var.namespace}"
    get_ingress        = "kubectl get ingress -n ${var.namespace}"
    get_pvc            = "kubectl get pvc -n ${var.namespace}"
    logs_php           = "kubectl logs -n ${var.namespace} -l app=php -f"
    logs_nginx         = "kubectl logs -n ${var.namespace} -l app=nginx -f"
    logs_mariadb       = "kubectl logs -n ${var.namespace} -l app=mariadb -f"
    exec_php           = "kubectl exec -it -n ${var.namespace} deployment/php -- bash"
    exec_drush         = "kubectl exec -it -n ${var.namespace} deployment/php -- drush status"
    port_forward_nginx = "kubectl port-forward -n ${var.namespace} service/${local.nginx_service_name} 8080:80"
  }
}

# ==============================================================================
# Deployment Summary
# ==============================================================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    project      = var.project_name
    environment  = var.environment
    namespace    = var.namespace
    url          = var.ingress_enabled ? (var.tls_enabled ? "https://${var.domain}" : "http://${var.domain}") : "Ingress disabled"
    php_replicas = var.php_autoscaling_enabled ? "${var.php_autoscaling_min_replicas}-${var.php_autoscaling_max_replicas} (autoscaled)" : var.php_replicas
    redis        = var.redis_enabled ? "enabled" : "disabled"
    solr         = var.solr_enabled ? "enabled" : "disabled"
    tls          = var.tls_enabled ? "enabled" : "disabled"
  }
}
