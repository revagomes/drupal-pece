#!/bin/bash

#
# build.sh - Build container images for PECE Drupal deployment
#
# Usage:
#   ./build.sh [OPTIONS] [SERVICE]
#
# Services:
#   php      - Build PHP-FPM image only
#   nginx    - Build Nginx image only
#   all      - Build all images (default)
#
# Options:
#   -h, --help           Show this help message
#   -v, --version TAG    Tag version (default: latest)
#   -r, --registry URL   Container registry URL (e.g., registry.example.com)
#   -p, --push           Push images to registry after build
#   -n, --no-cache       Build without using cache
#   --no-parallel        Build images sequentially instead of in parallel
#
# Environment Variables:
#   PROJECT_NAME         Project name for image tagging (default: pece)
#   CONTAINER_REGISTRY   Registry URL (can be overridden with -r)
#   IMAGE_TAG            Version tag (can be overridden with -v)
#   BUILD_ENGINE         Container build tool: podman or docker (default: podman)
#
# Examples:
#   ./build.sh                                    # Build all images with 'latest' tag
#   ./build.sh -v 1.0.0 php                      # Build PHP image with version 1.0.0
#   ./build.sh -r registry.io/pece -p -v 1.0.0   # Build, tag, and push all images
#   ./build.sh --no-cache nginx                  # Build Nginx without cache
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
PROJECT_NAME="${PROJECT_NAME:-pece}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-}"
BUILD_ENGINE="${BUILD_ENGINE:-podman}"
PUSH_IMAGES=false
NO_CACHE=""
BUILD_PARALLEL=true
SERVICE="all"

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$DEPLOY_DIR")"

# Image definitions
readonly PHP_CONTAINERFILE="${DEPLOY_DIR}/containerfiles/Containerfile.php"
readonly NGINX_CONTAINERFILE="${DEPLOY_DIR}/containerfiles/Containerfile.nginx"
readonly PHP_BUILD_CONTEXT="${PROJECT_ROOT}"
readonly NGINX_BUILD_CONTEXT="${DEPLOY_DIR}/containerfiles"

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

# Validate build engine
validate_build_engine() {
    if ! command -v "$BUILD_ENGINE" &> /dev/null; then
        error "Build engine '$BUILD_ENGINE' not found. Please install $BUILD_ENGINE or set BUILD_ENGINE environment variable."
    fi
    info "Using build engine: $BUILD_ENGINE"
}

# Validate Containerfiles exist
validate_containerfiles() {
    if [[ "$SERVICE" == "php" ]] || [[ "$SERVICE" == "all" ]]; then
        if [[ ! -f "$PHP_CONTAINERFILE" ]]; then
            error "PHP Containerfile not found: $PHP_CONTAINERFILE"
        fi
    fi

    if [[ "$SERVICE" == "nginx" ]] || [[ "$SERVICE" == "all" ]]; then
        if [[ ! -f "$NGINX_CONTAINERFILE" ]]; then
            error "Nginx Containerfile not found: $NGINX_CONTAINERFILE"
        fi
    fi
}

# Get full image name with registry prefix
get_image_name() {
    local service="$1"
    local image_base="${PROJECT_NAME}-${service}"

    if [[ -n "$CONTAINER_REGISTRY" ]]; then
        echo "${CONTAINER_REGISTRY}/${image_base}:${IMAGE_TAG}"
    else
        echo "${image_base}:${IMAGE_TAG}"
    fi
}

# Build PHP-FPM image
build_php() {
    local image_name
    image_name="$(get_image_name "php")"

    section "Building PHP-FPM Image"
    info "Image name: $image_name"
    info "Containerfile: $PHP_CONTAINERFILE"
    info "Build context: $PHP_BUILD_CONTEXT"

    # shellcheck disable=SC2086
    "$BUILD_ENGINE" build \
        --file "$PHP_CONTAINERFILE" \
        --tag "$image_name" \
        --target production \
        $NO_CACHE \
        "$PHP_BUILD_CONTEXT"

    success "PHP-FPM image built successfully: $image_name"
}

# Build Nginx image
build_nginx() {
    local image_name
    image_name="$(get_image_name "nginx")"

    section "Building Nginx Image"
    info "Image name: $image_name"
    info "Containerfile: $NGINX_CONTAINERFILE"
    info "Build context: $NGINX_BUILD_CONTEXT"

    # shellcheck disable=SC2086
    "$BUILD_ENGINE" build \
        --file "$NGINX_CONTAINERFILE" \
        --tag "$image_name" \
        $NO_CACHE \
        "$NGINX_BUILD_CONTEXT"

    success "Nginx image built successfully: $image_name"
}

