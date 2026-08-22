#!/usr/bin/env bash
# R18 — Android webkitgtk-android-1.vapi has get_network_session(), not a
# network_session property. Property syntax compiled on Linux/Windows and
# hid until a fresh Android valac (CI 32552806663).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
BROWSER="$ROOT_DIR/libocwebkit/Browser.vala"

[ -f "$BROWSER" ] || {
  echo "R18 missing $BROWSER" >&2
  exit 1
}

grep -q 'get_network_session()' "$BROWSER" || {
  echo "R18 expected get_network_session() in libocwebkit/Browser.vala" >&2
  exit 1
}

if grep -nE '\.network_session\b' "$ROOT_DIR"/libocwebkit/*.vala; then
  echo "R18 libocwebkit must not use .network_session (Android vapi has no property)" >&2
  exit 1
fi

echo "R18 webkit-get-network-session: OK"
