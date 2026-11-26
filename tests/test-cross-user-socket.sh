#!/bin/bash
# Cross-user ollmfilesd Unix socket regression.
#
# Spawns ollmfilesd the way ClientBoot.spawn does (absolute binary, --debug,
# no --interactive / --tcp / --socket / --rpc-script), with a 0755 home and
# data directory. A second uid, mapped through a user namespace to a
# subordinate id, must not read a 0600 file, write a file, run a sandbox
# command, hold the .fd socket, or set the pairing PIN.
#
# The test fails while that second uid can do any of those. It passes once
# the daemon refuses the other uid before the action.

set -euo pipefail

BUILD_DIR="${1:-}"
if [ -z "$BUILD_DIR" ]; then
	echo "usage: $0 BUILD_DIR" >&2
	exit 2
fi

DAEMON="$BUILD_DIR/ollmfilesd/ollmfilesd"
CLIENT="$BUILD_DIR/tests/test-cross-user-daemon-client"
if [ ! -x "$DAEMON" ] || [ ! -x "$CLIENT" ]; then
	echo "missing $DAEMON or $CLIENT" >&2
	exit 2
fi

MARKER="cross-user-socket-marker"
PIN="placeholder"
ROOT=$(mktemp -d /var/tmp/ollm-cross-user-XXXX)
chmod 0755 "$ROOT"
HOME_DIR="$ROOT/home"
DATA_DIR="$HOME_DIR/.local/share/ollmchat"
SOCK="$DATA_DIR/ollmfilesd.sock"
PRIVATE="$HOME_DIR/private-file"
WRITE_PATH="$HOME_DIR/written-by-daemon"
BUBBLE_OUT="$HOME_DIR/bubble-out"
LISTEN_HOST="192.0.2.1"
LISTEN_PORT="41429"
DAEMON_PID=""

cleanup() {
	if [ -n "${DAEMON_PID}" ]; then
		kill "$DAEMON_PID" 2>/dev/null || true
		wait "$DAEMON_PID" 2>/dev/null || true
	fi
	if [ -f "$DATA_DIR/ollmfilesd.pid" ]; then
		kill "$(cat "$DATA_DIR/ollmfilesd.pid")" 2>/dev/null || true
	fi
	sudo ip addr del "$LISTEN_HOST/32" dev lo 2>/dev/null || true
	if [ "${KEEP_ROOT:-}" = "" ]; then
		rm -rf "$ROOT"
	fi
}
trap cleanup EXIT

FAILS=0
fail() {
	echo "FAIL: $*" >&2
	FAILS=$((FAILS + 1))
}

harness() {
	echo "HARNESS: $*" >&2
	if [ -f "$HOME_DIR/.cache/ollmchat/ollmfilesd.stderr.log" ]; then
		echo "--- daemon log ---" >&2
		tail -n 80 "$HOME_DIR/.cache/ollmchat/ollmfilesd.stderr.log" >&2 || true
	fi
	KEEP_ROOT=1
	exit 99
}

as_other() {
	unshare --user --map-users=0:100000:1 --map-groups=0:100000:1 \
		--setuid 0 --setgid 0 "$@"
}

mkdir -m 0755 "$HOME_DIR"
mkdir -m 0755 "$HOME_DIR/.local"
mkdir -m 0755 "$HOME_DIR/.local/share"
mkdir -m 0755 "$DATA_DIR"
mkdir -m 0755 "$HOME_DIR/.config"
mkdir -m 0755 "$HOME_DIR/.config/ollmchat"
mkdir -m 0755 "$HOME_DIR/.cache"
printf '%s' "$MARKER" > "$PRIVATE"
chmod 0600 "$PRIVATE"
cat > "$HOME_DIR/.config/ollmchat/config.2.json" <<EOF
{
  "filesd": {
    "unix": true,
    "socket": "${LISTEN_HOST}:${LISTEN_PORT}",
    "ssl_enabled": true,
    "systemd": false
  }
}
EOF
sudo ip addr add "$LISTEN_HOST/32" dev lo 2>/dev/null || true

# Same argv ClientBoot.spawn builds when debug is true and pass_data_dir
# is false: the daemon binary plus --debug, and no foreground flag.
env -u OLLMFILESD_DAEMON \
	HOME="$HOME_DIR" \
	XDG_CONFIG_HOME="$HOME_DIR/.config" \
	XDG_CACHE_HOME="$HOME_DIR/.cache" \
	"$DAEMON" --debug >/dev/null 2>&1 || true

for _ in $(seq 1 50); do
	if [ -S "$SOCK" ]; then
		break
	fi
	sleep 0.1
done
if [ ! -S "$SOCK" ]; then
	harness "daemon socket did not appear"
fi
if [ -f "$DATA_DIR/ollmfilesd.pid" ]; then
	DAEMON_PID=$(cat "$DATA_DIR/ollmfilesd.pid")
