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
REPOS_DIR="$SCRIPT_DIR/../implementations"

# Server implementations
SERVERS=("go" "py" "rb" "rs" "ts")
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

# Function to check if directory exists
dir_exists() {
    [ -d "$1" ]
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

# Function to start server using make
start_server() {
    local server=$1
    local server_dir="$REPOS_DIR/better-auth-$server"

    if ! dir_exists "$server_dir"; then
        print_warning "Directory $server_dir does not exist - skipping"
        return 1
    fi

    print_status "Starting $server server from $server_dir"

    cd "$server_dir"
    make server > /tmp/better-auth-${server}.log 2>&1 &
    local pid=$!
    echo $pid > /tmp/better-auth-${server}.pid

    if wait_for_server; then
        print_success "$server server started (PID: $pid)"
        return 0
    else
        print_error "$server server failed to start"
        cat /tmp/better-auth-${server}.log
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

# Function to run client tests using make
run_client_tests() {
    local client=$1
    local client_dir="$REPOS_DIR/better-auth-$client"

    if ! dir_exists "$client_dir"; then
        print_warning "Directory $client_dir does not exist - skipping"
        return 2  # Return 2 for skipped
    fi

    # Platform-specific checks
    if [ "$client" = "swift" ] && ! command -v swift &> /dev/null; then
        print_warning "Swift not available - skipping better-auth-$client"
        return 2  # Return 2 for skipped
    fi

    if [ "$client" = "kt" ] && [ -z "$JAVA_HOME" ]; then
        print_warning "JAVA_HOME not set - skipping better-auth-$client"
        return 2  # Return 2 for skipped
    fi

    print_status "Running $client integration tests from $client_dir"

    cd "$client_dir"
    if make test-integration; then
        print_success "$client tests passed"
        return 0
    else
        print_error "$client tests failed"
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

        local output
        output=$(run_client_tests "$client" 2>&1)
        local status=$?
        echo "$output" >&2

        if [ $status -eq 0 ]; then
            results+=("${client}:PASS")
            client_results+=("${GREEN}✓${NC} $client")
        elif [ $status -eq 2 ]; then
            results+=("${client}:SKIP")
            client_results+=("${YELLOW}−${NC} $client")
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
    local total_skipped=0
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
        if ! start_server "$server"; then
            print_error "Failed to start $server server, skipping tests"
            for client in "${CLIENTS[@]}"; do
                results_matrix+=("${server}:${client}:SKIP")
                total_skipped=$((total_skipped + 1))
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
            elif [ "$status" = "SKIP" ]; then
                total_skipped=$((total_skipped + 1))
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

    local total_tests=$((total_passed + total_failed + total_skipped))

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
