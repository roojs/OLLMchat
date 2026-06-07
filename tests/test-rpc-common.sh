#!/bin/bash
# Shared helpers for ollmfilesd RPC shell tests (stdio NDJSON + jq).

require_rpc_tools() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required for RPC tests" >&2
        exit 1
    fi
}

# Start ollmfilesd --interactive; one persistent stdin/stdout session.
rpc_start() {
    coproc OLLMFILESD (
        OLLMFILES_IS_TEST=1 exec "$OLLMFILESD" --data-dir="$TEST_DIR" --interactive \
            2>"$TEST_DIR/ollmfilesd.stderr"
    )
    RPC_IN=${OLLMFILESD[1]}
    RPC_OUT=${OLLMFILESD[0]}
    RPC_PID=$OLLMFILESD_PID
    RPC_LAST_RESPONSE=""
}

# One JSON-RPC request line on stdin; read one response line from stdout.
# Result is in RPC_LAST_RESPONSE (not echoed — coproc fds break in $(...)).
rpc_call() {
    local id="$1"
    local method="$2"
    local params="${3:-{}}"
    local line="{\"jsonrpc\":\"2.0\",\"id\":${id},\"method\":\"${method}\",\"params\":${params}}"

    RPC_LAST_RESPONSE=""
    printf '%s\n' "$line" >&${RPC_IN} || return 1
    if ! read -r -t "${RPC_READ_TIMEOUT:-5}" RPC_LAST_RESPONSE <&${RPC_OUT}; then
        RPC_LAST_RESPONSE=""
        return 1
    fi
    return 0
}

wait_for_rpc_ready() {
    local attempt=0
    while [ "$attempt" -lt 60 ]; do
        if ! kill -0 "${RPC_PID:-}" 2>/dev/null; then
            return 1
        fi
        if [ -f "$TEST_DIR/files.sqlite" ]; then
            break
        fi
        sleep 0.25
        attempt=$((attempt + 1))
    done
    RPC_READ_TIMEOUT=15 rpc_call 0 "Daemon.hello" '{"protocol":1,"client":"test-rpc-probe"}' || return 1
    echo "$RPC_LAST_RESPONSE" | jq -e '.error == null and .result.server == "ollmfilesd"' >/dev/null 2>&1
}

rpc_shutdown() {
    if [ -n "${RPC_IN:-}" ]; then
        rpc_call 999 "Daemon.shutdown" '{}' >/dev/null 2>&1 || true
        exec {RPC_IN}>&-
    fi
    local attempt=0
    while [ "$attempt" -lt 30 ]; do
        if ! kill -0 "${RPC_PID:-}" 2>/dev/null; then
            return 0
        fi
        sleep 0.1
        attempt=$((attempt + 1))
    done
    kill "${RPC_PID}" 2>/dev/null || true
    wait "${RPC_PID}" 2>/dev/null || true
}

jq_ok() {
    local label="$1"
    local json="$2"
    local filter="$3"
    if echo "$json" | jq -e "$filter" >/dev/null 2>&1; then
        test_pass "$label"
    else
        echo "$json" | jq . >&2 || echo "$json" >&2
        test_fail "$label"
    fi
}
