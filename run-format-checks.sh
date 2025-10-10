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

# Repositories (kt excluded - ktlintCheck in lint script handles both)
REPOS=("dart" "go" "py" "rs" "swift" "ts")

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

# Function to run Dart format check
run_dart_format() {
    local repo_dir="$REPOS_DIR/better-auth-dart"
    print_status "Running Dart format check from $repo_dir"

    cd "$repo_dir"
    dart pub get > /dev/null 2>&1
    if dart format -onone --set-exit-if-changed .; then
        print_success "Dart format check passed"
        return 0
    else
        print_error "Dart format check failed"
        return 1
    fi
}

# Function to run Go format check
run_go_format() {
    local repo_dir="$REPOS_DIR/better-auth-go"
    print_status "Running Go format check from $repo_dir"

    cd "$repo_dir"
    local output=$(gofmt -e -l .)
    if [ -z "$output" ]; then
        print_success "Go format check passed"
        return 0
    else
        print_error "Go format check failed"
        echo "$output"
        return 1
    fi
}

# Function to run Python format check
run_py_format() {
    local repo_dir="$REPOS_DIR/better-auth-py"
    print_status "Running Python format check from $repo_dir"

    cd "$repo_dir"
    if [ -d "venv" ]; then
        source venv/bin/activate
    fi

    if black --check .; then
        print_success "Python format check passed"
        return 0
    else
        print_error "Python format check failed"
        return 1
    fi
}

# Function to run Rust format check
run_rs_format() {
    local repo_dir="$REPOS_DIR/better-auth-rs"
    print_status "Running Rust format check from $repo_dir"

    cd "$repo_dir"
    if cargo fmt --check; then
        print_success "Rust format check passed"
        return 0
    else
        print_error "Rust format check failed"
        return 1
    fi
}

# Function to run Swift format check
run_swift_format() {
    local repo_dir="$REPOS_DIR/better-auth-swift"
    print_status "Running Swift format check from $repo_dir"

    cd "$repo_dir"
    if ! command -v swiftformat &> /dev/null; then
        print_warning "swiftformat not installed - skipping"
        return 0
    fi

    if swiftformat --lint .; then
        print_success "Swift format check passed"
        return 0
    else
        print_error "Swift format check failed"
        return 1
    fi
}

# Function to run TypeScript format check
run_ts_format() {
    local repo_dir="$REPOS_DIR/better-auth-ts"
    print_status "Running TypeScript format check from $repo_dir"

    cd "$repo_dir"
    if npm run format:check; then
        print_success "TypeScript format check passed"
        return 0
    else
        print_error "TypeScript format check failed"
        return 1
    fi
}

# Main execution
main() {
    local total_passed=0
    local total_failed=0
    local results=()

    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              Better Auth Format Check Suite                        ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    for repo in "${REPOS[@]}"; do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if run_${repo}_format; then
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
    echo "║                      Format Check Results                          ║"
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
