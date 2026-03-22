# PECE Kubernetes Deployment Guide

This directory contains production-grade deployment infrastructure for PECE using OpenTofu, Kubernetes, and Podman.

## Overview

This deployment setup provides:

- **Container Images**: Production-optimized PHP-FPM and Nginx containers built with Podman
- **Infrastructure as Code**: OpenTofu modules for Kubernetes cluster provisioning
- **Kubernetes Manifests**: Complete K8s resource definitions (Deployments, Services, StatefulSets, Ingress, etc.)
- **Automation Scripts**: Build, deploy, and rollback automation
- **Configuration Management**: Environment-based configuration with ConfigMaps and Secrets

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Ingress (HTTPS)                      │
│                   pece.example.com                       │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────▼───────────┐
         │   Nginx Service       │
         │   (LoadBalancer)      │
         └───────────┬───────────┘
                     │
    ┌────────────────┼────────────────┐
    │                │                │
┌───▼───┐        ┌───▼───┐       ┌───▼───┐
│ Nginx │        │ Nginx │       │ Nginx │
│  Pod  │        │  Pod  │       │  Pod  │
└───┬───┘        └───┬───┘       └───┬───┘
    │                │                │
    └────────────────┼────────────────┘
                     │
         ┌───────────▼───────────┐
         │   PHP-FPM Service     │
         │   (ClusterIP)         │
         └───────────┬───────────┘
                     │
    ┌────────────────┼────────────────┐
    │                │                │
┌───▼───┐        ┌───▼───┐       ┌───▼───┐
│  PHP  │        │  PHP  │       │  PHP  │
│  Pod  │        │  Pod  │       │  Pod  │
└───┬───┘        └───┬───┘       └───┬───┘
    │                │                │
    └────────────────┼────────────────┘
                     │
         ┌───────────▼───────────┐
         │  MariaDB Service      │
         │   (ClusterIP)         │
         └───────────┬───────────┘
                     │
                ┌────▼────┐
                │ MariaDB │
                │StatefulSet│
                └─────────┘
```

## Directory Structure

```
deploy/
├── README.md                      # This file
├── Makefile                       # Main build and deployment automation
├── containerfiles/                # Container image definitions
│   ├── Containerfile.php         # PHP-FPM production image
│   └── Containerfile.nginx       # Nginx production image
├── opentofu/                      # Infrastructure as Code
│   ├── main.tf                   # Main OpenTofu configuration
│   ├── variables.tf              # Input variables
│   ├── outputs.tf                # Output values
│   ├── versions.tf               # Provider version constraints
│   └── modules/                  # Reusable modules
│       └── kubernetes/           # Kubernetes cluster module
│           └── main.tf
├── kubernetes/                    # Kubernetes manifests
│   ├── namespace.yaml            # Namespace definition
│   ├── configmap.yaml            # Drupal configuration
│   ├── secrets.yaml              # Database credentials (template)
│   ├── pvc.yaml                  # Persistent volume claims
│   ├── deployment-php.yaml       # PHP-FPM deployment
│   ├── deployment-nginx.yaml     # Nginx deployment
│   ├── statefulset-mariadb.yaml  # MariaDB StatefulSet
│   ├── service-php.yaml          # PHP-FPM service
│   ├── service-nginx.yaml        # Nginx service
│   ├── service-mariadb.yaml      # MariaDB service
│   ├── ingress.yaml              # Ingress resource
│   └── hpa.yaml                  # Horizontal Pod Autoscaler
└── scripts/                       # Automation scripts
    ├── build.sh                  # Container image build script
    ├── deploy.sh                 # Kubernetes deployment script
    └── rollback.sh               # Rollback script
```

## Prerequisites

### Required Tools

You must have the following tools installed:

```bash
# Container engine
podman --version     # >= 4.0 (or docker >= 24.0)

# Infrastructure provisioning
tofu --version       # >= 1.6 (OpenTofu)

# Kubernetes CLI
kubectl version      # >= 1.28

# Optional but recommended
helm version         # >= 3.0
```

### Installation

**macOS (Homebrew):**
```bash
brew install podman opentofu kubectl helm
```

**Linux (Debian/Ubuntu):**
```bash
# Podman
sudo apt-get update
sudo apt-get install -y podman

