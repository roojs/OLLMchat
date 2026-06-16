#!/usr/bin/env bash
# R13 — GLib TLS fix: ensure extension points before scanning GIO modules.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
PATCH="$ROOT_DIR/subprojects/packagefiles/glib/tls-ensure-before-scan.patch"
WRAP="$ROOT_DIR/android/pixiewood-wraps/glib/glib.wrap"

[ -f "$PATCH" ] || { echo "missing patch: $PATCH" >&2; exit 1; }
[ -f "$WRAP" ] || { echo "missing wrap: $WRAP" >&2; exit 1; }

grep -q '_g_io_modules_ensure_extension_points_registered' "$PATCH" ||
  { echo "TLS patch missing ensure-before-scan call" >&2; exit 1; }
grep -q 'g_io_modules_scan_all_in_directory_with_scope' "$PATCH" ||
  { echo "TLS patch must touch scan function" >&2; exit 1; }
grep -q 'OLLMchat' "$PATCH" &&
  { echo "TLS ship patch must not contain OLLMchat debug logging" >&2; exit 1; }

grep -qE 'revision[[:space:]]*=[[:space:]]*2\.84\.0' "$WRAP" ||
  { echo "glib.wrap must pin 2.84.0 for reproducible TLS patch" >&2; exit 1; }
grep -q 'tls-ensure-before-scan.patch' "$WRAP" ||
  { echo "glib.wrap must list tls-ensure-before-scan.patch" >&2; exit 1; }

echo "R13 glib-tls-ensure-before-scan: OK"
