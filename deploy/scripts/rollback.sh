#!/bin/bash

#
# rollback.sh - Rollback PECE Drupal deployment to previous version
#
# Usage:
#   ./rollback.sh [OPTIONS] [RESOURCE]
#
# Resources:
#   php         - Rollback PHP-FPM deployment only
#   nginx       - Rollback Nginx deployment only
#   mariadb     - Rollback MariaDB statefulset only
#   all         - Rollback all deployments (default)
#
# Options:
#   -h, --help                Show this help message
#   -n, --namespace NS        Kubernetes namespace (default: pece)
#   -r, --revision NUM        Rollback to specific revision (default: 0 = previous)
#   -w, --wait                Wait for rollout to complete (default: true)
#   --no-wait                 Don't wait for rollout to complete
#   --backup-db               Backup database before rollback
#   --restore-db FILE         Restore database from backup file after rollback
#   --list-revisions          List available revisions and exit
#   --force                   Force rollback even if health checks fail
#   --dry-run                 Show what would be rolled back without doing it
#
# Environment Variables:
#   KUBECONFIG              Path to kubeconfig file (default: ~/.kube/config)
#   KUBECTL                 Path to kubectl binary (default: kubectl)
#   ROLLBACK_TIMEOUT        Timeout for rollout in seconds (default: 300)
#   DB_BACKUP_DIR           Directory for database backups (default: ./backups)
#
# Examples:
#   ./rollback.sh                              # Rollback all to previous version
#   ./rollback.sh -n production php            # Rollback only PHP in production
#   ./rollback.sh -r 3                         # Rollback to specific revision 3
#   ./rollback.sh --backup-db                  # Backup DB before rollback
#   ./rollback.sh --restore-db backup.sql      # Restore DB from backup
#   ./rollback.sh --list-revisions             # List available revisions
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
REVISION="0"
WAIT_FOR_ROLLOUT=true
BACKUP_DB=false
RESTORE_DB=""
LIST_REVISIONS=false
FORCE_ROLLBACK=false
DRY_RUN=false
RESOURCE="all"
KUBECTL="${KUBECTL:-kubectl}"
ROLLBACK_TIMEOUT="${ROLLBACK_TIMEOUT:-300}"
DB_BACKUP_DIR="${DB_BACKUP_DIR:-./backups}"

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

# Resources that support rollback
readonly DEPLOYMENTS=("php" "nginx")
readonly STATEFULSETS=("mariadb")

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

# Validate namespace exists
validate_namespace() {
    if ! "$KUBECTL" get namespace "$NAMESPACE" &> /dev/null; then
        error "Namespace '$NAMESPACE' does not exist."
    fi
    info "Namespace '$NAMESPACE' exists"
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"

    "$KUBECTL" get "$resource_type" "$resource_name" -n "$NAMESPACE" &> /dev/null
}

# List revisions for a deployment
list_deployment_revisions() {
    local deployment="$1"

    if ! resource_exists deployment "$deployment"; then
        warn "Deployment '$deployment' not found in namespace '$NAMESPACE'"
        return 1
    fi

    echo ""
    print_msg "$BLUE" "Revisions for deployment/$deployment:"
    "$KUBECTL" rollout history deployment/"$deployment" -n "$NAMESPACE"
}

# List revisions for a statefulset
list_statefulset_revisions() {
    local statefulset="$1"

    if ! resource_exists statefulset "$statefulset"; then
        warn "StatefulSet '$statefulset' not found in namespace '$NAMESPACE'"
        return 1
    fi

    echo ""
    print_msg "$BLUE" "Revisions for statefulset/$statefulset:"
    "$KUBECTL" rollout history statefulset/"$statefulset" -n "$NAMESPACE"
}

# List all available revisions
list_all_revisions() {
    section "Available Revisions"

    for deployment in "${DEPLOYMENTS[@]}"; do
        list_deployment_revisions "$deployment" || true
    done

    for statefulset in "${STATEFULSETS[@]}"; do
        list_statefulset_revisions "$statefulset" || true
    done

    echo ""
}

