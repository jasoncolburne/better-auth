#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Main execution
print_status "Pulling latest changes from all submodules..."

if git submodule update --remote --merge; then
    print_success "All submodules updated successfully"
else
    print_error "Submodules not initialized."
    echo ""
    echo "Did you clone with --recurse-submodules?"
    echo "If not, run: git submodule update --init --recursive"
    echo ""
    exit 1
fi
