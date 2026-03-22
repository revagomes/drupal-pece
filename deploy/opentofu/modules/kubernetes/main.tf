# Kubernetes Module - Core Infrastructure Resources
# This module creates foundational K8s resources: namespace, configmap, secrets, and PVCs
# Workload resources (Deployments, StatefulSets, Services) are managed in the parent module

# ==============================================================================
# Namespace
# ==============================================================================

resource "kubernetes_namespace_v1" "pece" {
  metadata {
    name   = var.namespace
    labels = var.labels
    annotations = var.annotations
  }
}

# ==============================================================================
# ConfigMap - Non-sensitive Configuration
# ==============================================================================

resource "kubernetes_config_map_v1" "pece" {
  metadata {
    name      = "${var.project_name}-config"
    namespace = kubernetes_namespace_v1.pece.metadata[0].name
    labels    = var.labels
  }

  data = {
    # Database connection (non-sensitive)
    DB_HOST   = var.db_host
    DB_PORT   = tostring(var.db_port)
    DB_NAME   = var.db_name
    DB_USER   = var.db_user
    DB_DRIVER = "mysql"

    # Drupal configuration
    DRUPAL_ACCOUNT_USERNAME = var.drupal_admin_username
    DRUPAL_ACCOUNT_EMAIL    = var.drupal_admin_email
    SITE_LANGUAGE           = var.site_language

    # PHP-FPM configuration
    PHP_FPM_USER                 = "www-data"
    PHP_FPM_GROUP                = "www-data"
    PHP_MEMORY_LIMIT             = var.php_memory_limit
    PHP_MAX_EXECUTION_TIME       = "300"
    PHP_MAX_INPUT_TIME           = "300"
    PHP_POST_MAX_SIZE            = "100M"
    PHP_UPLOAD_MAX_FILESIZE      = "100M"

    # PHP OPcache configuration
    PHP_OPCACHE_ENABLE           = "1"
    PHP_OPCACHE_MEMORY           = "256"
    PHP_OPCACHE_MAX_FILES        = "20000"
    PHP_OPCACHE_VALIDATE_TIMESTAMPS = var.debug_mode ? "1" : "0"

    # Nginx configuration
    NGINX_BACKEND_HOST           = var.db_host == "mariadb" ? "php" : var.db_host
    NGINX_SERVER_ROOT            = "/var/www/html/web"
    NGINX_VHOST_PRESET           = "drupal10"
    NGINX_STATIC_OPEN_FILE_CACHE = var.debug_mode ? "off" : "on"
    NGINX_ERROR_LOG_LEVEL        = var.debug_mode ? "debug" : "warn"

    # Environment and feature flags
    ENVIRONMENT                  = var.environment
    DEBUG_MODE                   = var.debug_mode ? "true" : "false"

    # Drupal trusted host patterns (JSON encoded)
    DRUPAL_TRUSTED_HOST_PATTERNS = jsonencode(var.drupal_trusted_host_patterns)

    # Domain configuration
    DOMAIN = var.domain

    # Optional services flags
    REDIS_ENABLED = var.redis_enabled ? "true" : "false"
    SOLR_ENABLED  = var.solr_enabled ? "true" : "false"
  }
}

# ==============================================================================
# Secrets - Sensitive Configuration
# ==============================================================================

resource "kubernetes_secret_v1" "pece" {
  metadata {
    name      = "${var.project_name}-secrets"
    namespace = kubernetes_namespace_v1.pece.metadata[0].name
    labels    = var.labels
  }

  type = "Opaque"

  data = {
    # Database credentials (base64 encoded by Kubernetes provider)
    DB_PASSWORD      = var.db_password
    DB_ROOT_PASSWORD = var.db_root_password

    # Drupal admin credentials
    DRUPAL_ACCOUNT_PASSWORD = var.drupal_admin_password

    # Drupal hash salt (critical for security)
    DRUPAL_HASH_SALT = var.drupal_hash_salt
  }
}

# ==============================================================================
# Optional: Redis ConfigMap
# ==============================================================================

resource "kubernetes_config_map_v1" "redis" {
  count = var.redis_enabled ? 1 : 0

  metadata {
    name      = "${var.project_name}-redis-config"
    namespace = kubernetes_namespace_v1.pece.metadata[0].name
    labels    = merge(var.labels, { component = "redis" })
  }

  data = {
    REDIS_HOST = "redis"
    REDIS_PORT = "6379"
    REDIS_DB   = "0"
  }
}

# ==============================================================================
# Optional: Solr ConfigMap
# ==============================================================================

