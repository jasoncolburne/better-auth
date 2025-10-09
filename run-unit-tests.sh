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
REPOS_DIR="$(dirname "$SCRIPT_DIR")"

# Repositories with unit tests
REPOS=("go" "py" "rb" "rs" "ts")

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

# Function to run Go unit tests
run_go_unit_tests() {
    local repo_dir="$REPOS_DIR/better-auth-go"
    print_status "Running Go unit tests from $repo_dir"

    cd "$repo_dir"
    if go test ./...; then
        print_success "Go unit tests passed"
        return 0
    else
        print_error "Go unit tests failed"
        return 1
    fi
}

# Function to run Python unit tests
run_py_unit_tests() {
    local repo_dir="$REPOS_DIR/better-auth-py"
    print_status "Running Python unit tests from $repo_dir"

    cd "$repo_dir"
    if [ -d "venv" ]; then
        source venv/bin/activate
    fi

    if pytest tests/test_api.py tests/test_token.py; then
        print_success "Python unit tests passed"
        return 0
    else
        print_error "Python unit tests failed"
        return 1
    fi
}

# Function to run Ruby unit tests
run_rb_unit_tests() {
    local repo_dir="$REPOS_DIR/better-auth-rb"
    print_status "Running Ruby unit tests from $repo_dir"

    cd "$repo_dir"
    if bundle exec rspec; then
        print_success "Ruby unit tests passed"
        return 0
    else
        print_error "Ruby unit tests failed"
        return 1
    fi
}

# Function to run Rust unit tests
run_rs_unit_tests() {
    local repo_dir="$REPOS_DIR/better-auth-rs"
    print_status "Running Rust unit tests from $repo_dir"

    cd "$repo_dir"
    if cargo test --test api_test --test token_test; then
        print_success "Rust unit tests passed"
        return 0
    else
        print_error "Rust unit tests failed"
        return 1
    fi
}

# Function to run TypeScript unit tests
run_ts_unit_tests() {
    local repo_dir="$REPOS_DIR/better-auth-ts"
    print_status "Running TypeScript unit tests from $repo_dir"

    cd "$repo_dir"
    if npm test; then
        print_success "TypeScript unit tests passed"
        return 0
    else
        print_error "TypeScript unit tests failed"
        return 1
    fi
}

# Main execution
main() {
    local total_passed=0
    local total_failed=0
    local results=()

    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              Better Auth Unit Test Suite                           ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    for repo in "${REPOS[@]}"; do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if run_${repo}_unit_tests; then
            results+=("${GREEN}✓${NC} better-auth-$repo")
            total_passed=$((total_passed + 1))
        else
            results+=("${RED}✗${NC} better-auth-$repo")
            total_failed=$((total_failed + 1))
        fi
    done

    # Print summary
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                        Unit Test Results                           ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    for result in "${results[@]}"; do
        echo -e "  $result"
    done

    local total_tests=$((total_passed + total_failed))
    echo ""
    echo "════════════════════════════════════════════════════════════════════════"
    echo "Summary: $total_passed passed, $total_failed failed out of $total_tests repositories"
    echo "════════════════════════════════════════════════════════════════════════"

    if [ $total_failed -gt 0 ]; then
        exit 1
    fi
}

main "$@"
