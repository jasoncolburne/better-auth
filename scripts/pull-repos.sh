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

# All submodules
SUBMODULES=("better-auth-ts" "better-auth-py" "better-auth-go" "better-auth-rb" "better-auth-rs" "better-auth-swift" "better-auth-dart" "better-auth-kt")

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

# Counters
updated=0
skipped=0
failed=0

print_status "Pulling latest changes from all submodules..."
echo ""

for submodule in "${SUBMODULES[@]}"; do
    submodule_path="$REPOS_DIR/$submodule"

    # Check if submodule directory exists
    if [ ! -d "$submodule_path" ]; then
        print_error "$submodule: directory not found"
        echo "Did you clone with --recurse-submodules?"
        echo "If not, run: git submodule update --init --recursive"
        failed=$((failed + 1))
        continue
    fi

    cd "$submodule_path"

    # Check current branch
    current_branch=$(git branch --show-current)

    if [ -z "$current_branch" ]; then
        # Detached HEAD state
        print_warning "$submodule: detached HEAD, skipping"
        skipped=$((skipped + 1))
    elif [ "$current_branch" != "main" ]; then
        # On a different branch
        print_warning "$submodule: on branch '$current_branch', skipping"
        skipped=$((skipped + 1))
    else
        # On main branch, pull updates
        print_status "$submodule: on main, pulling..."
        if git pull origin main; then
            print_success "$submodule: updated"
            updated=$((updated + 1))
        else
            print_error "$submodule: failed to pull"
            failed=$((failed + 1))
        fi
    fi

    cd - > /dev/null
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary: $updated updated, $skipped skipped, $failed failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $failed -gt 0 ]; then
    exit 1
fi
