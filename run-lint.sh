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

# Repositories
REPOS=("dart" "kt" "py" "rb" "swift" "ts")

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

# Function to run Dart lint
run_dart_lint() {
    local repo_dir="$REPOS_DIR/better-auth-dart"
    print_status "Running Dart lint from $repo_dir"

    cd "$repo_dir"
    dart pub get > /dev/null 2>&1
    if dart analyze; then
        print_success "Dart lint passed"
        return 0
    else
        print_error "Dart lint failed"
        return 1
    fi
}

# Function to run Kotlin lint
run_kt_lint() {
    local repo_dir="$REPOS_DIR/better-auth-kt"
    print_status "Running Kotlin lint from $repo_dir"

    cd "$repo_dir"
    if env JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew ktlintCheck; then
        print_success "Kotlin lint passed"
        return 0
    else
        print_error "Kotlin lint failed"
        return 1
    fi
}

# Function to run Python lint
run_py_lint() {
    local repo_dir="$REPOS_DIR/better-auth-py"
    print_status "Running Python lint from $repo_dir"

    cd "$repo_dir"
    if [ -d "venv" ]; then
        source venv/bin/activate
    fi

    if ruff check .; then
        print_success "Python lint passed"
        return 0
    else
        print_error "Python lint failed"
        return 1
    fi
}

# Function to run Ruby lint
run_rb_lint() {
    local repo_dir="$REPOS_DIR/better-auth-rb"
    print_status "Running Ruby lint from $repo_dir"

    cd "$repo_dir"
    if bundle exec rubocop; then
        print_success "Ruby lint passed"
        return 0
    else
        print_error "Ruby lint failed"
        return 1
    fi
}

# Function to run Swift lint
run_swift_lint() {
    local repo_dir="$REPOS_DIR/better-auth-swift"
    print_status "Running Swift lint from $repo_dir"

    cd "$repo_dir"
    if ! command -v swiftlint &> /dev/null; then
        print_warning "swiftlint not installed - skipping"
        return 0
    fi

    if swiftlint lint --strict; then
        print_success "Swift lint passed"
        return 0
    else
        print_error "Swift lint failed"
        return 1
    fi
}

# Function to run TypeScript lint
run_ts_lint() {
    local repo_dir="$REPOS_DIR/better-auth-ts"
    print_status "Running TypeScript lint from $repo_dir"

    cd "$repo_dir"
    if npm run lint; then
        print_success "TypeScript lint passed"
        return 0
    else
        print_error "TypeScript lint failed"
        return 1
    fi
}

# Main execution
main() {
    local total_passed=0
    local total_failed=0
    local results=()

    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                 Better Auth Lint Suite                             ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    for repo in "${REPOS[@]}"; do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if run_${repo}_lint; then
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
    echo "║                          Lint Results                               ║"
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