resource "kubernetes_config_map_v1" "solr" {
  count = var.solr_enabled ? 1 : 0

  metadata {
    name      = "${var.project_name}-solr-config"
    namespace = kubernetes_namespace_v1.pece.metadata[0].name
    labels    = merge(var.labels, { component = "solr" })
  }

  data = {
    SOLR_HOST       = "solr"
    SOLR_PORT       = "8983"
    SOLR_CORE       = var.project_name
    SOLR_CONFIG_SET = var.solr_config_set
  }
}

# ==============================================================================
# Persistent Volume Claims
# ==============================================================================

# PVC for Drupal files (sites/default/files, private files, etc.)
resource "kubernetes_persistent_volume_claim_v1" "drupal_files" {
  metadata {
    name      = "${var.project_name}-drupal-files"
    namespace = kubernetes_namespace_v1.pece.metadata[0].name
    labels    = merge(var.labels, { component = "drupal-storage" })
  }

  spec {
    access_modes = [var.drupal_files_access_mode]

    resources {
      requests = {
        storage = var.drupal_files_storage_size
      }
    }

    storage_class_name = var.storage_class
  }

  # Wait for namespace to be ready
  depends_on = [kubernetes_namespace_v1.pece]
}

# PVC for MariaDB data (database storage)
resource "kubernetes_persistent_volume_claim_v1" "mariadb_data" {
  metadata {
    name      = "${var.project_name}-mariadb-data"
    namespace = kubernetes_namespace_v1.pece.metadata[0].name
    labels    = merge(var.labels, { component = "mariadb-storage" })
  }

  spec {
    access_modes = ["ReadWriteOnce"]  # Database needs single-writer access

    resources {
      requests = {
        storage = var.mariadb_storage_size
      }
    }

    storage_class_name = var.storage_class
  }

  # Wait for namespace to be ready
  depends_on = [kubernetes_namespace_v1.pece]
}

# ==============================================================================
# Optional: Redis PVC for persistence
# ==============================================================================

resource "kubernetes_persistent_volume_claim_v1" "redis_data" {
  count = var.redis_enabled ? 1 : 0

  metadata {
    name      = "${var.project_name}-redis-data"
    namespace = kubernetes_namespace_v1.pece.metadata[0].name
    labels    = merge(var.labels, { component = "redis-storage" })
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "1Gi"  # Redis typically needs less storage
      }
    }

    storage_class_name = var.storage_class
  }

  depends_on = [kubernetes_namespace_v1.pece]
}

# ==============================================================================
# Optional: Solr PVC for index data
# ==============================================================================

resource "kubernetes_persistent_volume_claim_v1" "solr_data" {
  count = var.solr_enabled ? 1 : 0

  metadata {
    name      = "${var.project_name}-solr-data"
    namespace = kubernetes_namespace_v1.pece.metadata[0].name
    labels    = merge(var.labels, { component = "solr-storage" })
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "10Gi"  # Solr indexes can grow large
      }
    }

    storage_class_name = var.storage_class
  }

  depends_on = [kubernetes_namespace_v1.pece]
}

# ==============================================================================
# Network Policies (optional security layer)
# ==============================================================================

# Network policy to restrict database access to only PHP pods
resource "kubernetes_network_policy_v1" "mariadb_access" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "${var.project_name}-mariadb-policy"
    namespace = kubernetes_namespace_v1.pece.metadata[0].name
    labels    = var.labels
  }

  spec {
    pod_selector {
      match_labels = {
        app = "mariadb"
      }
    }

    policy_types = ["Ingress"]

    # Allow ingress only from PHP pods
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "php"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "3306"
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.pece]
}

# Network policy for Redis (if enabled)
resource "kubernetes_network_policy_v1" "redis_access" {
  count = var.redis_enabled && var.enable_network_policies ? 1 : 0

  metadata {
    name      = "${var.project_name}-redis-policy"
    namespace = kubernetes_namespace_v1.pece.metadata[0].name
    labels    = var.labels
  }

  spec {
    pod_selector {
      match_labels = {
        app = "redis"
      }
    }

    policy_types = ["Ingress"]

    # Allow ingress only from PHP pods
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "php"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "6379"
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.pece]
}

# Network policy for Solr (if enabled)
resource "kubernetes_network_policy_v1" "solr_access" {
  count = var.solr_enabled && var.enable_network_policies ? 1 : 0

  metadata {
    name      = "${var.project_name}-solr-policy"
    namespace = kubernetes_namespace_v1.pece.metadata[0].name
    labels    = var.labels
  }

  spec {
    pod_selector {
      match_labels = {
        app = "solr"
      }
    }

    policy_types = ["Ingress"]

    # Allow ingress from PHP pods and external (for admin UI)
    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "php"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "8983"
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.pece]
}
