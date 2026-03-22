# End-to-End Verification Guide

This document provides comprehensive end-to-end verification procedures for the PECE Kubernetes deployment. Follow these steps to validate that the entire deployment pipeline works correctly from container build through production deployment.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Deployment Checks](#pre-deployment-checks)
3. [Step 1: Build Container Images](#step-1-build-container-images)
4. [Step 2: Apply OpenTofu Configuration](#step-2-apply-opentofu-configuration)
5. [Step 3: Deploy to Kubernetes](#step-3-deploy-to-kubernetes)
6. [Step 4: Verify Drupal Site Accessibility](#step-4-verify-drupal-site-accessibility)
7. [Step 5: Test Admin Login](#step-5-test-admin-login)
8. [Step 6: Verify File Persistence](#step-6-verify-file-persistence)
9. [Step 7: Test Rollback Functionality](#step-7-test-rollback-functionality)
10. [Troubleshooting](#troubleshooting)
11. [Cleanup](#cleanup)

---

## Prerequisites

Before starting the end-to-end verification, ensure you have the following tools installed and configured:

### Required Tools

```bash
# Container engine (Podman or Docker)
podman --version          # >= 4.0 OR
docker --version          # >= 20.10

# OpenTofu
tofu --version            # >= 1.6.0

# Kubernetes CLI
kubectl version --client  # >= 1.28

# Optional but recommended
helm version              # >= 3.0 (for Helm chart management)
```

### Environment Setup

1. **Container Registry Access** (if using private registry):
   ```bash
   export CONTAINER_REGISTRY="registry.example.com"
   export REGISTRY_USERNAME="your-username"
   export REGISTRY_PASSWORD="your-password"

   # Login to registry
   podman login $CONTAINER_REGISTRY
   ```

2. **Kubernetes Cluster Access**:
   ```bash
   # Verify cluster connectivity
   kubectl cluster-info
   kubectl get nodes

   # Ensure you have sufficient permissions
   kubectl auth can-i create namespace
   kubectl auth can-i create deployment
   ```

3. **Environment Variables**:
   ```bash
   # Copy the example file and customize
   cp deploy/opentofu/terraform.tfvars.example deploy/opentofu/terraform.tfvars

   # Edit with your values (IMPORTANT: Set secure passwords!)
   vi deploy/opentofu/terraform.tfvars
   ```

4. **Metrics Server** (required for HPA):
   ```bash
   # Check if metrics-server is installed
   kubectl get deployment metrics-server -n kube-system

   # If not installed, install it:
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

---

## Pre-Deployment Checks

Before starting the deployment, run these validation checks:

### 1. Validate Kubernetes Manifests

```bash
# Run manifest validation
cd deploy
make validate

# Or manually validate each manifest
kubectl apply --dry-run=client -f kubernetes/namespace.yaml
kubectl apply --dry-run=client -f kubernetes/configmap.yaml
kubectl apply --dry-run=client -f kubernetes/secrets.yaml
kubectl apply --dry-run=client -f kubernetes/pvc.yaml
kubectl apply --dry-run=client -f kubernetes/
```

**Expected Output**: All manifests should validate without errors.

### 2. Validate OpenTofu Configuration

```bash
# Initialize OpenTofu
cd deploy/opentofu
tofu init

# Validate configuration
tofu validate

# Preview changes (without applying)
tofu plan -var-file=terraform.tfvars
```

**Expected Output**: "Success! The configuration is valid." and a plan showing resources to create.

### 3. Lint Shell Scripts

```bash
# Lint all automation scripts
shellcheck deploy/scripts/*.sh

# Or check individually
shellcheck deploy/scripts/build.sh
shellcheck deploy/scripts/deploy.sh
shellcheck deploy/scripts/rollback.sh
```

**Expected Output**: No errors. Warnings are acceptable if they're intentional.

---

## Step 1: Build Container Images

Build production-ready container images for PHP-FPM and Nginx.

### Build All Images

```bash
cd deploy

# Build all images (default: using Podman)
make build

# Or build with Docker
BUILD_ENGINE=docker make build

# Build with specific version tag
IMAGE_TAG=v1.0.0 make build

# Build and push to registry
CONTAINER_REGISTRY=registry.example.com IMAGE_TAG=v1.0.0 make build push
```

### Verify Build Success

1. **Check Image Creation**:
   ```bash
   # List built images
   podman images | grep pece

   # Expected output:
   # pece-php     latest    <image-id>   <timestamp>   <size>
   # pece-nginx   latest    <image-id>   <timestamp>   <size>
   ```

2. **Inspect Images**:
   ```bash
   # Inspect PHP-FPM image
   podman inspect pece-php:latest | jq '.[0].Config'

   # Verify non-root user
   podman inspect pece-php:latest | jq '.[0].Config.User'
   # Expected: "www-data" or "82"

   # Inspect Nginx image
   podman inspect pece-nginx:latest | jq '.[0].Config'
   ```

3. **Test Image Functionality** (optional):
   ```bash
   # Run PHP-FPM container to verify it starts
   podman run --rm -d --name test-php pece-php:latest

   # Check if PHP-FPM is running
   podman exec test-php ps aux | grep php-fpm

   # Check health status
   podman exec test-php cgi-fcgi -bind -connect 127.0.0.1:9000

   # Cleanup
   podman stop test-php
   ```

4. **Security Scan** (recommended):
   ```bash
   # Scan for vulnerabilities (requires trivy)
   trivy image pece-php:latest
   trivy image pece-nginx:latest

   # Expected: No critical vulnerabilities
   ```

### Troubleshooting Build Issues

| Issue | Solution |
|-------|----------|
| Build fails with "permission denied" | Run with sudo or ensure user is in podman/docker group |
| "No space left on device" | Clean up old images: `podman system prune -a` |
| Composer install fails | Check network connectivity and composer cache |
| Nginx config test fails | Review nginx.conf syntax with `nginx -t` |

---

## Step 2: Apply OpenTofu Configuration

Provision Kubernetes infrastructure using OpenTofu.

### Initialize and Apply

```bash
cd deploy/opentofu

# Initialize (first time only)
tofu init

# Review the plan
tofu plan -var-file=terraform.tfvars -out=tfplan

# Review what will be created
# Expected resources:
# - kubernetes_namespace_v1.pece
# - kubernetes_config_map_v1.pece_config
# - kubernetes_secret_v1.pece_secrets
# - kubernetes_persistent_volume_claim_v1.drupal_files
# - kubernetes_persistent_volume_claim_v1.mariadb_data
# - kubernetes_horizontal_pod_autoscaler_v2.php (if enabled)
# - kubernetes_ingress_v1.pece (if enabled)
# - Plus module resources

# Apply the configuration
tofu apply tfplan

# Or apply directly with auto-approval (use with caution)
tofu apply -var-file=terraform.tfvars -auto-approve
```

### Verify OpenTofu Deployment

1. **Check Created Resources**:
   ```bash
   # View OpenTofu state
   tofu show

   # List all resources
   tofu state list

   # Get outputs
   tofu output
   ```

2. **Verify Kubernetes Resources Created**:
   ```bash
   # Check namespace
   kubectl get namespace pece

   # Check ConfigMaps
   kubectl get configmap -n pece
   kubectl describe configmap pece-config -n pece

   # Check Secrets (verify they exist, don't view values)
   kubectl get secret -n pece

   # Check PVCs
   kubectl get pvc -n pece

   # Expected status: All PVCs should be "Bound" or "Pending"
   ```

3. **Verify Storage Provisioning**:
   ```bash
   # Check PVC status
   kubectl get pvc -n pece -o wide

   # If PVCs are pending, check storage class
   kubectl get storageclass

   # Describe PVC for details
   kubectl describe pvc drupal-files -n pece
   kubectl describe pvc mariadb-data -n pece
   ```

### Expected OpenTofu Outputs

```hcl
connection_info = {
  admin_url = "https://pece.local/admin"
  database_host = "mariadb.pece.svc.cluster.local"
  nginx_fqdn = "nginx.pece.svc.cluster.local"
  php_fqdn = "php.pece.svc.cluster.local"
  web_url = "https://pece.local"
}

deployment_summary = "Deployment: pece (production) - Namespace: pece - Replicas: PHP=2, Nginx=2, MariaDB=1 - Autoscaling: enabled (2-10 replicas) - Ingress: enabled (pece.local) - TLS: enabled"

ingress_url = "https://pece.local"
namespace = "pece"
php_service_name = "php"
```

---

## Step 3: Deploy to Kubernetes

Deploy the PECE application workloads to Kubernetes.

### Deploy All Services

```bash
cd deploy

# Deploy all services
make deploy

# Or deploy with specific namespace
NAMESPACE=pece make deploy

# Deploy with waiting for rollout completion
make deploy  # (waiting is enabled by default)
```

The deploy script will:
1. Validate kubectl and cluster connectivity
2. Apply all Kubernetes manifests in order
3. Wait for rollouts to complete
4. Initialize the database if needed
5. Run health checks

### Monitor Deployment Progress

1. **Watch Pod Status**:
   ```bash
   # Watch all pods in the namespace
   kubectl get pods -n pece -w

   # Expected sequence:
   # 1. mariadb-0: Init -> Running
   # 2. php-<hash>-<hash>: Init -> Running (2 replicas)
   # 3. nginx-<hash>-<hash>: Init -> Running (2 replicas)
   ```

2. **Check Deployment Status**:
   ```bash
   # Check deployments
   kubectl get deployments -n pece

   # Expected output:
   # NAME    READY   UP-TO-DATE   AVAILABLE   AGE
   # php     2/2     2            2           5m
   # nginx   2/2     2            2           5m

   # Check StatefulSet
   kubectl get statefulset -n pece

   # Expected output:
   # NAME      READY   AGE
   # mariadb   1/1     5m
   ```

3. **View Logs**:
   ```bash
   # View deployment logs
   make logs

   # View specific component logs
   make logs COMPONENT=php
   make logs COMPONENT=nginx
   make logs COMPONENT=mariadb

   # Or use kubectl directly
   kubectl logs -n pece -l component=php-fpm --tail=100
   kubectl logs -n pece -l component=nginx --tail=100
   kubectl logs -n pece statefulset/mariadb --tail=100
   ```

4. **Check Events**:
   ```bash
   # View namespace events
   kubectl get events -n pece --sort-by='.lastTimestamp'

   # Look for warnings or errors
   kubectl get events -n pece --field-selector type=Warning
   ```

### Verify All Services Running

```bash
# Get comprehensive deployment status
make status

# Manual verification
kubectl get all -n pece -o wide

# Verify services
kubectl get svc -n pece

# Expected services:
# NAME      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
# php       ClusterIP   10.x.x.x       <none>        9000/TCP   5m
# nginx     ClusterIP   10.x.x.x       <none>        80/TCP     5m
# mariadb   ClusterIP   10.x.x.x       <none>        3306/TCP   5m

# Verify ingress
kubectl get ingress -n pece

# Expected ingress:
# NAME   CLASS   HOSTS              ADDRESS        PORTS     AGE
# pece   nginx   pece.local,...     10.x.x.x       80, 443   5m
```

### Database Initialization

The deploy script automatically initializes the database. Verify it:

```bash
# Check if Drupal is installed
kubectl exec -n pece deployment/php -- drush status

# Expected output should show:
# Drupal version         : 11.x
# Site URI               : https://pece.local
# Database               : Connected
# Drupal bootstrap       : Successful
# Default theme          : peceful
# Administration theme   : claro

# Verify configuration is imported
kubectl exec -n pece deployment/php -- drush config:status

# Expected: No differences between database and config
```

---

## Step 4: Verify Drupal Site Accessibility

Verify the Drupal site is accessible via the Ingress URL.

### Configure Local DNS (Development)

For local testing, add the ingress hostname to `/etc/hosts`:

```bash
# Get the ingress IP address
INGRESS_IP=$(kubectl get ingress pece -n pece -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# If using NodePort (for local clusters like minikube/kind)
INGRESS_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Add to /etc/hosts
echo "$INGRESS_IP pece.local www.pece.local" | sudo tee -a /etc/hosts
```

### Access the Site

1. **Homepage Access**:
   ```bash
   # Test HTTP access
   curl -I http://pece.local

   # Expected: HTTP/1.1 301 Moved Permanently (redirect to HTTPS)
   # or HTTP/1.1 200 OK (if TLS is disabled)

   # Test HTTPS access (if TLS is configured)
   curl -k -I https://pece.local

   # Expected: HTTP/2 200 (with valid certificate)
   # or HTTP/1.1 200 (if cert-manager is not configured)
   ```

2. **Browser Verification**:
   - Open browser and navigate to `https://pece.local`
   - Verify homepage loads without errors
   - Check browser console for JavaScript errors (should be none)
   - Verify static assets load (CSS, images, JavaScript)

3. **Health Endpoint Checks**:
   ```bash
   # Check PHP-FPM health (from within cluster)
   kubectl exec -n pece deployment/php -- cgi-fcgi -bind -connect 127.0.0.1:9000

   # Check Nginx health
   kubectl exec -n pece deployment/nginx -- curl -I http://localhost/

   # Check database connectivity
   kubectl exec -n pece deployment/php -- drush sql:query "SELECT 1"
   # Expected: 1
   ```

4. **Port Forward (Alternative Access)**:
   ```bash
   # If ingress is not working, use port-forward for troubleshooting
   kubectl port-forward -n pece service/nginx 8080:80

   # Access via localhost
   curl http://localhost:8080
   ```

### Verify Site Performance

```bash
# Test response time
time curl -s -o /dev/null -w "%{http_code}\n" https://pece.local

# Load testing (optional, requires Apache Bench)
ab -n 100 -c 10 https://pece.local/

# Check page load metrics
curl -w "@-" -o /dev/null -s https://pece.local <<'EOF'
    time_namelookup:  %{time_namelookup}\n
       time_connect:  %{time_connect}\n
    time_appconnect:  %{time_appconnect}\n
   time_pretransfer:  %{time_pretransfer}\n
      time_redirect:  %{time_redirect}\n
 time_starttransfer:  %{time_starttransfer}\n
                    ----------\n
         time_total:  %{time_total}\n
EOF
```

---

## Step 5: Test Admin Login

Verify that the Drupal admin account can log in successfully.

### Get Admin Credentials

```bash
# Get admin username from ConfigMap
kubectl get configmap pece-config -n pece -o jsonpath='{.data.DRUPAL_ACCOUNT_USERNAME}'
# Expected: admin

# Get admin password from Secret
kubectl get secret pece-secrets -n pece -o jsonpath='{.data.DRUPAL_ACCOUNT_PASSWORD}' | base64 -d
# This will output the admin password
```

### Test Login via CLI

```bash
# Login using drush
kubectl exec -n pece deployment/php -- drush user:login

# This will generate a one-time login URL
# Copy the URL and open in browser
```

### Test Login via Browser

1. **Navigate to Login Page**:
   - URL: `https://pece.local/user/login`
   - Enter admin username and password
   - Click "Log in"

2. **Verify Login Success**:
   - Should redirect to `/admin` or user profile page
   - Verify admin toolbar is visible
   - Check for any error messages (should be none)

3. **Test Admin Access**:
   - Navigate to `https://pece.local/admin`
   - Verify access to administration pages
   - Check Content, Structure, Configuration menus are accessible

### Verify User Permissions

```bash
# List all users
kubectl exec -n pece deployment/php -- drush user:information

# Check admin role
kubectl exec -n pece deployment/php -- drush user:role:list

# Verify admin has all permissions
kubectl exec -n pece deployment/php -- drush user:information 1
```

### Test Session Persistence

1. Log in to the site
2. Navigate to multiple pages
3. Wait 5 minutes
4. Navigate to another page
5. Verify session is still active (not logged out)

This verifies that:
- PHP sessions are working correctly
- Session affinity (sticky sessions) is configured properly
- Session storage is persisting (if using Redis/database sessions)

---

## Step 6: Verify File Persistence

Test that uploaded files persist across pod restarts.

### Upload a Test File

1. **Via Drupal Admin Interface**:
   ```
   - Login as admin
   - Navigate to: Content → Media → Add media → Image
   - Upload a test image (e.g., test-image.jpg)
   - Save the media item
   - Note the file URL (e.g., /sites/default/files/2024-02/test-image.jpg)
   ```

2. **Via Drush (Alternative)**:
   ```bash
   # Copy a test file to the pod
   kubectl cp test-image.jpg pece/php-<pod-name>:/tmp/test-image.jpg

   # Import via drush
   kubectl exec -n pece deployment/php -- drush file:import /tmp/test-image.jpg
   ```

### Verify File Exists in PVC

```bash
# List files in Drupal files directory
kubectl exec -n pece deployment/php -- ls -lah /var/www/html/web/sites/default/files/

# Verify the test file exists
kubectl exec -n pece deployment/php -- ls -lah /var/www/html/web/sites/default/files/**/test-image.jpg

# Check PVC usage
kubectl exec -n pece deployment/php -- df -h /var/www/html/web/sites/default/files
```

### Restart PHP Pod

```bash
# Get current PHP pod name
POD_NAME=$(kubectl get pod -n pece -l component=php-fpm -o jsonpath='{.items[0].metadata.name}')

# Delete the pod (it will be recreated by the Deployment)
kubectl delete pod -n pece $POD_NAME

# Wait for new pod to be ready
kubectl wait --for=condition=ready pod -n pece -l component=php-fpm --timeout=300s

# Verify new pod is running
kubectl get pods -n pece -l component=php-fpm
```

### Verify File Still Exists

```bash
# Check file exists after pod restart
kubectl exec -n pece deployment/php -- ls -lah /var/www/html/web/sites/default/files/**/test-image.jpg

# Verify file is accessible via browser
curl -I https://pece.local/sites/default/files/**/test-image.jpg
# Expected: HTTP/2 200

# Verify in Drupal UI
# Navigate to the media item created earlier
# Image should still display correctly
```

### Test with Multiple Replicas

If you have multiple PHP-FPM replicas (which you should for HA):

```bash
# Scale to 3 replicas
kubectl scale deployment php -n pece --replicas=3

# Wait for all replicas to be ready
kubectl wait --for=condition=ready pod -n pece -l component=php-fpm --timeout=300s

# Upload a file (it will go to one pod)
# Verify it's accessible from all pods
for pod in $(kubectl get pod -n pece -l component=php-fpm -o name); do
  echo "Checking $pod:"
  kubectl exec -n pece $pod -- ls -lah /var/www/html/web/sites/default/files/**/test-image.jpg
done

# All pods should see the file (due to ReadWriteMany PVC)
```

---

## Step 7: Test Rollback Functionality

Verify that the rollback mechanism works correctly.

### Create a Baseline Deployment

```bash
# Record the current deployment revision
kubectl rollout history deployment/php -n pece
kubectl rollout history deployment/nginx -n pece
kubectl rollout history statefulset/mariadb -n pece

# Note the current revision numbers
```

### Deploy a New Version

1. **Build New Image with Tag**:
   ```bash
   cd deploy
   IMAGE_TAG=v2.0.0 make build

   # Push to registry (if using remote registry)
   CONTAINER_REGISTRY=registry.example.com IMAGE_TAG=v2.0.0 make push
   ```

2. **Update Deployment with New Image**:
   ```bash
   # Update PHP deployment
   kubectl set image deployment/php -n pece \
     php=pece-php:v2.0.0 \
     --record

   # Update Nginx deployment
   kubectl set image deployment/nginx -n pece \
     nginx=pece-nginx:v2.0.0 \
     --record

   # Wait for rollout
   kubectl rollout status deployment/php -n pece
   kubectl rollout status deployment/nginx -n pece
   ```

3. **Verify New Version Running**:
   ```bash
   # Check image versions
   kubectl get deployment php -n pece -o jsonpath='{.spec.template.spec.containers[0].image}'
   kubectl get deployment nginx -n pece -o jsonpath='{.spec.template.spec.containers[0].image}'

   # Verify site still works
   curl -I https://pece.local
   ```

### Execute Rollback

1. **Using Makefile**:
   ```bash
   cd deploy

   # Rollback all deployments
   make rollback

   # Or rollback specific components
   make rollback-php
   make rollback-nginx
   make rollback-mariadb
   ```

2. **Manual Rollback**:
   ```bash
   # Rollback PHP deployment
   kubectl rollout undo deployment/php -n pece

   # Rollback Nginx deployment
   kubectl rollout undo deployment/nginx -n pece

   # Rollback to specific revision
   kubectl rollout undo deployment/php -n pece --to-revision=1
   ```

3. **Monitor Rollback Progress**:
   ```bash
   # Watch rollout status
   kubectl rollout status deployment/php -n pece
   kubectl rollout status deployment/nginx -n pece

   # View rollback events
   kubectl get events -n pece --sort-by='.lastTimestamp' | grep -i rollback
   ```

### Verify Rollback Success

```bash
# Check image versions (should be back to original)
kubectl get deployment php -n pece -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: pece-php:latest (or previous version)

# Verify all pods are running
kubectl get pods -n pece

# Test site accessibility
curl -I https://pece.local
# Expected: HTTP/2 200

# Verify Drupal status
kubectl exec -n pece deployment/php -- drush status
```

### Test Rollback with Database Backup

```bash
# Create database backup before rollback
cd deploy
make rollback-all --backup-db

# This will:
# 1. Create a database backup in ./backups/
# 2. Perform the rollback
# 3. Preserve the backup for recovery if needed

# List backups
ls -lh ./backups/

# Restore from backup if needed
make rollback --restore-db=./backups/pece-drupal-YYYYMMDD-HHMMSS.sql.gz
```

### Measure Rollback Time

```bash
# Time the rollback operation
time make rollback

# Target: Should complete within 5 minutes (300 seconds)
# Actual time depends on:
# - Number of replicas
# - Image pull time
# - Pod startup time
# - Health check intervals
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Pods Not Starting

**Symptoms**:
- Pods stuck in `Pending`, `CrashLoopBackOff`, or `ImagePullBackOff` state

**Diagnosis**:
```bash
# Check pod status
kubectl get pods -n pece

# Describe pod for details
kubectl describe pod <pod-name> -n pece

# Check pod logs
kubectl logs <pod-name> -n pece
kubectl logs <pod-name> -n pece --previous  # for crashed pods
```

**Common Causes**:

| Issue | Symptom | Solution |
|-------|---------|----------|
| ImagePullBackOff | Cannot pull container image | Verify image exists, check registry credentials |
| CrashLoopBackOff | Container starts then crashes | Check logs for errors, verify environment variables |
| Pending (PVC) | PVC not bound | Check storage class exists, ensure PV provisioner is running |
| Pending (Resources) | Insufficient resources | Check node resources: `kubectl top nodes` |

#### 2. Database Connection Failures

**Symptoms**:
- PHP pods log "SQLSTATE[HY000] [2002] Connection refused"
- Drupal shows database connection errors

**Diagnosis**:
```bash
# Check MariaDB pod is running
kubectl get pod -n pece -l component=database

# Check MariaDB logs
kubectl logs -n pece statefulset/mariadb --tail=50

# Test database connectivity from PHP pod
kubectl exec -n pece deployment/php -- nc -zv mariadb 3306

# Verify database credentials
kubectl get secret pece-secrets -n pece -o jsonpath='{.data}' | jq
```

**Solutions**:
- Ensure MariaDB pod is running: `kubectl get statefulset mariadb -n pece`
- Verify service exists: `kubectl get svc mariadb -n pece`
- Check credentials match between ConfigMap/Secret and MariaDB
- Verify MariaDB is accepting connections: `kubectl exec -n pece statefulset/mariadb -- mysqladmin ping`

#### 3. Ingress Not Working

**Symptoms**:
- Cannot access site via ingress URL
- `curl` returns connection refused or timeout

**Diagnosis**:
```bash
# Check ingress status
kubectl get ingress pece -n pece
kubectl describe ingress pece -n pece

# Check ingress controller is running
kubectl get pods -n ingress-nginx  # or appropriate namespace

# Check nginx service
kubectl get svc nginx -n pece

# Test direct service access (bypass ingress)
kubectl port-forward -n pece svc/nginx 8080:80
curl http://localhost:8080
```

**Solutions**:
- Install ingress controller if missing (e.g., nginx-ingress-controller)
- Verify ingress class matches controller: `kubectl get ingressclass`
- Check DNS/hosts file for correct hostname mapping
- Verify TLS certificate if using HTTPS (check cert-manager)

#### 4. File Upload Failures

**Symptoms**:
- "Unable to create directory" errors in Drupal
- File uploads fail

**Diagnosis**:
```bash
# Check PVC status
kubectl get pvc drupal-files -n pece

# Check mount in pod
kubectl exec -n pece deployment/php -- mount | grep "/var/www/html"

# Check permissions
kubectl exec -n pece deployment/php -- ls -ld /var/www/html/web/sites/default/files

# Check disk space
kubectl exec -n pece deployment/php -- df -h /var/www/html/web/sites/default/files
```

**Solutions**:
- Ensure PVC is bound: `kubectl describe pvc drupal-files -n pece`
- Fix permissions: `kubectl exec -n pece deployment/php -- chown -R www-data:www-data /var/www/html/web/sites/default/files`
- Increase PVC size if full (requires storage class support for volume expansion)
- Verify access mode is ReadWriteMany for multi-pod setups

#### 5. Performance Issues

**Symptoms**:
- Slow page loads
- High CPU/memory usage

**Diagnosis**:
```bash
# Check resource usage
kubectl top pods -n pece
kubectl top nodes

# Check HPA status
kubectl get hpa -n pece

# Check for resource limits being hit
kubectl describe pod <pod-name> -n pece | grep -A 5 "Limits\|Requests"

# Check OPcache status
kubectl exec -n pece deployment/php -- php -r "var_dump(opcache_get_status());"
```

**Solutions**:
- Scale up replicas: `kubectl scale deployment php -n pece --replicas=5`
- Increase resource limits in deployment manifests
- Enable and tune OPcache (should be enabled by default)
- Enable Redis caching if not already enabled
- Check for slow database queries: `kubectl exec -n pece deployment/php -- drush sql:query "SHOW PROCESSLIST"`

#### 6. HPA Not Scaling

**Symptoms**:
- HPA shows `<unknown>` for metrics
- Pods don't scale despite high load

**Diagnosis**:
```bash
# Check HPA status
kubectl get hpa -n pece
kubectl describe hpa php -n pece

# Check metrics-server
kubectl get deployment metrics-server -n kube-system
kubectl logs -n kube-system deployment/metrics-server

# Test metrics API
kubectl top pods -n pece
```

**Solutions**:
- Install metrics-server if missing
- Verify metrics-server has correct flags (e.g., `--kubelet-insecure-tls` for local clusters)
- Check resource requests are set on pods (HPA requires them)
- Wait a few minutes for metrics to populate

---

## Cleanup

### Remove Deployment (Keep Infrastructure)

```bash
cd deploy

# Remove application workloads only
kubectl delete -f kubernetes/deployment-php.yaml
kubectl delete -f kubernetes/deployment-nginx.yaml
kubectl delete -f kubernetes/statefulset-mariadb.yaml
kubectl delete -f kubernetes/service-php.yaml
kubectl delete -f kubernetes/service-nginx.yaml
kubectl delete -f kubernetes/service-mariadb.yaml
kubectl delete -f kubernetes/ingress.yaml
kubectl delete -f kubernetes/hpa.yaml

# Keep: namespace, configmaps, secrets, PVCs (preserves data)
```

### Full Cleanup (Including Data)

```bash
# Delete everything created by OpenTofu
cd deploy/opentofu
tofu destroy -var-file=terraform.tfvars

# Or manually delete namespace (this will delete everything in it)
kubectl delete namespace pece

# Cleanup local files
cd deploy
rm -rf ./backups/  # Remove database backups
```

### Cleanup Container Images

```bash
# Remove local images
podman rmi pece-php:latest pece-nginx:latest
podman rmi pece-php:v2.0.0 pece-nginx:v2.0.0

# Or remove all PECE images
podman images | grep pece | awk '{print $3}' | xargs podman rmi

# Cleanup build cache
podman system prune -a
```

---

## Success Criteria Checklist

Use this checklist to verify all end-to-end verification steps are complete:

- [ ] **Step 1 - Build Images**
  - [ ] PHP-FPM image builds successfully
  - [ ] Nginx image builds successfully
  - [ ] Images run as non-root user
  - [ ] Images pass security scan (no critical vulnerabilities)

- [ ] **Step 2 - OpenTofu**
  - [ ] OpenTofu configuration validates
  - [ ] `tofu apply` completes without errors
  - [ ] Namespace created
  - [ ] ConfigMaps created
  - [ ] Secrets created
  - [ ] PVCs bound to persistent volumes

- [ ] **Step 3 - Deploy to Kubernetes**
  - [ ] All pods reach Running state
  - [ ] PHP deployment has 2/2 replicas ready
  - [ ] Nginx deployment has 2/2 replicas ready
  - [ ] MariaDB StatefulSet has 1/1 replicas ready
  - [ ] All services created
  - [ ] Ingress created and has IP address
  - [ ] Database initialized with `drush si`
  - [ ] Configuration imported with `drush cim`

- [ ] **Step 4 - Site Accessibility**
  - [ ] Site accessible via ingress URL
  - [ ] Homepage loads without errors
  - [ ] No browser console errors
  - [ ] Static assets load correctly
  - [ ] Health checks pass

- [ ] **Step 5 - Admin Login**
  - [ ] Admin credentials retrieved from secrets
  - [ ] Login via web UI successful
  - [ ] Admin toolbar visible after login
  - [ ] Administration pages accessible
  - [ ] Session persists across page loads

- [ ] **Step 6 - File Persistence**
  - [ ] File upload succeeds
  - [ ] File visible in PVC
  - [ ] File persists after pod restart
  - [ ] File accessible from all replicas
  - [ ] File accessible via browser

- [ ] **Step 7 - Rollback**
  - [ ] New version deployment succeeds
  - [ ] Rollback command executes successfully
  - [ ] Rollback completes within 5 minutes
  - [ ] Previous version restored
  - [ ] Site functional after rollback
  - [ ] Database backup created (if using --backup-db)

- [ ] **Security**
  - [ ] All containers run as non-root
  - [ ] No secrets in environment variables (using secretKeyRef)
  - [ ] Resource limits set on all containers
  - [ ] Network policies configured (optional)

- [ ] **Performance**
  - [ ] HPA functional (if metrics-server installed)
  - [ ] Page load time < 2 seconds
  - [ ] No resource limit warnings

---

## Additional Verification

### Health Status Report

Run this comprehensive health check:

```bash
#!/bin/bash
# health-check.sh - Comprehensive deployment health check

echo "=== PECE Kubernetes Deployment Health Check ==="
echo ""

echo "1. Namespace Status:"
kubectl get namespace pece
echo ""

echo "2. Pod Status:"
kubectl get pods -n pece -o wide
echo ""

echo "3. Deployment Status:"
kubectl get deployments -n pece
echo ""

echo "4. StatefulSet Status:"
kubectl get statefulset -n pece
echo ""

echo "5. Service Status:"
kubectl get svc -n pece
echo ""

echo "6. Ingress Status:"
kubectl get ingress -n pece
echo ""

echo "7. PVC Status:"
kubectl get pvc -n pece
echo ""

echo "8. HPA Status:"
kubectl get hpa -n pece
echo ""

echo "9. ConfigMap Status:"
kubectl get configmap -n pece
echo ""

echo "10. Secret Status:"
kubectl get secret -n pece
echo ""

echo "11. Resource Usage:"
kubectl top pods -n pece
echo ""

echo "12. Recent Events:"
kubectl get events -n pece --sort-by='.lastTimestamp' | tail -20
echo ""

echo "13. Drupal Status:"
kubectl exec -n pece deployment/php -- drush status
echo ""

echo "14. Database Connectivity:"
kubectl exec -n pece deployment/php -- drush sql:query "SELECT 1" && echo "Database: OK" || echo "Database: FAILED"
echo ""

echo "15. Web Accessibility:"
INGRESS_URL=$(kubectl get ingress pece -n pece -o jsonpath='{.spec.rules[0].host}')
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" "http://$INGRESS_URL" || echo "Web Access: FAILED"
echo ""

echo "=== Health Check Complete ==="
```

Save as `health-check.sh`, make executable (`chmod +x health-check.sh`), and run: `./health-check.sh`

---

## Next Steps

After successful end-to-end verification:

1. **Production Hardening**:
   - Enable TLS/HTTPS with valid certificates (cert-manager + Let's Encrypt)
   - Configure network policies for stricter security
   - Set up monitoring (Prometheus + Grafana)
   - Configure log aggregation (ELK/Loki)
   - Implement automated backups

2. **CI/CD Integration**:
   - Set up GitHub Actions / GitLab CI for automated builds
   - Implement automated testing in pipeline
   - Configure automated deployments to staging/production
   - Add security scanning to pipeline

3. **Operational Excellence**:
   - Document runbook for common operations
   - Set up alerting (Alertmanager)
   - Create disaster recovery plan
   - Perform regular backup/restore drills
   - Establish SLO/SLI metrics

4. **Scaling and Optimization**:
   - Tune resource requests/limits based on actual usage
   - Implement CDN for static assets
   - Configure Redis for session and cache storage
   - Enable Solr for search functionality
   - Optimize database queries and indexes

---

## References

- [Deploy README](./README.md) - General deployment documentation
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Drupal on Kubernetes Best Practices](https://www.drupal.org/docs/administering-a-drupal-site/running-drupal-on-kubernetes)
- [PECE Project Documentation](../README.md)

---

**Document Version**: 1.0.0
**Last Updated**: 2026-02-13
**Maintained by**: PECE DevOps Team
