#!/bin/bash
# Tranche 0 — ollmfilesd RPC harness smoke (stdio NDJSON + jq).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test-common.sh"
source "$SCRIPT_DIR/test-rpc-common.sh"

BUILD_DIR="${1:-$PROJECT_ROOT/build}"
OLLMFILESD="$BUILD_DIR/ollmfilesd/ollmfilesd"
TEST_DIR="$BUILD_DIR/test-rpc-$$"

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

# T0.1 — spawn --interactive with isolated data_dir; probe Daemon.hello on stdio
rpc_start

if ! wait_for_rpc_ready; then
    test_fail "T0.1 spawn daemon (stdio hello)"
    exit 1
fi
test_pass "T0.1 spawn daemon (stdio hello)"

# T0.2 — Daemon.hello
rpc_call 1 "Daemon.hello" '{"protocol":1,"client":"test-rpc"}'
jq_ok "T0.2 Daemon.hello (no error)" "$RPC_LAST_RESPONSE" '.error == null'
jq_ok "T0.2 Daemon.hello (server)" "$RPC_LAST_RESPONSE" '.result.server == "ollmfilesd"'
jq_ok "T0.2 Daemon.hello (ready)" "$RPC_LAST_RESPONSE" '(.result.ready // true) == true'

# T0.3 — second request on same stdio session; id matches
rpc_call 42 "Daemon.hello" '{"protocol":1,"client":"test-rpc"}'
jq_ok "T0.3 response id matches" "$RPC_LAST_RESPONSE" '.id == 42'

# T0.4 — unknown method (deferred: dispatch logs critical, no wire error yet)

print_test_summary
exit "$([ "${TESTS_FAILED:-0}" -eq 0 ] && echo 0 || echo 1)"
