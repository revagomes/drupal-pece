#!/bin/bash

#
# deploy.sh - Deploy PECE Drupal application to Kubernetes
#
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Options:
#   -h, --help           Show this help message
#   -n, --namespace NS   Kubernetes namespace (default: pece)
#   -d, --dry-run        Perform a dry-run without applying changes
#   -w, --wait           Wait for rollout to complete (default: true)
#   --no-wait            Don't wait for rollout to complete
#   --skip-init          Skip database initialization
#   --force              Force deployment even if health checks fail
#
# Environment Variables:
#   KUBECONFIG           Path to kubeconfig file (default: ~/.kube/config)
#   KUBECTL              Path to kubectl binary (default: kubectl)
#   DEPLOY_TIMEOUT       Timeout for rollout in seconds (default: 600)
#
# Examples:
#   ./deploy.sh                          # Deploy to 'pece' namespace
#   ./deploy.sh -n production            # Deploy to 'production' namespace
#   ./deploy.sh --dry-run                # Preview changes without applying
#   ./deploy.sh --skip-init              # Deploy without running DB init
#

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration & Defaults
# -----------------------------------------------------------------------------

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
NAMESPACE="${NAMESPACE:-pece}"
DRY_RUN=false
WAIT_FOR_ROLLOUT=true
SKIP_INIT=false
FORCE_DEPLOY=false
KUBECTL="${KUBECTL:-kubectl}"
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-600}"

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
K8S_DIR="${DEPLOY_DIR}/kubernetes"

# Deployment order (order matters!)
readonly DEPLOY_ORDER=(
    "namespace.yaml"
    "secrets.yaml"
    "configmap.yaml"
    "pvc.yaml"
    "service-mariadb.yaml"
    "statefulset-mariadb.yaml"
    "service-php.yaml"
    "deployment-php.yaml"
    "service-nginx.yaml"
    "deployment-nginx.yaml"
    "ingress.yaml"
    "hpa.yaml"
)

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Print colored message
print_msg() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Print info message
info() {
    print_msg "$BLUE" "INFO: $1"
}

# Print success message
success() {
    print_msg "$GREEN" "SUCCESS: $1"
}

# Print warning message
warn() {
    print_msg "$YELLOW" "WARNING: $1"
}

# Print error message and exit
error() {
    print_msg "$RED" "ERROR: $1" >&2
    exit 1
}

# Print section header
section() {
    echo ""
    print_msg "$BLUE" "===================================================================="
    print_msg "$BLUE" "$1"
    print_msg "$BLUE" "===================================================================="
}

# Show help message
show_help() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

# Validate kubectl is available
validate_kubectl() {
    if ! command -v "$KUBECTL" &> /dev/null; then
        error "kubectl not found. Please install kubectl or set KUBECTL environment variable."
    fi
    info "Using kubectl: $KUBECTL"
}

# Validate cluster connectivity
validate_cluster() {
    if ! "$KUBECTL" cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster. Check your KUBECONFIG and cluster status."
    fi
    info "Connected to Kubernetes cluster"
}

# Validate manifests exist
validate_manifests() {
    local missing=0
    for manifest in "${DEPLOY_ORDER[@]}"; do
        if [[ ! -f "${K8S_DIR}/${manifest}" ]]; then
            warn "Manifest not found: ${K8S_DIR}/${manifest}"
            missing=$((missing + 1))
        fi
    done

    if [[ $missing -gt 0 ]]; then
        error "$missing manifest file(s) missing. Cannot proceed with deployment."
    fi
    info "All manifest files validated"
}

# Apply Kubernetes manifest
apply_manifest() {
    local manifest="$1"
    local manifest_path="${K8S_DIR}/${manifest}"

    info "Applying ${manifest}..."

    if [[ "$DRY_RUN" == true ]]; then
        "$KUBECTL" apply --dry-run=client -f "$manifest_path" -n "$NAMESPACE"
    else
        "$KUBECTL" apply -f "$manifest_path" -n "$NAMESPACE"
    fi

    success "Applied ${manifest}"
}

# Wait for deployment to be ready
wait_for_deployment() {
    local deployment="$1"
    local timeout="${2:-$DEPLOY_TIMEOUT}"

    if [[ "$WAIT_FOR_ROLLOUT" == false ]]; then
        info "Skipping wait for deployment: $deployment"
        return 0
    fi

    info "Waiting for deployment/${deployment} to be ready (timeout: ${timeout}s)..."

    if "$KUBECTL" rollout status deployment/"$deployment" -n "$NAMESPACE" --timeout="${timeout}s"; then
        success "Deployment ${deployment} is ready"
    else
        if [[ "$FORCE_DEPLOY" == true ]]; then
            warn "Deployment ${deployment} failed to be ready, but continuing (--force)"
        else
            error "Deployment ${deployment} failed to be ready. Use --force to override."
        fi
    fi
}

# Wait for StatefulSet to be ready
wait_for_statefulset() {
    local statefulset="$1"
    local timeout="${2:-$DEPLOY_TIMEOUT}"

    if [[ "$WAIT_FOR_ROLLOUT" == false ]]; then
        info "Skipping wait for statefulset: $statefulset"
        return 0
    fi

    info "Waiting for statefulset/${statefulset} to be ready (timeout: ${timeout}s)..."

    if "$KUBECTL" rollout status statefulset/"$statefulset" -n "$NAMESPACE" --timeout="${timeout}s"; then
        success "StatefulSet ${statefulset} is ready"
    else
        if [[ "$FORCE_DEPLOY" == true ]]; then
            warn "StatefulSet ${statefulset} failed to be ready, but continuing (--force)"
        else
            error "StatefulSet ${statefulset} failed to be ready. Use --force to override."
        fi
    fi
}

