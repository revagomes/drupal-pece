#!/bin/bash

#
# rollback-compose.sh - Rollback PECE Docker Compose deployment to a previous image tag
#
# Usage:
#   ./rollback-compose.sh [OPTIONS]
#
# Options:
#   -h, --help           Show this help message
#   -t, --tag TAG        Image tag to rollback to (required, e.g. sha-abc1234)
#   --dry-run            Print commands without executing remote steps
#
# Environment Variables:
#   VPS_HOST             VPS hostname or IP address
#   VPS_USER             SSH user on the VPS
#   VPS_SSH_KEY          Path to the SSH private key file
#   VPS_DEPLOY_PATH      Deployment directory on the VPS (default: /opt/pece2)
#
# Examples:
#   ./rollback-compose.sh --tag sha-abc1234
#   TAG=sha-abc1234 ./rollback-compose.sh
#   ./rollback-compose.sh --tag sha-abc1234 --dry-run
#

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration & Defaults
# -----------------------------------------------------------------------------

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

VPS_HOST="${VPS_HOST:-}"
VPS_USER="${VPS_USER:-}"
VPS_SSH_KEY="${VPS_SSH_KEY:-}"
VPS_DEPLOY_PATH="${VPS_DEPLOY_PATH:-/opt/pece2}"
TAG="${TAG:-}"
DRY_RUN=false

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_msg() { echo -e "${1}${2}${NC}"; }
info()    { print_msg "$BLUE"   "INFO: $1"; }
success() { print_msg "$GREEN"  "SUCCESS: $1"; }
warn()    { print_msg "$YELLOW" "WARNING: $1"; }
error()   { print_msg "$RED"    "ERROR: $1" >&2; exit 1; }

section() {
    echo ""
    print_msg "$BLUE" "===================================================================="
    print_msg "$BLUE" "$1"
    print_msg "$BLUE" "===================================================================="
}

show_help() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

ssh_exec() {
    local cmd="$1"
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] ssh ${VPS_USER}@${VPS_HOST}: $cmd"
        return 0
    fi
    ssh -i "$VPS_SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        "${VPS_USER}@${VPS_HOST}" "$cmd"
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

validate() {
    [[ -z "$VPS_HOST" ]]    && error "VPS_HOST is not set."
    [[ -z "$VPS_USER" ]]    && error "VPS_USER is not set."
    [[ -z "$VPS_SSH_KEY" ]] && error "VPS_SSH_KEY is not set."
    [[ -z "$TAG" ]]         && error "TAG is not set. Use --tag sha-<commit> or set TAG env var."

    if [[ "$DRY_RUN" == false ]]; then
        [[ ! -f "$VPS_SSH_KEY" ]] && error "SSH key file not found: $VPS_SSH_KEY"
    fi

    info "Validation passed — rolling back to tag: $TAG"
}

# -----------------------------------------------------------------------------
# Rollback Steps
# -----------------------------------------------------------------------------

update_image_tags() {
    info "Updating PHP_IMAGE and NGINX_IMAGE in .env to tag: ${TAG}"

    # Use sed to replace only the tag portion of the image lines
    local sed_cmd
    sed_cmd="sed -i \
        -e 's|^PHP_IMAGE=.*|PHP_IMAGE=ghcr.io/pece-project/drupal-pece/php:${TAG}|' \
        -e 's|^NGINX_IMAGE=.*|NGINX_IMAGE=ghcr.io/pece-project/drupal-pece/nginx:${TAG}|' \
        '${VPS_DEPLOY_PATH}/.env'"

    ssh_exec "$sed_cmd"
    success ".env updated to tag ${TAG}"
}

pull_and_restart() {
    info "Pulling rollback images (tag: ${TAG})"
    ssh_exec "cd '${VPS_DEPLOY_PATH}' && docker compose pull php nginx"

    info "Restarting PHP and Nginx containers"
    ssh_exec "cd '${VPS_DEPLOY_PATH}' && docker compose up -d --no-deps php nginx"

    success "Rollback containers started"
}

verify_services() {
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] Skipping service verification"
        return 0
    fi

    info "Verifying running services after rollback"
    ssh_exec "cd '${VPS_DEPLOY_PATH}' && docker compose ps"
}

# -----------------------------------------------------------------------------
# Argument Parsing
# -----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            error "Unknown option: $1\nUse --help for usage information."
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    section "PECE Docker Compose Rollback"
    info "Target: ${VPS_USER:-<VPS_USER>}@${VPS_HOST:-<VPS_HOST>}:${VPS_DEPLOY_PATH}"
    info "Rollback tag: ${TAG:-<not set>}"

    validate
    update_image_tags
    pull_and_restart
    verify_services

    section "Rollback Completed Successfully"
    success "PECE is running image tag: ${TAG}"
    info "To redeploy latest: make compose-deploy"
}

main
