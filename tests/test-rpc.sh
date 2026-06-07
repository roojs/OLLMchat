#!/bin/bash
# Tranche 0 — ollmfilesd RPC harness smoke (shell + socat + jq).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test-common.sh"
source "$SCRIPT_DIR/test-rpc-common.sh"

BUILD_DIR="${1:-$PROJECT_ROOT/build}"
OLLMFILESD="$BUILD_DIR/ollmfilesd/ollmfilesd"
TEST_DIR="$BUILD_DIR/test-rpc-$$"
RPC_SOCKET="$TEST_DIR/ollmfilesd.sock"
PID_FILE="$TEST_DIR/ollmfilesd.pid"

cleanup() {
    rpc_shutdown || true
    if [ "${TESTS_FAILED:-0}" -eq 0 ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    elif [ -d "$TEST_DIR" ]; then
        echo -e "${YELLOW}Test failed — leaving $TEST_DIR for debugging${NC}"
    fi
}
trap cleanup EXIT

require_rpc_tools

if [ ! -x "$OLLMFILESD" ]; then
    echo -e "${RED}Error: ollmfilesd not found at $OLLMFILESD${NC}" >&2
    exit 1
fi

mkdir -p "$TEST_DIR"

# T0.1 — spawn with isolated data_dir; socket + pid
OLLMFILES_IS_TEST=1 \
    "$OLLMFILESD" --data-dir="$TEST_DIR" >/dev/null 2>&1 &

if ! wait_for_socket; then
    test_fail "T0.1 spawn daemon (socket accepts)"
    exit 1
fi

if [ ! -f "$PID_FILE" ]; then
    test_fail "T0.1 pid file written"
    exit 1
fi
test_pass "T0.1 spawn daemon (socket + pid)"

# T0.2 — Daemon.hello
resp=$(rpc_call 1 "Daemon.hello" '{"protocol":1,"client":"test-rpc"}')
jq_ok "T0.2 Daemon.hello (no error)" "$resp" '.error == null'
jq_ok "T0.2 Daemon.hello (server)" "$resp" '.result.server == "ollmfilesd"'
jq_ok "T0.2 Daemon.hello (ready)" "$resp" '.result.ready == true'

# T0.3 — second request on a new connection; id matches
resp=$(rpc_call 42 "Daemon.hello" '{"protocol":1,"client":"test-rpc"}')
jq_ok "T0.3 response id matches" "$resp" '.id == 42'

# T0.4 — unknown method (deferred: dispatch logs critical, no wire error yet)

print_test_summary
exit "$([ "${TESTS_FAILED:-0}" -eq 0 ] && echo 0 || echo 1)"
