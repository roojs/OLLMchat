#!/bin/bash
# Shared helpers for ollmfilesd RPC script tests (NDJSON file + jq).

require_rpc_tools() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required for RPC tests" >&2
        exit 1
    fi
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "Error: sqlite3 is required for RPC tests" >&2
        exit 1
    fi
}

# Copy tracked fixture tree into the isolated test data dir.
setup_rpc_fixture() {
    local fixture_name="${1:-minimal-project}"
    local src="$SCRIPT_DIR/rpc-fixtures/$fixture_name"
    local dest="$TEST_DIR/projects/$fixture_name"
    if [ ! -d "$src" ]; then
        echo "Error: RPC fixture not found at $src" >&2
        exit 1
    fi
    mkdir -p "$TEST_DIR/projects"
    cp -a "$src" "$dest"
    RPC_PROJECT_PATH="$(cd "$dest" && pwd)"
}

# Substitute __PROJECT_PATH__ in a template script; write runnable script in TEST_DIR.
prepare_rpc_script() {
    local template="$1"
    local dest="$2"
    if [ -z "${RPC_PROJECT_PATH:-}" ]; then
        echo "Error: RPC_PROJECT_PATH not set (call setup_rpc_fixture first)" >&2
        exit 1
    fi
    sed "s|__PROJECT_PATH__|${RPC_PROJECT_PATH}|g" "$template" >"$dest"
}

# Run --interactive --rpc-script; capture stdout (NDJSON) and stderr.
run_rpc_script() {
    local script="$1"
    local out="$2"
    local err="$3"
    OLLMFILES_IS_TEST=1 "$OLLMFILESD" --interactive --data-dir="$TEST_DIR" \
        --rpc-script="$script" >"$out" 2>"$err"
}

rpc_line() {
    sed -n "${1}p" "$2"
}

# Find a JSON-RPC response line by request id (skip notifications without id).
rpc_resp_by_id() {
    local id="$1"
    local out="$2"
    jq -c "select(.id == $id)" "$out" | head -1
}

jq_line_ok() {
    local label="$1"
    local line="$2"
    local filter="$3"
    if [ -z "$line" ]; then
        echo "(empty line)" >&2
        test_fail "$label"
        return
    fi
    if echo "$line" | jq -e "$filter" >/dev/null 2>&1; then
        test_pass "$label"
    else
        echo "$line" | jq . >&2 || echo "$line" >&2
        test_fail "$label"
    fi
}

jq_resp_ok() {
    local label="$1"
    local id="$2"
    local out="$3"
    local filter="$4"
    local line
    line=$(rpc_resp_by_id "$id" "$out")
    jq_line_ok "$label" "$line" "$filter"
}

# Pass jq args after out file, e.g. --arg p "$path" '.result.path == $p'
jq_resp_args_ok() {
    local label="$1"
    local id="$2"
    local out="$3"
    shift 3
    local line
    line=$(rpc_resp_by_id "$id" "$out")
    if [ -z "$line" ]; then
        echo "(empty line)" >&2
        test_fail "$label"
        return
    fi
    if echo "$line" | jq -e "$@" >/dev/null 2>&1; then
        test_pass "$label"
    else
        echo "$line" | jq . >&2 || echo "$line" >&2
        test_fail "$label"
    fi
}

sqlite_count_ok() {
    local label="$1"
    local db="$2"
    local sql="$3"
    local expected="$4"
    if [ ! -f "$db" ]; then
        test_fail "$label (database not found: $db)"
        return
    fi
    local count
    count=$(sqlite3 "$db" "$sql")
    if [ "$count" = "$expected" ]; then
        test_pass "$label"
    else
        echo "  SQL: $sql" >&2
        echo "  Expected count: $expected, got: $count" >&2
        test_fail "$label"
    fi
}
