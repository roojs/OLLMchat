#!/usr/bin/env bash
# Probe always-on <write>…</write> edit copy with ollmchat-cli (no write tool).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -x "$ROOT/build/ollmapp/ollmchat-cli" ]]; then
	CLI_DEFAULT="$ROOT/build/ollmapp/ollmchat-cli"
else
	CLI_DEFAULT="$ROOT/build/ollmchat-cli"
fi
CLI="${OLLMCHAT_CLI:-$CLI_DEFAULT}"
SYSTEM="${OLLMCHAT_SYSTEM_FILE:-$ROOT/tests/data/always-on-edit-brace-poc/system.md}"
USER="${OLLMCHAT_USER_FILE:-$ROOT/tests/data/always-on-edit-brace-poc/user.md}"
MODEL="${OLLMCHAT_MODEL:-ornith-1.5:35b}"
OUT="${OLLMCHAT_POC_OUT:-}"

if [[ ! -x "$CLI" ]]; then
	echo "Missing executable: $CLI (build with: ninja -C build ollmchat-cli)" >&2
	exit 1
fi

ARGS=(--system-file="$SYSTEM" --user-file="$USER" -m "$MODEL")
if [[ -n "${OLLMCHAT_DEBUG:-}" ]]; then
	ARGS=(-d "${ARGS[@]}")
fi

if [[ -n "$OUT" ]]; then
	"$CLI" "${ARGS[@]}" | tee "$OUT"
else
	"$CLI" "${ARGS[@]}"
fi