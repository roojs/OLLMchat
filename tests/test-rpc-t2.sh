#!/bin/bash
# Tranche 2 — File RPC tests (interactive + rpc-script + jq + sqlite + filesystem).
#
# Two caller paths (see docs/plans/done/2.10.4.10-DONE-rpc-tests.md):
#   Path A — activate with scan (normal open project); File.* on existing files.
#   Path B — activate with skip_scan + File.register (agent new_fake path).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test-common.sh"
source "$SCRIPT_DIR/test-rpc-common.sh"

BUILD_DIR="${1:-$PROJECT_ROOT/build}"
OLLMFILESD="$BUILD_DIR/ollmfilesd/ollmfilesd"
TEST_DIR="$BUILD_DIR/test-rpc-t2-$$"
ISOLATED_DIRS=()
RPC_DB="$TEST_DIR/files.sqlite"
HELLO_PATH=""
NEW_FILE_PATH=""
REGISTER_PATH=""

cleanup() {
    local d
    for d in "${ISOLATED_DIRS[@]}"; do
        if [ "${TESTS_FAILED:-0}" -eq 0 ] && [ -d "$d" ]; then
            rm -rf "$d"
        fi
    done
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

run_t2_case() {
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
    RPC_DB="$TEST_DIR/files.sqlite"
}

# Fresh data_dir per case — avoids cross-script DB interference (e.g. after shutdown).
run_t2_case_isolated() {
    local template="$1"
    local case_dir
    case_dir=$(mktemp -d "$TEST_DIR/case-XXXX")
    ISOLATED_DIRS+=("$case_dir")
    local saved_test_dir="$TEST_DIR"
    TEST_DIR="$case_dir"
    setup_rpc_fixture minimal-project
    ISOLATED_HELLO="$RPC_PROJECT_PATH/hello.txt"
    ISOLATED_REGISTER="$RPC_PROJECT_PATH/pending-register.txt"
    ISOLATED_DB="$case_dir/files.sqlite"
    run_t2_case "$template"
    TEST_DIR="$saved_test_dir"
}

file_exists_ok() {
    local label="$1"
    local path="$2"
    if [ -f "$path" ]; then
        test_pass "$label"
    else
        test_fail "$label (missing: $path)"
    fi
}

file_missing_ok() {
    local label="$1"
    local path="$2"
    if [ ! -e "$path" ]; then
        test_pass "$label"
    else
        test_fail "$label (still present: $path)"
    fi
}

file_content_ok() {
    local label="$1"
    local path="$2"
    local expected="$3"
    if [ ! -f "$path" ]; then
        test_fail "$label (missing: $path)"
        return
    fi
    local actual
    actual=$(cat "$path")
    if [ "$actual" = "$expected" ]; then
        test_pass "$label"
    else
        echo "  Expected: $(printf '%q' "$expected")" >&2
        echo "  Actual:   $(printf '%q' "$actual")" >&2
        test_fail "$label"
    fi
}

mkdir -p "$TEST_DIR"
setup_rpc_fixture minimal-project

HELLO_PATH="$RPC_PROJECT_PATH/hello.txt"
NEW_FILE_PATH="$RPC_PROJECT_PATH/src/new.txt"
REGISTER_PATH="$RPC_PROJECT_PATH/pending-register.txt"
mkdir -p "$RPC_PROJECT_PATH/src"
printf 'seed\n' >"$NEW_FILE_PATH"

# --- Path A: scan on activate (single script session) ---
run_t2_case "$SCRIPT_DIR/rpc/t2-scan.script.in"

jq_resp_ok "T2A.2 File.read (no error)" 4 "$RPC_LAST_OUT" '.error == null'
jq_resp_ok "T2A.2 File.read (id > 0)" 4 "$RPC_LAST_OUT" '(.result[0].id // .result[0]["id"]) > 0'
jq_resp_args_ok "T2A.2 File.read (path)" 4 "$RPC_LAST_OUT" \
    --arg p "$HELLO_PATH" '.result[0].path == $p'

jq_resp_ok "T2A.1 File.write (no error)" 5 "$RPC_LAST_OUT" '.error == null and .msg == "ok"'

jq_resp_ok "T2A.3 File.changed.check (NO_CHANGE)" 6 "$RPC_LAST_OUT" \
    '.error == null and .msg == "0"'

file_content_ok "T2A.2 File.read (disk content)" "$HELLO_PATH" "hello from rpc fixture"

run_t2_case "$SCRIPT_DIR/rpc/t2-file-activate.script.in"
if grep -q "no signal call_activate on File" "$RPC_LAST_ERR"; then
    test_pass "T2A.7 File.activate (no server handler)"
else
    test_fail "T2A.7 File.activate (no server handler)"
fi
if [ -z "$(rpc_resp_by_id 4 "$RPC_LAST_OUT")" ]; then
    test_pass "T2A.7 File.activate (no wire response)"
else
    test_fail "T2A.7 File.activate (no wire response)"
fi

# --- Path B: skip_scan + File.register ---
run_t2_case "$SCRIPT_DIR/rpc/t2-register.script.in"
jq_resp_ok "T2B.5 File.register (no error)" 4 "$RPC_LAST_OUT" '.error == null'
jq_resp_ok "T2B.5 File.register (id > 0)" 4 "$RPC_LAST_OUT" \
    '(.result[0].id // .result[0]["id"]) > 0'
jq_resp_args_ok "T2B.5 File.register (path)" 4 "$RPC_LAST_OUT" \
    --arg p "$REGISTER_PATH" '.result[0].path == $p'
sqlite_count_ok "T2B.5 File.register (sqlite row)" "$RPC_DB" \
    "SELECT COUNT(*) FROM filebase WHERE delete_id = 0 AND path = '$REGISTER_PATH';" \
    "1"

jq_resp_ok "T2B.5 File.read after register (no error)" 5 "$RPC_LAST_OUT" '.error == null'
jq_resp_ok "T2B.5 File.read after register (id > 0)" 5 "$RPC_LAST_OUT" \
    '(.result[0].id // .result[0]["id"]) > 0'
jq_resp_args_ok "T2B.5 File.read after register (path)" 5 "$RPC_LAST_OUT" \
    --arg p "$REGISTER_PATH" '.result[0].path == $p'

# --- Path A: changed.check with external touch ---
touch "$HELLO_PATH"
run_t2_case "$SCRIPT_DIR/rpc/t2-changed-dirty.script.in"
jq_resp_ok "T2A.4 File.changed.check (CHANGED_HAS_UNSAVED)" 4 "$RPC_LAST_OUT" \
    '.error == null and .msg == "1"'

# --- Path A: write persistence (isolated data_dir) ---
run_t2_case_isolated "$SCRIPT_DIR/rpc/t2-write-persist.script.in"
sqlite_count_ok "T2A.1 File.write (sqlite row)" "$ISOLATED_DB" \
    "SELECT COUNT(*) FROM filebase WHERE delete_id = 0 AND path = '$ISOLATED_HELLO';" \
    "1"

# --- Path B: delete (skip_scan + register new file) ---
run_t2_case_isolated "$SCRIPT_DIR/rpc/t2-delete.script.in"
jq_resp_ok "T2B.6 File.read before delete (no error)" 5 "$RPC_LAST_OUT" '.error == null'
jq_resp_ok "T2B.6 File.delete (no error)" 7 "$RPC_LAST_OUT" '.error == null and .msg == "ok"'

print_test_summary
exit "$([ "${TESTS_FAILED:-0}" -eq 0 ] && echo 0 || echo 1)"
