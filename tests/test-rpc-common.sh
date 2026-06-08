#!/bin/bash
# Shared helpers for ollmfilesd RPC script tests (NDJSON file + jq).

require_rpc_tools() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required for RPC tests" >&2
        exit 1
    fi
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

jq_line_ok() {
    local label="$1"
    local line="$2"
    local filter="$3"
    if echo "$line" | jq -e "$filter" >/dev/null 2>&1; then
        test_pass "$label"
    else
        echo "$line" | jq . >&2 || echo "$line" >&2
        test_fail "$label"
    fi
}
