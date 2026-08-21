#!/usr/bin/env bash
# R13 — TLS is app-only (g_io_openssl_load). Do not patch GLib module scan.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
PATCH_DIR="$ROOT_DIR/android/pixiewood-wraps/glib/packagefiles/glib"
PATCH="$PATCH_DIR/tls-ensure-before-scan.patch"
HACK="$PATCH_DIR/hack.patch"
WRAP="$ROOT_DIR/android/pixiewood-wraps/glib/glib.wrap"

[ -f "$WRAP" ] || { echo "missing wrap: $WRAP" >&2; exit 1; }
[ -f "$HACK" ] || { echo "missing g_set_user_dirs hack.patch: $HACK" >&2; exit 1; }

if [ -f "$PATCH" ]; then
  echo "GLib TLS scan patch must not ship (9.2 static gioopenssl): $PATCH" >&2
  exit 1
fi
grep -q 'tls-ensure-before-scan.patch' "$WRAP" &&
  { echo "glib.wrap must not list tls-ensure-before-scan.patch" >&2; exit 1; }
grep -q 'hack.patch' "$WRAP" ||
  { echo "glib.wrap must list hack.patch" >&2; exit 1; }

echo "R13 glib-tls-ensure-before-scan: OK (patch absent)"
