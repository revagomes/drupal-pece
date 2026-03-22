# OpenTofu Main Configuration for PECE Drupal Kubernetes Deployment
# This file orchestrates the deployment by calling modules and configuring providers

# ==============================================================================
# Provider Configuration
# ==============================================================================

provider "kubernetes" {
  # Provider will use the default kubeconfig file (~/.kube/config)
  # or can be configured with explicit connection details:
  # config_path    = var.kubeconfig_path
  # config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    # Helm provider inherits Kubernetes configuration
    # config_path    = var.kubeconfig_path
    # config_context = var.kubeconfig_context
  }
}

# ==============================================================================
# Local Variables
# ==============================================================================

locals {
  # Merge common labels with environment-specific labels
  labels = merge(
    var.common_labels,
    {
      environment = var.environment
      project     = var.project_name
    }
  )

  # Construct full image names with registry prefix
  php_image_full = var.container_registry != "" ? "${var.container_registry}/${var.php_image}:${var.php_image_tag}" : "${var.php_image}:${var.php_image_tag}"
  nginx_image_full = var.container_registry != "" ? "${var.container_registry}/${var.nginx_image}:${var.nginx_image_tag}" : "${var.nginx_image}:${var.nginx_image_tag}"
  mariadb_image_full = "${var.mariadb_image}:${var.mariadb_image_tag}"

  # Service names
  php_service_name = "php"
  nginx_service_name = "nginx"
  mariadb_service_name = var.db_host
}

# ==============================================================================
# Kubernetes Infrastructure Module
# ==============================================================================

module "kubernetes" {
  source = "./modules/kubernetes"

  # Project configuration
  namespace    = var.namespace
  project_name = var.project_name
  environment  = var.environment
  labels       = local.labels
  annotations  = var.common_annotations

  # Container images
  php_image     = local.php_image_full
  nginx_image   = local.nginx_image_full
  mariadb_image = local.mariadb_image_full

  # Replicas and scaling
  php_replicas   = var.php_replicas
  nginx_replicas = var.nginx_replicas

  # Resource limits - PHP
  php_cpu_request    = var.php_cpu_request
  php_cpu_limit      = var.php_cpu_limit
  php_memory_request = var.php_memory_request
  php_memory_limit   = var.php_memory_limit

  # Resource limits - Nginx
  nginx_cpu_request    = var.nginx_cpu_request
  nginx_cpu_limit      = var.nginx_cpu_limit
  nginx_memory_request = var.nginx_memory_request
  nginx_memory_limit   = var.nginx_memory_limit

  # Resource limits - MariaDB
  mariadb_cpu_request    = var.mariadb_cpu_request
  mariadb_cpu_limit      = var.mariadb_cpu_limit
  mariadb_memory_request = var.mariadb_memory_request
  mariadb_memory_limit   = var.mariadb_memory_limit

  # Database configuration
  db_name          = var.db_name
  db_user          = var.db_user
  db_password      = var.db_password
  db_root_password = var.db_root_password
  db_host          = var.db_host
  db_port          = var.db_port

  # Storage configuration
  storage_class              = var.storage_class
  drupal_files_storage_size  = var.drupal_files_storage_size
  mariadb_storage_size       = var.mariadb_storage_size
  drupal_files_access_mode   = var.drupal_files_access_mode

  # Drupal configuration
  drupal_admin_username       = var.drupal_admin_username
  drupal_admin_password       = var.drupal_admin_password
  drupal_admin_email          = var.drupal_admin_email
  drupal_hash_salt            = var.drupal_hash_salt
  drupal_trusted_host_patterns = var.drupal_trusted_host_patterns
  site_language               = var.site_language

  # Networking
  domain = var.domain

  # Feature flags
  enable_init_container   = var.enable_init_container
  enable_health_checks    = var.enable_health_checks
  enable_network_policies = var.enable_network_policies
  debug_mode              = var.debug_mode

  # Optional services
  redis_enabled   = var.redis_enabled
  redis_image_tag = var.redis_image_tag
  solr_enabled    = var.solr_enabled
  solr_image_tag  = var.solr_image_tag
  solr_config_set = var.solr_config_set
}

# ==============================================================================
# HorizontalPodAutoscaler for PHP-FPM
# ==============================================================================

resource "kubernetes_horizontal_pod_autoscaler_v2" "php" {
  count = var.php_autoscaling_enabled ? 1 : 0

  metadata {
    name      = "php-hpa"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    min_replicas = var.php_autoscaling_min_replicas
    max_replicas = var.php_autoscaling_max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "php"
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.php_autoscaling_cpu_threshold
        }
      }
    }

    behavior {
      scale_down {
        stabilization_window_seconds = 300
        policy {
          type          = "Percent"
          value         = 50
          period_seconds = 60
        }
      }
      scale_up {
        stabilization_window_seconds = 0
        policy {
          type          = "Percent"
          value         = 100
          period_seconds = 30
        }
      }
    }
  }

  depends_on = [module.kubernetes]
}

# ==============================================================================
# Ingress Resource
# ==============================================================================

resource "kubernetes_ingress_v1" "pece" {
  count = var.ingress_enabled ? 1 : 0

  metadata {
    name      = "${var.project_name}-ingress"
    namespace = var.namespace
    labels    = local.labels
    annotations = merge(
      {
        "kubernetes.io/ingress.class"                = var.ingress_class
        "nginx.ingress.kubernetes.io/ssl-redirect"   = var.tls_enabled ? "true" : "false"
        "nginx.ingress.kubernetes.io/proxy-body-size" = "100m"
      },
      var.ingress_annotations
    )
  }

  spec {
    dynamic "tls" {
      for_each = var.tls_enabled ? [1] : []
      content {
        hosts       = [var.domain]
        secret_name = var.tls_secret_name
      }
    }

    rule {
      host = var.domain

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = local.nginx_service_name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [module.kubernetes]
}
