#!/bin/bash
# Stacked modified review — headless daemon (Tier A).
# Accept head chunk (FileHistory.decide); expect full path approved in DB.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test-common.sh"
source "$SCRIPT_DIR/test-rpc-common.sh"

BUILD_DIR="${1:-$PROJECT_ROOT/build}"
OLLMFILESD="$BUILD_DIR/ollmfilesd/ollmfilesd"
TEST_DIR="$BUILD_DIR/test-rpc-stacked-review-$$"
RPC_DB="$TEST_DIR/files.sqlite"
STACKED_PATH=""

cleanup() {
    if [ "${TESTS_FAILED:-0}" -eq 0 ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    elif [ -d "$TEST_DIR" ]; then
        echo -e "${YELLOW}Left $TEST_DIR for Tier C (STACKED_REVIEW_DATA_DIR)${NC}"
    fi
}
trap cleanup EXIT

require_rpc_tools

if [ ! -x "$OLLMFILESD" ]; then
    echo -e "${RED}Error: ollmfilesd not found at $OLLMFILESD${NC}" >&2
    exit 1
fi

mkdir -p "$TEST_DIR"
setup_rpc_fixture minimal-project
STACKED_PATH="$RPC_PROJECT_PATH/stacked-review.txt"

prepare_stacked_script() {
    local template="$1"
    local dest="$2"
    prepare_rpc_script "$template" "$dest"
    sed -i "s|__STACKED_PATH__|${STACKED_PATH}|g" "$dest"
}

echo "=== stacked-review Tier A (headless) ==="
SCRIPT="$TEST_DIR/stacked-review-full.script"
OUT="$TEST_DIR/stacked-review-full.out.ndjson"
ERR="$TEST_DIR/stacked-review-full.stderr"
prepare_stacked_script "$SCRIPT_DIR/rpc/stacked-review-full.script.in" "$SCRIPT"
run_rpc_script "$SCRIPT" "$OUT" "$ERR"
RPC_DB="$TEST_DIR/files.sqlite"

sqlite_count_ok "fixture: file_history rows persisted" "$RPC_DB" \
    "SELECT COUNT(*) FROM file_history WHERE path='$STACKED_PATH'" "4"

sqlite_count_ok "after decide: no pending history for path" "$RPC_DB" \
    "SELECT COUNT(*) FROM file_history WHERE path='$STACKED_PATH' AND reviewed=0" "0"

sqlite_count_ok "after decide: file approved in DB" "$RPC_DB" \
    "SELECT is_need_approval FROM filebase WHERE path='$STACKED_PATH' ORDER BY id DESC LIMIT 1" "0"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}Tier A: passed${NC}"
else
    echo -e "${RED}Tier A: failed (bug: head decide leaves stack pending)${NC}"
    exit 1
fi