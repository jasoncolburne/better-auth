#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default port
PORT=8080

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_DIR="$(dirname "$SCRIPT_DIR")"

# Server implementations
SERVERS=("go" "py" "rb" "rs")
# Client implementations
CLIENTS=("dart" "kt" "py" "rs" "swift" "ts")

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

# Function to check if a port is in use
is_port_in_use() {
    lsof -i :$PORT > /dev/null 2>&1
}

# Function to kill process on port
kill_port() {
    if is_port_in_use; then
        print_warning "Killing existing process on port $PORT"
        lsof -ti :$PORT | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
}

# Function to wait for server to be ready
wait_for_server() {
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -s -X POST http://localhost:$PORT/key/response > /dev/null 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    return 1
}

# Function to start Go server
start_go_server() {
    local server_dir="$REPOS_DIR/better-auth-go"
    print_status "Starting Go server from $server_dir"

    cd "$server_dir"
    go run examples/server.go > /tmp/better-auth-go.log 2>&1 &
    local pid=$!
    echo $pid > /tmp/better-auth-go.pid

    if wait_for_server; then
        print_success "Go server started (PID: $pid)"
        return 0
    else
        print_error "Go server failed to start"
        cat /tmp/better-auth-go.log
        return 1
    fi
}

# Function to start Python server
start_py_server() {
    local server_dir="$REPOS_DIR/better-auth-py"
    print_status "Starting Python server from $server_dir"

    cd "$server_dir"
    # Activate venv if it exists
    if [ -d "venv" ]; then
        source venv/bin/activate
    fi

    python -m examples.server > /tmp/better-auth-py-server.log 2>&1 &
    local pid=$!
    echo $pid > /tmp/better-auth-py-server.pid

    if wait_for_server; then
        print_success "Python server started (PID: $pid)"
        return 0
    else
        print_error "Python server failed to start"
        cat /tmp/better-auth-py-server.log
        return 1
    fi
}

# Function to start Ruby server
start_rb_server() {
    local server_dir="$REPOS_DIR/better-auth-rb"
    print_status "Starting Ruby server from $server_dir"

    cd "$server_dir"
    bundle exec ruby examples/server.rb > /tmp/better-auth-rb.log 2>&1 &
    local pid=$!
    echo $pid > /tmp/better-auth-rb.pid

    if wait_for_server; then
        print_success "Ruby server started (PID: $pid)"
        return 0
    else
        print_error "Ruby server failed to start"
        cat /tmp/better-auth-rb.log
        return 1
    fi
}

# Function to start Rust server
start_rs_server() {
    local server_dir="$REPOS_DIR/better-auth-rs"
    print_status "Starting Rust server from $server_dir"

    cd "$server_dir"
    cargo run --example server > /tmp/better-auth-rs.log 2>&1 &
    local pid=$!
    echo $pid > /tmp/better-auth-rs.pid

    if wait_for_server; then
        print_success "Rust server started (PID: $pid)"
        return 0
    else
        print_error "Rust server failed to start"
        cat /tmp/better-auth-rs.log
        return 1
    fi
}

# Function to stop server
stop_server() {
    local server=$1
    local pid_file="/tmp/better-auth-${server}.pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 $pid 2>/dev/null; then
            print_status "Stopping $server server (PID: $pid)"
            kill $pid 2>/dev/null || true
            sleep 1
            kill -9 $pid 2>/dev/null || true
        fi
        rm -f "$pid_file"
    fi

    # Also kill any process on the port as fallback
    kill_port
}

# Function to run Dart tests
run_dart_tests() {
    local client_dir="$REPOS_DIR/better-auth-dart"
    print_status "Running Dart integration tests from $client_dir"

    cd "$client_dir"
    if dart test test/integration_test.dart; then
        print_success "Dart tests passed"
        return 0
    else
        print_error "Dart tests failed"
        return 1
    fi
}

# Function to run Kotlin tests
run_kt_tests() {
    local client_dir="$REPOS_DIR/better-auth-kt"
    print_status "Running Kotlin integration tests from $client_dir"

    cd "$client_dir"
    if env JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew test --tests "com.betterauth.IntegrationTest" --rerun-tasks; then
        print_success "Kotlin tests passed"
        return 0
    else
        print_error "Kotlin tests failed"
        return 1
    fi
}

# Function to run Python tests
run_py_tests() {
    local client_dir="$REPOS_DIR/better-auth-py"
    print_status "Running Python integration tests from $client_dir"

    cd "$client_dir"
    if (source venv/bin/activate && pytest tests/integration/test_integration.py); then
        print_success "Python tests passed"
        return 0
    else
        print_error "Python tests failed"
        return 1
    fi
}

