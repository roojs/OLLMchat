#!/bin/bash
# TCP listener + OLLMrpc.Client smoke test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test-common.sh"

BUILD_DIR="${1:-$PROJECT_ROOT/build}"
OLLMFILESD="$BUILD_DIR/ollmfilesd/ollmfilesd"
RPC_CLIENT="$BUILD_DIR/tests/test-rpc-client-tcp"
TEST_DIR="$BUILD_DIR/test-rpc-tcp-$$"
TCP_PORT="${OLLMFILES_TEST_TCP_PORT:-4141}"
RPC_OUT="$TEST_DIR/out.ndjson"
RPC_ERR="$TEST_DIR/ollmfilesd.stderr"
DAEMON_PID=0

cleanup() {
    if [ "$DAEMON_PID" -ne 0 ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
    if [ "${TESTS_FAILED:-0}" -eq 0 ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    elif [ -d "$TEST_DIR" ]; then
        echo -e "${YELLOW}Test failed — leaving $TEST_DIR for debugging${NC}"
    fi
}
trap cleanup EXIT

if [ ! -x "$OLLMFILESD" ]; then
    echo -e "${RED}Error: ollmfilesd not found at $OLLMFILESD${NC}" >&2
    exit 1
fi

if [ ! -x "$RPC_CLIENT" ]; then
    echo -e "${RED}Error: TCP RPC client not found at $RPC_CLIENT${NC}" >&2
    exit 1
fi

wait_for_tcp() {
    local attempt
    for attempt in $(seq 1 50); do
        if (: >"/dev/tcp/127.0.0.1/$TCP_PORT") 2>/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

mkdir -p "$TEST_DIR"
OLLMFILES_IS_TEST=1 "$OLLMFILESD" \
    --tcp \
    --tcp-host=127.0.0.1 \
    --tcp-port="$TCP_PORT" \
    --data-dir="$TEST_DIR" \
    >"$RPC_OUT" 2>"$RPC_ERR" &
DAEMON_PID=$!

if wait_for_tcp; then
    test_pass "TCP listener accepts connections"
else
    test_fail "TCP listener accepts connections"
fi

if "$RPC_CLIENT" "tcp://127.0.0.1:$TCP_PORT"; then
    test_pass "OLLMrpc.Client connects over TCP and shuts down daemon"
else
    test_fail "OLLMrpc.Client connects over TCP and shuts down daemon"
fi

if wait "$DAEMON_PID"; then
    test_pass "TCP daemon exits after Daemon.shutdown"
    DAEMON_PID=0
else
    test_fail "TCP daemon exits after Daemon.shutdown"
fi

print_test_summary
exit "$([ "${TESTS_FAILED:-0}" -eq 0 ] && echo 0 || echo 1)"