# OpenTofu
curl -Lo /tmp/opentofu.deb https://get.opentofu.org/opentofu/1.6.0/deb/opentofu_1.6.0_amd64.deb
sudo dpkg -i /tmp/opentofu.deb

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Kubernetes Cluster

You need access to a Kubernetes cluster. Options include:

- **Local Development**: [Minikube](https://minikube.sigs.k8s.io/), [Kind](https://kind.sigs.k8s.io/), [k3s](https://k3s.io/)
- **Cloud Providers**: GKE, EKS, AKS, DigitalOcean Kubernetes
- **Self-Hosted**: Kubeadm, Rancher, OpenShift

Ensure your `kubectl` is configured to access the cluster:

```bash
kubectl cluster-info
kubectl get nodes
```

## Quick Start

### 1. Set Environment Variables

Create a `.env` file or export variables:

```bash
export CONTAINER_REGISTRY=registry.example.com
export REGISTRY_USERNAME=your-username
export REGISTRY_PASSWORD=your-password
export IMAGE_TAG=v1.0.0
export DB_ROOT_PASSWORD=$(openssl rand -base64 32)
export DB_PASSWORD=$(openssl rand -base64 32)
export DRUPAL_HASH_SALT=$(openssl rand -base64 48)
```

### 2. Build Container Images

```bash
cd deploy
make build IMAGE_TAG=v1.0.0
```

This builds:
- `pece-php:v1.0.0` - PHP-FPM with Drupal dependencies
- `pece-nginx:v1.0.0` - Nginx with Drupal-optimized configuration

### 3. Push Images to Registry

```bash
make push CONTAINER_REGISTRY=registry.example.com IMAGE_TAG=v1.0.0
```

### 4. Provision Infrastructure with OpenTofu

```bash
cd opentofu

# Initialize OpenTofu
tofu init

# Review planned changes
tofu plan -var-file=production.tfvars

# Apply infrastructure
tofu apply -var-file=production.tfvars
```

### 5. Deploy to Kubernetes

```bash
cd deploy

# Deploy all resources
make deploy ENV=production IMAGE_TAG=v1.0.0

# Check deployment status
make status
```

### 6. Access the Site

```bash
# Get the ingress URL
kubectl get ingress -n pece

# Or port-forward for testing
kubectl port-forward -n pece svc/nginx 8080:80
# Visit http://localhost:8080
```

## Building Container Images

### Build All Images

```bash
make build
```

### Build Specific Images

```bash
# PHP-FPM only
make build-php IMAGE_TAG=v1.0.1

# Nginx only
make build-nginx IMAGE_TAG=v1.0.1
```

### Build with Custom Registry

```bash
make build CONTAINER_REGISTRY=registry.example.com IMAGE_TAG=v1.0.2
```

### Image Details

**PHP-FPM Image (`pece-php`)**
- Base: `php:8.3-fpm-alpine`
- Includes: Composer dependencies, Drupal core, PECE profile
- Non-root user: `www-data` (UID 82)
- Health check: `/health` endpoint via `drush status`

**Nginx Image (`pece-nginx`)**
- Base: `nginx:1.25-alpine`
- Configuration: Drupal-optimized with FastCGI caching
- Non-root user: `nginx` (UID 101)
- Health check: HTTP 200 on `/nginx-health`

## Infrastructure Provisioning with OpenTofu

### Initialize OpenTofu

```bash
cd opentofu
tofu init
```

### Create Variable File

Create `opentofu/production.tfvars`:

```hcl
# Cluster configuration
cluster_name = "pece-prod"
cluster_region = "us-east-1"
kubernetes_version = "1.28"

# Node pools
node_pools = {
  default = {
    size = "s-2vcpu-4gb"
    min_nodes = 2
    max_nodes = 5
  }
}

# Networking
vpc_cidr = "10.0.0.0/16"
enable_private_cluster = true

# Storage
storage_class = "do-block-storage"
```

### Plan and Apply

```bash
# Preview changes
tofu plan -var-file=production.tfvars -out=plan.out

# Apply changes
tofu apply plan.out
```

### Verify Infrastructure

```bash
# Get kubeconfig
tofu output -raw kubeconfig > ~/.kube/pece-prod-config
export KUBECONFIG=~/.kube/pece-prod-config

# Verify cluster access
kubectl get nodes
```

## Kubernetes Deployment

### Configure Secrets

**IMPORTANT**: Never commit real secrets to version control.

Create secrets file from template:

```bash
cd deploy/kubernetes

# Copy template
cp secrets.yaml secrets.local.yaml

# Edit with real credentials
# DO NOT commit secrets.local.yaml
```

Edit `secrets.local.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pece-secrets
  namespace: pece
type: Opaque
stringData:
  DB_ROOT_PASSWORD: "YOUR_GENERATED_PASSWORD"
  DB_PASSWORD: "YOUR_GENERATED_PASSWORD"
  DRUPAL_HASH_SALT: "YOUR_GENERATED_SALT"
```

Apply secrets:

```bash
kubectl apply -f secrets.local.yaml
```

### Deploy Application

Using Makefile (recommended):

```bash
make deploy ENV=production IMAGE_TAG=v1.0.0
```

Or manually:

```bash
cd deploy/kubernetes

# Apply in order
kubectl apply -f namespace.yaml
kubectl apply -f secrets.yaml
kubectl apply -f configmap.yaml
kubectl apply -f pvc.yaml
kubectl apply -f statefulset-mariadb.yaml
kubectl apply -f service-mariadb.yaml
kubectl apply -f deployment-php.yaml
kubectl apply -f service-php.yaml
kubectl apply -f deployment-nginx.yaml
kubectl apply -f service-nginx.yaml
kubectl apply -f ingress.yaml
kubectl apply -f hpa.yaml
```

### Verify Deployment

```bash
# Check pod status
kubectl get pods -n pece

# Check services
kubectl get svc -n pece

# Check ingress
kubectl get ingress -n pece

# View logs
kubectl logs -n pece -l app=pece-php --tail=50
kubectl logs -n pece -l app=pece-nginx --tail=50

# Check Drupal status
kubectl exec -n pece -it deployment/pece-php -- drush status
```

### Initialize Drupal

For a fresh deployment, initialize the Drupal site:

```bash
# Get a shell in the PHP pod
kubectl exec -n pece -it deployment/pece-php -- bash

# Inside the pod
cd /var/www/html
composer install --no-dev
drush -y si pece --existing-config \
  --account-name=admin \
  --account-pass=YOUR_ADMIN_PASSWORD

# Import essential content
drush content:import ../content/essential/

# Exit the pod
exit
```

## Configuration Management

### ConfigMaps

Drupal configuration is managed via `kubernetes/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: pece-config
  namespace: pece
data:
  NGINX_BACKEND_HOST: "pece-php"
  NGINX_SERVER_ROOT: "/var/www/html/web"
  NGINX_VHOST_PRESET: "drupal10"
  DB_HOST: "pece-mariadb"
  DB_NAME: "drupal"
  DB_USER: "drupal"
  DB_DRIVER: "mysql"
  DB_PORT: "3306"
```

Update configuration:

```bash
# Edit configmap.yaml
kubectl apply -f kubernetes/configmap.yaml

# Restart pods to pick up changes
kubectl rollout restart deployment/pece-php -n pece
kubectl rollout restart deployment/pece-nginx -n pece
```

### Secrets

Manage sensitive data with Kubernetes Secrets:

```bash
# Create or update secret
kubectl create secret generic pece-secrets \
  --from-literal=DB_PASSWORD=$(openssl rand -base64 32) \
  --from-literal=DRUPAL_HASH_SALT=$(openssl rand -base64 48) \
  --dry-run=client -o yaml | kubectl apply -f -

# View secret keys (not values)
kubectl get secret pece-secrets -n pece -o jsonpath='{.data}'

# Decode a secret value (for debugging)
kubectl get secret pece-secrets -n pece -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
```

## Rollback Procedures

### Automated Rollback

```bash
# Rollback to previous deployment
make rollback

# Or manually
./scripts/rollback.sh
```

### Manual Rollback

```bash
# View rollout history
kubectl rollout history deployment/pece-php -n pece
kubectl rollout history deployment/pece-nginx -n pece

# Rollback to previous revision
kubectl rollout undo deployment/pece-php -n pece
kubectl rollout undo deployment/pece-nginx -n pece

# Rollback to specific revision
kubectl rollout undo deployment/pece-php -n pece --to-revision=3
```

### Database Rollback

**CRITICAL**: Always backup the database before deployments.

```bash
# Backup before deployment
kubectl exec -n pece -it statefulset/pece-mariadb -- \
  mysqldump -u root -p$DB_ROOT_PASSWORD drupal > backup-$(date +%Y%m%d-%H%M%S).sql

# Restore from backup
kubectl exec -n pece -i statefulset/pece-mariadb -- \
  mysql -u root -p$DB_ROOT_PASSWORD drupal < backup-20240213-120000.sql
```

## Scaling

### Manual Scaling

```bash
# Scale PHP-FPM pods
kubectl scale deployment/pece-php -n pece --replicas=5

# Scale Nginx pods
kubectl scale deployment/pece-nginx -n pece --replicas=3
```

### Horizontal Pod Autoscaler (HPA)

HPA is configured in `kubernetes/hpa.yaml`:

```bash
# View HPA status
kubectl get hpa -n pece

# Update HPA configuration
kubectl apply -f kubernetes/hpa.yaml
```

The HPA automatically scales based on:
- CPU utilization (target: 70%)
- Memory utilization (target: 80%)
- Min replicas: 2
- Max replicas: 10

## Monitoring and Logs

### View Logs

```bash
# PHP-FPM logs
kubectl logs -n pece -l app=pece-php --tail=100 -f

# Nginx logs
kubectl logs -n pece -l app=pece-nginx --tail=100 -f

# MariaDB logs
kubectl logs -n pece statefulset/pece-mariadb --tail=100 -f

# All pods
kubectl logs -n pece --all-containers=true --tail=100 -f
```

### Shell Access

```bash
# PHP-FPM pod
make shell-php
# Or manually:
kubectl exec -n pece -it deployment/pece-php -- bash

# Nginx pod
make shell-nginx
# Or manually:
kubectl exec -n pece -it deployment/pece-nginx -- sh

# MariaDB pod
make shell-mariadb
# Or manually:
kubectl exec -n pece -it statefulset/pece-mariadb -- bash
```

### Health Checks

```bash
# Check pod health
kubectl get pods -n pece

# Describe pod for detailed events
kubectl describe pod -n pece <pod-name>

# Check readiness/liveness probes
kubectl get events -n pece --field-selector involvedObject.kind=Pod
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status and events
kubectl get pods -n pece
kubectl describe pod -n pece <pod-name>

# Common issues:
# 1. Image pull errors - verify CONTAINER_REGISTRY and credentials
# 2. Resource limits - check node capacity
# 3. PVC binding - verify storage class exists
```

### Database Connection Failures

```bash
# Verify MariaDB is running
kubectl get pods -n pece -l app=pece-mariadb

# Check service endpoints
kubectl get endpoints -n pece pece-mariadb

# Test connection from PHP pod
kubectl exec -n pece -it deployment/pece-php -- \
  mysql -h pece-mariadb -u drupal -p$DB_PASSWORD -e "SELECT 1"
```

### Ingress Not Working

```bash
# Check ingress status
kubectl get ingress -n pece
kubectl describe ingress -n pece pece-ingress

# Verify ingress controller is installed
kubectl get pods -n ingress-nginx

# Check service endpoints
kubectl get endpoints -n pece pece-nginx
```

### Performance Issues

```bash
# Check resource usage
kubectl top pods -n pece
kubectl top nodes

# Check HPA status
kubectl get hpa -n pece

# View resource limits
kubectl describe deployment/pece-php -n pece | grep -A 5 Limits
```

### Persistent Storage Issues

```bash
# Check PVC status
kubectl get pvc -n pece

# Describe PVC
kubectl describe pvc -n pece pece-files

# Verify storage class
kubectl get storageclass
```

## Maintenance

### Update Container Images

```bash
# Build new images
make build IMAGE_TAG=v1.1.0

# Push to registry
make push IMAGE_TAG=v1.1.0

# Update deployment with new images
kubectl set image deployment/pece-php -n pece \
  php=registry.example.com/pece-php:v1.1.0

kubectl set image deployment/pece-nginx -n pece \
  nginx=registry.example.com/pece-nginx:v1.1.0

# Monitor rollout
kubectl rollout status deployment/pece-php -n pece
kubectl rollout status deployment/pece-nginx -n pece
```

### Update Drupal Core and Modules

```bash
# Get shell in PHP pod
kubectl exec -n pece -it deployment/pece-php -- bash

# Inside pod
cd /var/www/html
composer update
drush -y updb
drush -y cex

# Exit and copy updated config
exit

# Copy config from pod to local
kubectl cp pece/pece-php-xxxx:/var/www/html/config ./config

# Commit config changes
git add config/
git commit -m "Update Drupal core and contrib modules"
```

### Backup Strategy

**Database Backups:**
```bash
# Manual backup
kubectl exec -n pece -it statefulset/pece-mariadb -- \
  mysqldump -u root -p$DB_ROOT_PASSWORD drupal | \
  gzip > backup-$(date +%Y%m%d-%H%M%S).sql.gz

# Automated with CronJob (create kubernetes/cronjob-backup.yaml)
kubectl apply -f kubernetes/cronjob-backup.yaml
```

**File Backups:**
```bash
# Backup files directory
kubectl cp pece/pece-php-xxxx:/var/www/html/web/sites/default/files \
  ./backups/files-$(date +%Y%m%d-%H%M%S)
```

## Environment Variables Reference

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `CONTAINER_REGISTRY` | No | Container registry URL | `registry.example.com` |
| `REGISTRY_USERNAME` | If using registry | Registry username | `admin` |
| `REGISTRY_PASSWORD` | If using registry | Registry password | `*****` |
| `IMAGE_TAG` | No | Container image tag | `v1.0.0` (default: `latest`) |
| `ENV` | No | Environment name | `production`, `staging` |
| `NAMESPACE` | No | Kubernetes namespace | `pece` (default) |
| `DB_ROOT_PASSWORD` | Yes | MariaDB root password | Generate with `openssl rand -base64 32` |
| `DB_PASSWORD` | Yes | Drupal database password | Generate with `openssl rand -base64 32` |
| `DRUPAL_HASH_SALT` | Yes | Drupal hash salt | Generate with `openssl rand -base64 48` |
| `KUBECONFIG` | No | Kubernetes config file | `~/.kube/config` |

## Security Best Practices

1. **Never commit secrets** - Use `secrets.local.yaml` (gitignored)
2. **Run as non-root** - All containers use unprivileged users
3. **Use network policies** - Restrict pod-to-pod communication
4. **Scan images** - Run `trivy image <image>` before deployment
5. **Enable RBAC** - Use service accounts with minimal permissions
6. **Use TLS** - Configure Ingress with valid SSL certificates
7. **Rotate secrets** - Regularly update database passwords and hash salts
8. **Resource limits** - Set CPU/memory limits on all containers
9. **Read-only root filesystem** - Where possible, use `readOnlyRootFilesystem: true`
10. **Keep images updated** - Regularly rebuild with latest base images

## Additional Resources

- [PECE Project Documentation](https://pece-project.github.io/drupal-pece/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Podman Documentation](https://docs.podman.io/)
- [Drupal Docker Documentation](https://www.drupal.org/docs/develop/local-server-setup/docker-development-environments)

## Support

For issues and questions:

- GitHub Issues: [PECE Project Issues](https://github.com/PECE-project/drupal-pece/issues)
- Documentation: [PECE Documentation](https://pece-project.github.io/drupal-pece/)
- Drupal Community: [Drupal.org](https://www.drupal.org/)

## License

This deployment infrastructure is part of the PECE project, licensed under [GPLv3](https://www.gnu.org/licenses/gpl-3.0.txt).
