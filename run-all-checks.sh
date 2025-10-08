#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Main execution
main() {
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║           Better Auth - Running All Checks                         ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    local failed=0

    # 1. Format check
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║  Step 1/4: Format Check                                            ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    if "$SCRIPT_DIR/run-format-check.sh"; then
        print_success "Format check completed"
    else
        print_error "Format check failed"
        failed=1
    fi

    # 2. Lint
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║  Step 2/4: Lint                                                     ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    if "$SCRIPT_DIR/run-lint.sh"; then
        print_success "Lint completed"
    else
        print_error "Lint failed"
        failed=1
    fi

    # 3. Unit tests
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║  Step 3/4: Unit Tests                                               ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    if "$SCRIPT_DIR/run-unit-tests.sh"; then
        print_success "Unit tests completed"
    else
        print_error "Unit tests failed"
        failed=1
    fi

    # 4. Integration tests
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║  Step 4/4: Integration Tests                                        ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    if "$SCRIPT_DIR/run-integration-tests.sh"; then
        print_success "Integration tests completed"
    else
        print_error "Integration tests failed"
        failed=1
    fi

    # Final summary
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                         Final Summary                               ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    if [ $failed -eq 0 ]; then
        print_success "All checks passed!"
        echo ""
        exit 0
    else
        print_error "Some checks failed - see above for details"
        echo ""
        exit 1
    fi
}

main "$@"