fi

echo "socket_mode=$(stat -c %a "$SOCK")"
echo "fd_socket_mode=$(stat -c %a "$SOCK.fd")"
echo "data_dir_mode=$(stat -c %a "$DATA_DIR")"

if as_other python3 -c 'import sys; open(sys.argv[1], "rb").read()' "$PRIVATE" 2>/dev/null; then
	harness "other uid can already read the private file"
fi

full_b64=$(printf '%s' "$MARKER" | base64 -w0)
trim_b64=$(python3 -c 'import sys,base64; d=sys.argv[1].encode(); print(base64.b64encode(d[:-1]).decode())' "$MARKER")

owner_read=$("$CLIENT" "$SOCK" read "$PRIVATE" "$MARKER" "$full_b64" "$trim_b64")
echo "owner_read=$owner_read"
printf '%s\n' "$owner_read" | grep -q 'hit=yes' || harness "owner File.read did not return the file"

other_read=$(as_other "$CLIENT" "$SOCK" read "$PRIVATE" "$MARKER" "$full_b64" "$trim_b64")
echo "other_read=$other_read"
if printf '%s\n' "$other_read" | grep -q 'hit=yes'; then
	fail "other uid File.read returned the private file"
fi

"$CLIENT" "$SOCK" write "$WRITE_PATH" "$MARKER" >/dev/null
if ! grep -q "$MARKER" "$WRITE_PATH"; then
	harness "owner File.rpc_write did not create the file"
fi
rm -f "$WRITE_PATH"
as_other "$CLIENT" "$SOCK" write "$WRITE_PATH" "$MARKER" >/dev/null || true
if [ -e "$WRITE_PATH" ]; then
	fail "other uid File.rpc_write created $WRITE_PATH"
fi

owner_bubble=$("$CLIENT" "$SOCK" bubble "$BUBBLE_OUT" "$HOME_DIR" "$MARKER" || true)
echo "owner_bubble=$owner_bubble"
bubble_ok=0
for _ in $(seq 1 30); do
	if [ -f "$BUBBLE_OUT" ] && grep -q "$MARKER" "$BUBBLE_OUT"; then
		bubble_ok=1
		break
	fi
	sleep 0.2
done
if [ "$bubble_ok" -ne 1 ]; then
	harness "owner Sandbox-Bubble did not write the marker"
fi
rm -f "$BUBBLE_OUT"
as_other "$CLIENT" "$SOCK" bubble "$BUBBLE_OUT" "$HOME_DIR" "$MARKER" >/dev/null || true
for _ in $(seq 1 15); do
	if [ -e "$BUBBLE_OUT" ]; then
		break
	fi
	sleep 0.2
done
if [ -e "$BUBBLE_OUT" ]; then
	fail "other uid Sandbox-Bubble wrote $BUBBLE_OUT"
fi

other_fd=$(as_other "$CLIENT" "$SOCK.fd" fd)
echo "other_fd=$other_fd"
if printf '%s\n' "$other_fd" | grep -q 'held=yes'; then
	fail "other uid connection to the fd socket stayed open"
fi

handshake() {
	# TLS 1.3 reports the handshake up before this server drops a client
	# that sent no certificate. A connection the server keeps open is the
	# acceptance signal.
	local rc=0
	timeout 0.4 openssl s_client -connect "$1:$2" -quiet </dev/null >/dev/null 2>&1 || rc=$?
	if [ "$rc" -eq 124 ]; then
		echo handshake=ok
		return
	fi
	echo handshake=denied
}

before_hs=$(handshake "$LISTEN_HOST" "$LISTEN_PORT" || true)
echo "handshake_before=$before_hs"
other_pair=$(as_other "$CLIENT" "$SOCK" pair "$PIN" || true)
echo "other_pair=$other_pair"
after_hs=$(handshake "$LISTEN_HOST" "$LISTEN_PORT" || true)
echo "handshake_after=$after_hs"
if printf '%s\n' "$other_pair" | grep -q 'reply=ok'; then
	fail "other uid ClientCert.pair was accepted"
fi
if printf '%s\n' "$before_hs" | grep -q 'handshake=denied' \
	&& printf '%s\n' "$after_hs" | grep -q 'handshake=ok'; then
	fail "other uid ClientCert.pair opened the pairing window"
fi
if printf '%s\n' "$other_pair" | grep -q 'SSL listener is off'; then
	harness "SSL listener did not start, pair path was not exercised"
fi

if [ "$FAILS" -ne 0 ]; then
	if [ -f "$HOME_DIR/.cache/ollmchat/ollmfilesd.stderr.log" ]; then
		echo "--- daemon log ---" >&2
		tail -n 120 "$HOME_DIR/.cache/ollmchat/ollmfilesd.stderr.log" >&2 || true
	fi
	KEEP_ROOT=1
	exit 1
fi
echo "PASS"