# Initialize database if needed
init_database() {
    if [[ "$SKIP_INIT" == true ]]; then
        info "Skipping database initialization (--skip-init)"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        info "Skipping database initialization (dry-run mode)"
        return 0
    fi

    section "Database Initialization"

    # Get first PHP pod
    local php_pod
    php_pod=$("$KUBECTL" get pods -n "$NAMESPACE" -l component=php-fpm -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$php_pod" ]]; then
        warn "No PHP pods found. Skipping database initialization."
        return 0
    fi

    info "Using pod: $php_pod"

    # Check if Drupal is already installed
    info "Checking Drupal installation status..."
    if "$KUBECTL" exec -n "$NAMESPACE" "$php_pod" -- vendor/bin/drush status --field=bootstrap 2>/dev/null | grep -q "Successful"; then
        info "Drupal is already installed. Skipping site installation."
        info "Running database updates..."
        "$KUBECTL" exec -n "$NAMESPACE" "$php_pod" -- vendor/bin/drush updb -y || warn "Database updates failed"
    else
        info "Installing Drupal with PECE profile..."
        "$KUBECTL" exec -n "$NAMESPACE" "$php_pod" -- vendor/bin/drush si pece --existing-config -y || warn "Site installation failed"
    fi

    success "Database initialization completed"
}

# Verify deployment health
verify_deployment() {
    if [[ "$DRY_RUN" == true ]]; then
        info "Skipping health verification (dry-run mode)"
        return 0
    fi

    section "Deployment Health Check"

    # Check all pods are running
    info "Checking pod status..."
    "$KUBECTL" get pods -n "$NAMESPACE" -l app=pece

    # Check services
    info "Checking services..."
    "$KUBECTL" get services -n "$NAMESPACE" -l app=pece

    # Check ingress
    info "Checking ingress..."
    "$KUBECTL" get ingress -n "$NAMESPACE" -l app=pece

    success "Deployment health check completed"
}

# Print deployment summary
print_summary() {
    section "Deployment Summary"
    echo "Namespace:       $NAMESPACE"
    echo "Dry Run:         $([ "$DRY_RUN" == true ] && echo "yes" || echo "no")"
    echo "Wait for Ready:  $([ "$WAIT_FOR_ROLLOUT" == true ] && echo "yes" || echo "no")"
    echo "Skip DB Init:    $([ "$SKIP_INIT" == true ] && echo "yes" || echo "no")"
    echo "Timeout:         ${DEPLOY_TIMEOUT}s"
    echo "Kubectl:         $KUBECTL"
    echo ""
}

# Get access information
print_access_info() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    section "Access Information"

    # Get ingress URL
    local ingress_host
    ingress_host=$("$KUBECTL" get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")

    if [[ -n "$ingress_host" ]]; then
        echo "Application URL: https://${ingress_host}"
    else
        warn "Ingress host not configured"
    fi

    # Get LoadBalancer IP if available
    local lb_ip
    lb_ip=$("$KUBECTL" get service nginx -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [[ -n "$lb_ip" ]]; then
        echo "LoadBalancer IP: ${lb_ip}"
    fi

    # Show kubectl commands
    echo ""
    echo "Useful commands:"
    echo "  # View pods"
    echo "  $KUBECTL get pods -n $NAMESPACE"
    echo ""
    echo "  # View logs (PHP)"
    echo "  $KUBECTL logs -n $NAMESPACE -l component=php-fpm --tail=100 -f"
    echo ""
    echo "  # Execute drush command"
    echo "  $KUBECTL exec -n $NAMESPACE -it \$(kubectl get pod -n $NAMESPACE -l component=php-fpm -o jsonpath='{.items[0].metadata.name}') -- vendor/bin/drush status"
    echo ""
}

# -----------------------------------------------------------------------------
# Argument Parsing
# -----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -w|--wait)
            WAIT_FOR_ROLLOUT=true
            shift
            ;;
        --no-wait)
            WAIT_FOR_ROLLOUT=false
            shift
            ;;
        --skip-init)
            SKIP_INIT=true
            shift
            ;;
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        *)
            error "Unknown option: $1\nUse --help for usage information."
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

main() {
    section "PECE Kubernetes Deployment"

    # Validation
    validate_kubectl
    validate_cluster
    validate_manifests

    # Show configuration
    print_summary

    # Apply manifests in order
    section "Applying Kubernetes Manifests"
    for manifest in "${DEPLOY_ORDER[@]}"; do
        apply_manifest "$manifest"
    done

    if [[ "$DRY_RUN" == true ]]; then
        section "Dry Run Completed"
        info "No changes were applied (dry-run mode)"
        exit 0
    fi

    # Wait for deployments to be ready
    section "Waiting for Resources"

    # Wait for MariaDB StatefulSet
    wait_for_statefulset "mariadb"

    # Wait for PHP Deployment
    wait_for_deployment "php"

    # Wait for Nginx Deployment
    wait_for_deployment "nginx"

    # Initialize database
    init_database

    # Verify deployment
    verify_deployment

    # Final success message
    section "Deployment Completed Successfully"
    success "All resources deployed successfully!"

    # Show access information
    print_access_info
}

# Run main function
main
