#!/bin/bash
# Tranche 1 — ProjectManager RPC tests (interactive + rpc-script + jq + sqlite).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test-common.sh"
source "$SCRIPT_DIR/test-rpc-common.sh"

BUILD_DIR="${1:-$PROJECT_ROOT/build}"
OLLMFILESD="$BUILD_DIR/ollmfilesd/ollmfilesd"
TEST_DIR="$BUILD_DIR/test-rpc-t1-$$"
RPC_DB="$TEST_DIR/files.sqlite"

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

run_t1_case() {
    local template="$1"
    local script="$TEST_DIR/$(basename "${template%.in}")"
    local out="$TEST_DIR/$(basename "${template%.in}").out.ndjson"
    local err="$TEST_DIR/$(basename "${template%.in}").stderr"
    if [ ! -f "$template" ]; then
        echo -e "${RED}Error: RPC template not found at $template${NC}" >&2
        exit 1
    fi
    prepare_rpc_script "$template" "$script"
    run_rpc_script "$script" "$out" "$err"
    RPC_LAST_OUT="$out"
    RPC_LAST_ERR="$err"
}

mkdir -p "$TEST_DIR"
setup_rpc_fixture minimal-project

# --- Wire round-trip (single script session) ---
run_t1_case "$SCRIPT_DIR/rpc/t1.script.in"

jq_resp_ok "T1.1 load_projects_from_db (array)" 2 "$RPC_LAST_OUT" \
    '.error == null and ((.result // []) | type) == "array"'
jq_resp_ok "T1.2 create_project (no error)" 3 "$RPC_LAST_OUT" '.error == null'
jq_resp_ok "T1.2 create_project (is_project)" 3 "$RPC_LAST_OUT" \
    '.result[0]["is-project"] == true'
jq_resp_args_ok "T1.2 create_project (path)" 3 "$RPC_LAST_OUT" \
    --arg p "$RPC_PROJECT_PATH" '.result[0].path == $p'
jq_resp_ok "T1.3 load_projects_from_db (count)" 4 "$RPC_LAST_OUT" \
    '.error == null and (.result | length) >= 1'
jq_resp_ok "T1.4 activate_project (no error)" 5 "$RPC_LAST_OUT" '.error == null'

jq_resp_ok "T1.6 Folder.fetch (no error)" 6 "$RPC_LAST_OUT" '.error == null'
jq_resp_ok "T1.6 Folder.fetch (folder row)" 6 "$RPC_LAST_OUT" \
    '.result[0]["base-type"] == "d"'
jq_resp_args_ok "T1.6 Folder.fetch (path)" 6 "$RPC_LAST_OUT" \
    --arg p "$RPC_PROJECT_PATH" '.result[0].path == $p'

jq_resp_ok "T1.7 Folder.project_description (no error)" 7 "$RPC_LAST_OUT" '.error == null'
jq_resp_ok "T1.7 Folder.project_description (msg string)" 7 "$RPC_LAST_OUT" \
    '(.msg | type) == "string"'

jq_resp_ok "T1.8 Codebase.search (no error)" 8 "$RPC_LAST_OUT" '.error == null'
jq_resp_ok "T1.8 Codebase.search (msg string)" 8 "$RPC_LAST_OUT" \
    '(.msg | type) == "string"'

jq_resp_ok "T1.5 remove_project (no error)" 9 "$RPC_LAST_OUT" '.error == null'

# --- Persistence (separate script runs; shutdown flushes DB) ---
run_t1_case "$SCRIPT_DIR/rpc/t1-persist.script.in"
sqlite_count_ok "T1.2 create_project persisted" "$RPC_DB" \
    "SELECT COUNT(*) FROM filebase WHERE delete_id = 0 AND is_project = 1 AND path = '$RPC_PROJECT_PATH';" \
    "1"
sqlite_count_ok "T1.4 activate_project is_active" "$RPC_DB" \
    "SELECT COUNT(*) FROM filebase WHERE path = '$RPC_PROJECT_PATH' AND delete_id = 0 AND is_active = 1;" \
    "1"

run_t1_case "$SCRIPT_DIR/rpc/t1-remove.script.in"
sqlite_count_ok "T1.5 remove_project (is_project cleared)" "$RPC_DB" \
    "SELECT COUNT(*) FROM filebase WHERE path = '$RPC_PROJECT_PATH' AND delete_id = 0 AND is_project = 0;" \
    "1"

print_test_summary
exit "$([ "${TESTS_FAILED:-0}" -eq 0 ] && echo 0 || echo 1)"