# Function to run Rust tests
run_rs_tests() {
    local client_dir="$REPOS_DIR/better-auth-rs"
    print_status "Running Rust integration tests from $client_dir"

    cd "$client_dir"
    if cargo test --test integration_test; then
        print_success "Rust tests passed"
        return 0
    else
        print_error "Rust tests failed"
        return 1
    fi
}

# Function to run Swift tests
run_swift_tests() {
    local client_dir="$REPOS_DIR/better-auth-swift"
    print_status "Running Swift integration tests from $client_dir"

    cd "$client_dir"
    if swift test --filter BetterAuthTests.IntegrationTests; then
        print_success "Swift tests passed"
        return 0
    else
        print_error "Swift tests failed"
        return 1
    fi
}

# Function to run TypeScript tests
run_ts_tests() {
    local client_dir="$REPOS_DIR/better-auth-ts"
    print_status "Running TypeScript integration tests from $client_dir"

    cd "$client_dir"
    if npm run test:integration; then
        print_success "TypeScript tests passed"
        return 0
    else
        print_error "TypeScript tests failed"
        return 1
    fi
}

# Function to run all client tests against a server
run_all_client_tests() {
    local results=()
    local client_results=()

    for client in "${CLIENTS[@]}"; do
        echo "" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        print_status "Testing $client client" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

        if run_${client}_tests >&2; then
            results+=("${client}:PASS")
            client_results+=("${GREEN}✓${NC} $client")
        else
            results+=("${client}:FAIL")
            client_results+=("${RED}✗${NC} $client")
        fi
    done

    # Print summary for this server
    echo "" >&2
    echo "Client Results:" >&2
    for result in "${client_results[@]}"; do
        echo -e "  $result" >&2
    done

    # Return combined results (to stdout only)
    echo "${results[@]}"
}

# Main execution
main() {
    local total_passed=0
    local total_failed=0
    local results_matrix=()

    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║         Better Auth Integration Test Suite                         ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Ensure clean start
    kill_port

    for server in "${SERVERS[@]}"; do
        echo ""
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "  Testing with $server server"
        echo "╚════════════════════════════════════════════════════════════════════╝"

        # Start the server
        if ! start_${server}_server; then
            print_error "Failed to start $server server, skipping tests"
            for client in "${CLIENTS[@]}"; do
                results_matrix+=("${server}:${client}:SKIP")
            done
            stop_server "$server"
            continue
        fi

        sleep 2

        # Run all client tests
        local client_results=($(run_all_client_tests))

        # Process results
        for result in "${client_results[@]}"; do
            local client=$(echo "$result" | cut -d: -f1)
            local status=$(echo "$result" | cut -d: -f2)
            results_matrix+=("${server}:${client}:${status}")

            if [ "$status" = "PASS" ]; then
                total_passed=$((total_passed + 1))
            else
                total_failed=$((total_failed + 1))
            fi
        done

        # Stop the server
        stop_server "$server"
        sleep 1
    done

    # Print final summary
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                     Final Test Results Matrix                      ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
    printf "%-15s" "Server/Client"
    for client in "${CLIENTS[@]}"; do
        printf "%-10s" "$client"
    done
    echo ""
    echo "────────────────────────────────────────────────────────────────────────"

    for server in "${SERVERS[@]}"; do
        printf "%-15s" "$server"
        for client in "${CLIENTS[@]}"; do
            local result=""
            for matrix_entry in "${results_matrix[@]}"; do
                local s=$(echo "$matrix_entry" | cut -d: -f1)
                local c=$(echo "$matrix_entry" | cut -d: -f2)
                local status=$(echo "$matrix_entry" | cut -d: -f3)

                if [ "$s" = "$server" ] && [ "$c" = "$client" ]; then
                    if [ "$status" = "PASS" ]; then
                        result="${GREEN}✓${NC}"
                    elif [ "$status" = "FAIL" ]; then
                        result="${RED}✗${NC}"
                    else
                        result="${YELLOW}−${NC}"
                    fi
                    break
                fi
            done
            echo -ne "$result"
            printf "%-9s" ""
        done
        echo ""
    done

    local total_tests=$((total_passed + total_failed))
    local total_skipped=$((${#SERVERS[@]} * ${#CLIENTS[@]} - total_tests))

    echo ""
    echo "════════════════════════════════════════════════════════════════════════"
    echo "Summary: $total_passed passed, $total_failed failed, $total_skipped skipped out of $((${#SERVERS[@]} * ${#CLIENTS[@]})) combinations"
    echo "════════════════════════════════════════════════════════════════════════"

    if [ $total_failed -gt 0 ] || [ $total_passed -eq 0 ]; then
        exit 1
    fi
}

# Cleanup on exit
cleanup() {
    echo ""
    print_status "Cleaning up..."
    for server in "${SERVERS[@]}"; do
        stop_server "$server"
    done
}

trap cleanup EXIT INT TERM

main "$@"
