#!/bin/bash

#
# deploy-compose.sh - Deploy PECE to VPS via Docker Compose
#
# Usage:
#   ./deploy-compose.sh [OPTIONS]
#
# Options:
#   -h, --help           Show this help message
#   --skip-env           Skip writing the .env file on the VPS
#   --dry-run            Print commands without executing remote steps
#
# Environment Variables (must be set or passed via GitHub Actions secrets):
#   VPS_HOST             VPS hostname or IP address
#   VPS_USER             SSH user on the VPS
#   VPS_SSH_KEY          Path to the SSH private key file
#   VPS_DEPLOY_PATH      Deployment directory on the VPS (default: /opt/pece2)
#   DB_NAME              MariaDB database name (default: drupal)
#   DB_USER              MariaDB application user (default: drupal)
#   DB_PASSWORD          MariaDB application user password
#   DB_ROOT_PASSWORD     MariaDB root password
#   DRUPAL_TRUSTED_HOST  Drupal trusted host pattern (e.g., pece.example.com)
#   IMAGE_TAG            Image tag to deploy (default: latest)
#
# Examples:
#   ./deploy-compose.sh
#   ./deploy-compose.sh --dry-run
#   VPS_HOST=1.2.3.4 VPS_USER=deploy ./deploy-compose.sh
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
DB_NAME="${DB_NAME:-drupal}"
DB_USER="${DB_USER:-drupal}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
DRUPAL_TRUSTED_HOST="${DRUPAL_TRUSTED_HOST:-}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
SKIP_ENV=false
DRY_RUN=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_DIR="${DEPLOY_DIR}/docker-compose"

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
    [[ -z "$VPS_HOST" ]]         && error "VPS_HOST is not set."
    [[ -z "$VPS_USER" ]]         && error "VPS_USER is not set."
    [[ -z "$VPS_SSH_KEY" ]]      && error "VPS_SSH_KEY is not set."
    [[ -z "$DB_PASSWORD" ]]      && error "DB_PASSWORD is not set."
    [[ -z "$DB_ROOT_PASSWORD" ]] && error "DB_ROOT_PASSWORD is not set."

    if [[ "$DRY_RUN" == false ]]; then
        [[ ! -f "$VPS_SSH_KEY" ]] && error "SSH key file not found: $VPS_SSH_KEY"
    fi

    if [[ ! -f "${COMPOSE_DIR}/docker-compose.yml" ]]; then
        error "docker-compose.yml not found at: ${COMPOSE_DIR}/docker-compose.yml"
    fi

    info "Validation passed"
}

# -----------------------------------------------------------------------------
# Main Steps
# -----------------------------------------------------------------------------

write_env_file() {
    if [[ "$SKIP_ENV" == true ]]; then
        info "Skipping .env file update (--skip-env)"
        return 0
    fi

    info "Writing .env file on VPS at ${VPS_DEPLOY_PATH}/.env"

    local env_content
    env_content=$(cat <<EOF
PHP_IMAGE=ghcr.io/pece-project/drupal-pece/php:${IMAGE_TAG}
NGINX_IMAGE=ghcr.io/pece-project/drupal-pece/nginx:${IMAGE_TAG}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
DRUPAL_TRUSTED_HOST=${DRUPAL_TRUSTED_HOST}
EOF
)

    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] Would write .env to ${VPS_DEPLOY_PATH}/.env"
        return 0
    fi

    ssh -i "$VPS_SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        "${VPS_USER}@${VPS_HOST}" \
        "mkdir -p '${VPS_DEPLOY_PATH}' && cat > '${VPS_DEPLOY_PATH}/.env'" <<< "$env_content"

    success ".env file written on VPS"
}

copy_compose_file() {
    info "Copying docker-compose.yml to VPS"

    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] Would scp ${COMPOSE_DIR}/docker-compose.yml → ${VPS_USER}@${VPS_HOST}:${VPS_DEPLOY_PATH}/docker-compose.yml"
        return 0
    fi

    scp -i "$VPS_SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        "${COMPOSE_DIR}/docker-compose.yml" \
        "${VPS_USER}@${VPS_HOST}:${VPS_DEPLOY_PATH}/docker-compose.yml"

    success "docker-compose.yml copied to VPS"
}

pull_and_up() {
    info "Pulling images and starting services on VPS"

    ssh_exec "cd '${VPS_DEPLOY_PATH}' && docker compose pull"
    ssh_exec "cd '${VPS_DEPLOY_PATH}' && docker compose up -d --remove-orphans"

    success "Services started"
}

verify_services() {
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] Skipping service verification"
        return 0
    fi

    info "Verifying running services"
    ssh_exec "cd '${VPS_DEPLOY_PATH}' && docker compose ps"
}

# -----------------------------------------------------------------------------
# Argument Parsing
# -----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)     show_help ;;
        --skip-env)    SKIP_ENV=true; shift ;;
        --dry-run)     DRY_RUN=true; shift ;;
        *) error "Unknown option: $1\nUse --help for usage information." ;;
    esac
done

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    section "PECE Docker Compose Deployment"
    info "Target: ${VPS_USER:-<VPS_USER>}@${VPS_HOST:-<VPS_HOST>}:${VPS_DEPLOY_PATH}"
    info "Image tag: ${IMAGE_TAG}"

    validate
    write_env_file
    copy_compose_file
    pull_and_up
    verify_services

    section "Deployment Completed Successfully"
    success "PECE is running on VPS at port 8080"
    info "Configure Easypanel to route your domain to localhost:8080"
}

main
