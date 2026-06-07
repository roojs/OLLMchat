#!/bin/bash
# Shared helpers for ollmfilesd RPC shell tests (socat + jq).

require_rpc_tools() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required for RPC tests" >&2
        exit 1
    fi
    if command -v socat >/dev/null 2>&1; then
        RPC_SEND='socat - UNIX-CONNECT:'
    elif command -v nc >/dev/null 2>&1; then
        RPC_SEND='nc -U'
    else
        echo "Error: socat or nc is required for RPC tests" >&2
        exit 1
    fi
}

# One JSON-RPC request per connection (NDJSON line in, one line out).
rpc_call() {
    local id="$1"
    local method="$2"
    local params="${3:-{}}"
    local line="{\"jsonrpc\":\"2.0\",\"id\":${id},\"method\":\"${method}\",\"params\":${params}}"
    if [ "$RPC_SEND" = "nc -U" ]; then
        printf '%s\n' "$line" | nc -U "$RPC_SOCKET"
    else
        printf '%s\n' "$line" | socat - UNIX-CONNECT:"${RPC_SOCKET}"
    fi
}

wait_for_socket() {
    local attempt=0
    while [ "$attempt" -lt 50 ]; do
        if [ -S "${RPC_SOCKET}" ] && rpc_call 0 "Daemon.hello" \
            '{"protocol":1,"client":"test-rpc-probe"}' >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
        attempt=$((attempt + 1))
    done
    return 1
}

rpc_shutdown() {
    if [ -S "${RPC_SOCKET}" ]; then
        rpc_call 999 "Daemon.shutdown" '{}' >/dev/null 2>&1 || true
    fi
    local attempt=0
    while [ "$attempt" -lt 30 ]; do
        if [ ! -S "${RPC_SOCKET}" ]; then
            return 0
        fi
        sleep 0.1
        attempt=$((attempt + 1))
    done
    return 1
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
