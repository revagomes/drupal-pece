#!/bin/bash
# Kubernetes Manifest Validation Wrapper
# Ensures PyYAML is available and runs the validation script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default directory to validate
MANIFESTS_DIR="${1:-$PROJECT_ROOT/deploy/kubernetes}"

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is required but not found${NC}"
    exit 1
fi

# Check if PyYAML is installed
if ! python3 -c "import yaml" 2>/dev/null; then
    echo -e "${YELLOW}PyYAML not found. Installing...${NC}"
    pip3 install --user PyYAML || {
        echo -e "${RED}Failed to install PyYAML${NC}"
        exit 1
    }
    echo -e "${GREEN}PyYAML installed successfully${NC}"
fi

# Get user site-packages directory and add to PYTHONPATH
USER_SITE=$(python3 -c "import site; print(site.USER_SITE)" 2>/dev/null || echo "")
if [ -n "$USER_SITE" ]; then
    export PYTHONPATH="$USER_SITE:$PYTHONPATH"
fi

# Run the validation script
python3 "$SCRIPT_DIR/validate-k8s-manifests.py" "$MANIFESTS_DIR"
