#!/bin/bash
# Tranche 0 — ollmfilesd RPC harness (interactive + rpc-script file + jq).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test-common.sh"
source "$SCRIPT_DIR/test-rpc-common.sh"

BUILD_DIR="${1:-$PROJECT_ROOT/build}"
OLLMFILESD="$BUILD_DIR/ollmfilesd/ollmfilesd"
TEST_DIR="$BUILD_DIR/test-rpc-$$"
RPC_SCRIPT="$SCRIPT_DIR/rpc/t0.script"
RPC_OUT="$TEST_DIR/out.ndjson"
RPC_ERR="$TEST_DIR/ollmfilesd.stderr"

cleanup() {
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

if [ ! -f "$RPC_SCRIPT" ]; then
    echo -e "${RED}Error: RPC script not found at $RPC_SCRIPT${NC}" >&2
    exit 1
fi

mkdir -p "$TEST_DIR"
run_rpc_script "$RPC_SCRIPT" "$RPC_OUT" "$RPC_ERR"

# line 1 — ready notification (Daemon.ready)
ready=$(rpc_line 1 "$RPC_OUT")
jq_line_ok "T0.1 ready notification" "$ready" \
    '.method == "Daemon.ready" and .["object-type"] == "Daemon"'

# line 2 — Daemon.hello response
resp=$(rpc_line 2 "$RPC_OUT")
jq_line_ok "T0.2 Daemon.hello (no error)" "$resp" '.error == null'
jq_line_ok "T0.2 Daemon.hello (server)" "$resp" '.result[0].server == "ollmfilesd"'
jq_line_ok "T0.2 Daemon.hello (ready)" "$resp" '(.result[0].ready // true) == true'

# line 3 — second request; id matches
resp=$(rpc_line 3 "$RPC_OUT")
jq_line_ok "T0.3 response id matches" "$resp" '.id == 42'

print_test_summary
exit "$([ "${TESTS_FAILED:-0}" -eq 0 ] && echo 0 || echo 1)"