# Push image to registry
push_image() {
    local image_name="$1"

    if [[ -z "$CONTAINER_REGISTRY" ]]; then
        warn "No registry specified. Skipping push for $image_name"
        return 0
    fi

    info "Pushing image to registry: $image_name"
    "$BUILD_ENGINE" push "$image_name"
    success "Image pushed successfully: $image_name"
}

# Build all images sequentially
build_sequential() {
    if [[ "$SERVICE" == "php" ]] || [[ "$SERVICE" == "all" ]]; then
        build_php
        if [[ "$PUSH_IMAGES" == true ]]; then
            push_image "$(get_image_name "php")"
        fi
    fi

    if [[ "$SERVICE" == "nginx" ]] || [[ "$SERVICE" == "all" ]]; then
        build_nginx
        if [[ "$PUSH_IMAGES" == true ]]; then
            push_image "$(get_image_name "nginx")"
        fi
    fi
}

# Build all images in parallel (background jobs)
build_parallel() {
    local pids=()
    local failed=0

    if [[ "$SERVICE" == "php" ]] || [[ "$SERVICE" == "all" ]]; then
        build_php &
        pids+=($!)
    fi

    if [[ "$SERVICE" == "nginx" ]] || [[ "$SERVICE" == "all" ]]; then
        build_nginx &
        pids+=($!)
    fi

    # Wait for all background jobs
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=1
        fi
    done

    if [[ $failed -eq 1 ]]; then
        error "One or more image builds failed"
    fi

    # Push images after successful builds
    if [[ "$PUSH_IMAGES" == true ]]; then
        section "Pushing Images to Registry"
        if [[ "$SERVICE" == "php" ]] || [[ "$SERVICE" == "all" ]]; then
            push_image "$(get_image_name "php")"
        fi
        if [[ "$SERVICE" == "nginx" ]] || [[ "$SERVICE" == "all" ]]; then
            push_image "$(get_image_name "nginx")"
        fi
    fi
}

# Main build orchestration
build_images() {
    if [[ "$BUILD_PARALLEL" == true ]] && [[ "$SERVICE" == "all" ]]; then
        info "Building images in parallel..."
        build_parallel
    else
        info "Building images sequentially..."
        build_sequential
    fi
}

# Print build summary
print_summary() {
    section "Build Summary"
    echo "Project:         $PROJECT_NAME"
    echo "Version:         $IMAGE_TAG"
    echo "Registry:        ${CONTAINER_REGISTRY:-<none>}"
    echo "Build Engine:    $BUILD_ENGINE"
    echo "Service:         $SERVICE"
    echo "Cache:           $([ -n "$NO_CACHE" ] && echo "disabled" || echo "enabled")"
    echo "Push:            $([ "$PUSH_IMAGES" == true ] && echo "yes" || echo "no")"
    echo ""

    if [[ "$SERVICE" == "php" ]] || [[ "$SERVICE" == "all" ]]; then
        echo "PHP Image:       $(get_image_name "php")"
    fi
    if [[ "$SERVICE" == "nginx" ]] || [[ "$SERVICE" == "all" ]]; then
        echo "Nginx Image:     $(get_image_name "nginx")"
    fi
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
        -v|--version)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -r|--registry)
            CONTAINER_REGISTRY="$2"
            shift 2
            ;;
        -p|--push)
            PUSH_IMAGES=true
            shift
            ;;
        -n|--no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --no-parallel)
            BUILD_PARALLEL=false
            shift
            ;;
        php|nginx|all)
            SERVICE="$1"
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
    section "PECE Container Image Build"

    # Validation
    validate_build_engine
    validate_containerfiles

    # Show configuration
    print_summary

    # Build images
    build_images

    # Final success message
    section "Build Completed Successfully"
    success "All images built successfully!"

    if [[ "$PUSH_IMAGES" == false ]] && [[ -n "$CONTAINER_REGISTRY" ]]; then
        info "Tip: Use --push flag to push images to registry"
    fi

    info "To verify images, run:"
    echo "  $BUILD_ENGINE images | grep $PROJECT_NAME"
}

# Run main function
main
