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
REPOS_DIR="$SCRIPT_DIR/../implementations"

# All implementation repositories
REPOS=("dart" "go" "kt" "py" "rb" "rs" "swift" "ts")

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if directory exists
dir_exists() {
    [ -d "$1" ]
}

# Function to run setup using make
run_setup() {
    local repo=$1
    local repo_dir="$REPOS_DIR/better-auth-$repo"

    if ! dir_exists "$repo_dir"; then
        print_warning "Directory $repo_dir does not exist - skipping"
        return 0
    fi

    print_status "Setting up better-auth-$repo from $repo_dir"

    # Platform-specific checks
    if [ "$repo" = "swift" ] && ! command_exists swift; then
        print_warning "Swift not installed - skipping better-auth-swift"
        return 0
    fi

    if [ "$repo" = "kt" ] && [ -z "$JAVA_HOME" ]; then
        print_warning "JAVA_HOME not set - skipping better-auth-kt"
        return 0
    fi

    if [ "$repo" = "dart" ] && ! command_exists dart; then
        print_warning "Dart not installed - skipping better-auth-dart"
        return 0
    fi

    cd "$repo_dir"
    if make setup; then
        print_success "Setup completed for better-auth-$repo"
        return 0
    else
        print_error "Setup failed for better-auth-$repo"
        return 1
    fi
}

# Main execution
main() {
    local total_passed=0
    local total_failed=0
    local total_skipped=0
    local results=()

    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              Better Auth Setup Script                              ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    for repo in "${REPOS[@]}"; do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        local output
        output=$(run_setup "$repo" 2>&1)
        local status=$?

        if [ $status -eq 0 ]; then
            if echo "$output" | grep -q "WARNING"; then
                results+=("${YELLOW}−${NC} better-auth-$repo")
                total_skipped=$((total_skipped + 1))
            else
                results+=("${GREEN}✓${NC} better-auth-$repo")
                total_passed=$((total_passed + 1))
            fi
            echo "$output"
        else
            results+=("${RED}✗${NC} better-auth-$repo")
            total_failed=$((total_failed + 1))
            echo "$output"
        fi
    done

    # Print summary
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                          Setup Results                             ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    for result in "${results[@]}"; do
        echo -e "  $result"
    done

    local total_repos=${#REPOS[@]}
    echo ""
    echo "════════════════════════════════════════════════════════════════════════"
    echo "Summary: $total_passed completed, $total_failed failed, $total_skipped skipped out of $total_repos repositories"
    echo "════════════════════════════════════════════════════════════════════════"

    if [ $total_failed -gt 0 ]; then
        exit 1
    fi

    # Install git hooks
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    "$SCRIPT_DIR/install-hooks.sh"
}

main "$@"