# Backup database
backup_database() {
    if [[ "$BACKUP_DB" == false ]]; then
        info "Skipping database backup (--backup-db not specified)"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        info "Would backup database (dry-run mode)"
        return 0
    fi

    section "Database Backup"

    # Create backup directory
    mkdir -p "$DB_BACKUP_DIR"

    # Get first PHP pod
    local php_pod
    php_pod=$("$KUBECTL" get pods -n "$NAMESPACE" -l component=php-fpm -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$php_pod" ]]; then
        error "No PHP pods found. Cannot backup database."
    fi

    info "Using pod: $php_pod"

    # Generate backup filename with timestamp
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="${DB_BACKUP_DIR}/drupal-backup-${timestamp}.sql.gz"

    info "Creating database backup: $backup_file"

    # Execute drush sql-dump and save locally
    if "$KUBECTL" exec -n "$NAMESPACE" "$php_pod" -- vendor/bin/drush sql-dump --gzip 2>/dev/null | gunzip > "${backup_file%.gz}"; then
        gzip "${backup_file%.gz}"
        success "Database backed up to: $backup_file"
        echo "Backup file: $backup_file" > "${DB_BACKUP_DIR}/latest-backup.txt"
    else
        error "Database backup failed"
    fi
}

# Restore database
restore_database() {
    if [[ -z "$RESTORE_DB" ]]; then
        info "Skipping database restore (--restore-db not specified)"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        info "Would restore database from: $RESTORE_DB (dry-run mode)"
        return 0
    fi

    if [[ ! -f "$RESTORE_DB" ]]; then
        error "Database backup file not found: $RESTORE_DB"
    fi

    section "Database Restore"

    # Get first PHP pod
    local php_pod
    php_pod=$("$KUBECTL" get pods -n "$NAMESPACE" -l component=php-fpm -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$php_pod" ]]; then
        error "No PHP pods found. Cannot restore database."
    fi

    info "Using pod: $php_pod"
    info "Restoring database from: $RESTORE_DB"

    # Restore database
    if [[ "$RESTORE_DB" == *.gz ]]; then
        # Compressed file
        if gunzip -c "$RESTORE_DB" | "$KUBECTL" exec -i -n "$NAMESPACE" "$php_pod" -- vendor/bin/drush sql-cli; then
            success "Database restored from: $RESTORE_DB"
        else
            error "Database restore failed"
        fi
    else
        # Uncompressed file
        if "$KUBECTL" exec -i -n "$NAMESPACE" "$php_pod" -- vendor/bin/drush sql-cli < "$RESTORE_DB"; then
            success "Database restored from: $RESTORE_DB"
        else
            error "Database restore failed"
        fi
    fi

    # Run database updates
    info "Running database updates..."
    "$KUBECTL" exec -n "$NAMESPACE" "$php_pod" -- vendor/bin/drush updb -y || warn "Database updates failed"

    # Clear cache
    info "Clearing Drupal cache..."
    "$KUBECTL" exec -n "$NAMESPACE" "$php_pod" -- vendor/bin/drush cr || warn "Cache clear failed"
}

# Rollback deployment
rollback_deployment() {
    local deployment="$1"

    if ! resource_exists deployment "$deployment"; then
        warn "Deployment '$deployment' not found. Skipping."
        return 0
    fi

    section "Rolling Back Deployment: $deployment"

    if [[ "$DRY_RUN" == true ]]; then
        info "Would rollback deployment/$deployment to revision $REVISION (dry-run mode)"
        return 0
    fi

    # Build rollback command
    local rollback_cmd="$KUBECTL rollout undo deployment/$deployment -n $NAMESPACE"
    if [[ "$REVISION" != "0" ]]; then
        rollback_cmd="$rollback_cmd --to-revision=$REVISION"
    fi

    info "Executing rollback..."
    if $rollback_cmd; then
        success "Rollback initiated for deployment/$deployment"
    else
        if [[ "$FORCE_ROLLBACK" == true ]]; then
            warn "Rollback failed for deployment/$deployment, but continuing (--force)"
        else
            error "Rollback failed for deployment/$deployment. Use --force to override."
        fi
    fi

    # Wait for rollout if requested
    if [[ "$WAIT_FOR_ROLLOUT" == true ]]; then
        wait_for_deployment "$deployment"
    fi
}

# Rollback statefulset
rollback_statefulset() {
    local statefulset="$1"

    if ! resource_exists statefulset "$statefulset"; then
        warn "StatefulSet '$statefulset' not found. Skipping."
        return 0
    fi

    section "Rolling Back StatefulSet: $statefulset"

    if [[ "$DRY_RUN" == true ]]; then
        info "Would rollback statefulset/$statefulset to revision $REVISION (dry-run mode)"
        return 0
    fi

    # Build rollback command
    local rollback_cmd="$KUBECTL rollout undo statefulset/$statefulset -n $NAMESPACE"
    if [[ "$REVISION" != "0" ]]; then
        rollback_cmd="$rollback_cmd --to-revision=$REVISION"
    fi

    info "Executing rollback..."
    if $rollback_cmd; then
        success "Rollback initiated for statefulset/$statefulset"
    else
        if [[ "$FORCE_ROLLBACK" == true ]]; then
            warn "Rollback failed for statefulset/$statefulset, but continuing (--force)"
        else
            error "Rollback failed for statefulset/$statefulset. Use --force to override."
        fi
    fi

    # Wait for rollout if requested
    if [[ "$WAIT_FOR_ROLLOUT" == true ]]; then
        wait_for_statefulset "$statefulset"
    fi
}

# Wait for deployment to be ready
wait_for_deployment() {
    local deployment="$1"
    local timeout="${2:-$ROLLBACK_TIMEOUT}"

    if [[ "$WAIT_FOR_ROLLOUT" == false ]]; then
        info "Skipping wait for deployment: $deployment"
        return 0
    fi

    info "Waiting for deployment/${deployment} to be ready (timeout: ${timeout}s)..."

    if "$KUBECTL" rollout status deployment/"$deployment" -n "$NAMESPACE" --timeout="${timeout}s"; then
        success "Deployment ${deployment} is ready"
    else
        if [[ "$FORCE_ROLLBACK" == true ]]; then
            warn "Deployment ${deployment} failed to be ready, but continuing (--force)"
        else
            error "Deployment ${deployment} failed to be ready. Use --force to override."
        fi
    fi
}

# Wait for StatefulSet to be ready
wait_for_statefulset() {
    local statefulset="$1"
    local timeout="${2:-$ROLLBACK_TIMEOUT}"

    if [[ "$WAIT_FOR_ROLLOUT" == false ]]; then
        info "Skipping wait for statefulset: $statefulset"
        return 0
    fi

    info "Waiting for statefulset/${statefulset} to be ready (timeout: ${timeout}s)..."

    if "$KUBECTL" rollout status statefulset/"$statefulset" -n "$NAMESPACE" --timeout="${timeout}s"; then
        success "StatefulSet ${statefulset} is ready"
    else
        if [[ "$FORCE_ROLLBACK" == true ]]; then
            warn "StatefulSet ${statefulset} failed to be ready, but continuing (--force)"
        else
            error "StatefulSet ${statefulset} failed to be ready. Use --force to override."
        fi
    fi
}

# Verify deployment health
verify_rollback() {
    if [[ "$DRY_RUN" == true ]]; then
        info "Skipping health verification (dry-run mode)"
        return 0
    fi

    section "Rollback Health Check"

    # Check all pods are running
    info "Checking pod status..."
    "$KUBECTL" get pods -n "$NAMESPACE" -l app=pece

    # Check specific resources based on what was rolled back
    if [[ "$RESOURCE" == "all" ]] || [[ "$RESOURCE" == "php" ]]; then
        info "Checking PHP deployment..."
        "$KUBECTL" get deployment php -n "$NAMESPACE"
    fi

    if [[ "$RESOURCE" == "all" ]] || [[ "$RESOURCE" == "nginx" ]]; then
        info "Checking Nginx deployment..."
        "$KUBECTL" get deployment nginx -n "$NAMESPACE"
    fi

    if [[ "$RESOURCE" == "all" ]] || [[ "$RESOURCE" == "mariadb" ]]; then
        info "Checking MariaDB statefulset..."
        "$KUBECTL" get statefulset mariadb -n "$NAMESPACE"
    fi

    success "Rollback health check completed"
}

# Print rollback summary
print_summary() {
    section "Rollback Configuration"
    echo "Namespace:       $NAMESPACE"
    echo "Resource:        $RESOURCE"
    echo "Revision:        $([ "$REVISION" == "0" ] && echo "previous" || echo "$REVISION")"
    echo "Wait for Ready:  $([ "$WAIT_FOR_ROLLOUT" == true ] && echo "yes" || echo "no")"
    echo "Backup DB:       $([ "$BACKUP_DB" == true ] && echo "yes" || echo "no")"
    echo "Restore DB:      $([ -n "$RESTORE_DB" ] && echo "$RESTORE_DB" || echo "no")"
    echo "Dry Run:         $([ "$DRY_RUN" == true ] && echo "yes" || echo "no")"
    echo "Timeout:         ${ROLLBACK_TIMEOUT}s"
    echo "Kubectl:         $KUBECTL"
    echo ""
}

# Print access information
print_access_info() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    section "Post-Rollback Information"

    # Get ingress URL
    local ingress_host
    ingress_host=$("$KUBECTL" get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")

    if [[ -n "$ingress_host" ]]; then
        echo "Application URL: https://${ingress_host}"
    fi

    # Show kubectl commands
    echo ""
    echo "Useful commands:"
    echo "  # Check rollout history"
    echo "  $KUBECTL rollout history deployment/php -n $NAMESPACE"
    echo ""
    echo "  # View pods"
    echo "  $KUBECTL get pods -n $NAMESPACE"
    echo ""
    echo "  # View logs (PHP)"
    echo "  $KUBECTL logs -n $NAMESPACE -l component=php-fpm --tail=100 -f"
    echo ""
    echo "  # Check Drupal status"
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
        -r|--revision)
            REVISION="$2"
            shift 2
            ;;
        -w|--wait)
            WAIT_FOR_ROLLOUT=true
            shift
            ;;
        --no-wait)
            WAIT_FOR_ROLLOUT=false
            shift
            ;;
        --backup-db)
            BACKUP_DB=true
            shift
            ;;
        --restore-db)
            RESTORE_DB="$2"
            shift 2
            ;;
        --list-revisions)
            LIST_REVISIONS=true
            shift
            ;;
        --force)
            FORCE_ROLLBACK=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        php|nginx|mariadb|all)
            RESOURCE="$1"
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
    section "PECE Kubernetes Rollback"

    # Validation
    validate_kubectl
    validate_cluster
    validate_namespace

    # List revisions if requested
    if [[ "$LIST_REVISIONS" == true ]]; then
        list_all_revisions
        exit 0
    fi

    # Show configuration
    print_summary

    # Backup database if requested
    if [[ "$BACKUP_DB" == true ]]; then
        backup_database
    fi

    # Execute rollback based on resource
    section "Executing Rollback"

    case "$RESOURCE" in
        php)
            rollback_deployment "php"
            ;;
        nginx)
            rollback_deployment "nginx"
            ;;
        mariadb)
            rollback_statefulset "mariadb"
            ;;
        all)
            # Rollback in reverse order: nginx, php, then mariadb
            rollback_deployment "nginx"
            rollback_deployment "php"
            rollback_statefulset "mariadb"
            ;;
        *)
            error "Unknown resource: $RESOURCE"
            ;;
    esac

    # Restore database if requested
    if [[ -n "$RESTORE_DB" ]]; then
        restore_database
    fi

    # Verify rollback
    verify_rollback

    # Final success message
    section "Rollback Completed Successfully"
    success "All resources rolled back successfully!"

    if [[ "$BACKUP_DB" == true ]]; then
        info "Database backup saved to: ${DB_BACKUP_DIR}/"
    fi

    # Show access information
    print_access_info
}

# Run main function
main
