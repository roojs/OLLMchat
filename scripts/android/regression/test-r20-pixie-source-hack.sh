#!/usr/bin/env bash
# R20 — a chat build that is set up to compile the GTK stack from source,
# or that still has a local GLib scheduler hack, must stop.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CHECK="$ROOT_DIR/scripts/android/refuse-pixie-source-hack.sh"
[ -x "$CHECK" ] || chmod +x "$CHECK"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

ok_dir="$tmp/ok"
mkdir -p "$ok_dir/meson-logs" "$ok_dir/pixie/share/pixiewood"
printf '%s\n' 'env[PKG_CONFIG]: /pixie/share/pixiewood/pkg-config-wrapper' > "$ok_dir/meson-logs/meson-log.txt"
printf '%s\n' 'build ollmapp/ollmchat: phony' > "$ok_dir/build.ninja"
printf '%s\n' '{"provided_dependencies":[]}' > "$ok_dir/pixie/share/pixiewood/MANIFEST.json"

if ! PIXIEWOOD_USE_PIXIE=1 PIXIEWOOD_BUILD_DIR="$ok_dir" PIXIEWOOD_CHECK_ROOT="$ROOT_DIR" "$CHECK" >/dev/null; then
  echo "R20 clean pixie tree was rejected" >&2
  exit 1
fi

bad_log="$tmp/source"
mkdir -p "$bad_log/meson-logs"
printf '%s\n' 'Main project name: ollmchat' > "$bad_log/meson-logs/meson-log.txt"
set +e
out="$(PIXIEWOOD_USE_PIXIE=1 PIXIEWOOD_BUILD_DIR="$bad_log" PIXIEWOOD_CHECK_ROOT="$ROOT_DIR" "$CHECK" 2>&1)"
code=$?
set -e
[ "$code" -ne 0 ] || { echo "R20 from-source Meson log was allowed" >&2; exit 1; }
printf '%s\n' "$out" | grep -q 'hack has been done that is not allowed' ||
  { echo "R20 missing stop message: $out" >&2; exit 1; }

set +e
out="$(PIXIEWOOD_USE_PIXIE= PIXIEWOOD_BUILD_DIR="$ok_dir" PIXIEWOOD_CHECK_ROOT="$ROOT_DIR" "$CHECK" 2>&1)"
code=$?
set -e
[ "$code" -ne 0 ] || { echo "R20 unset PIXIEWOOD_USE_PIXIE was allowed" >&2; exit 1; }

hack_root="$tmp/tree"
mkdir -p "$hack_root/ollmapp/android"
echo 'int x;' > "$hack_root/ollmapp/android/android-sched.c"
set +e
out="$(PIXIEWOOD_USE_PIXIE=1 PIXIEWOOD_BUILD_DIR="$ok_dir" PIXIEWOOD_CHECK_ROOT="$hack_root" "$CHECK" 2>&1)"
code=$?
set -e
[ "$code" -ne 0 ] || { echo "R20 android-sched.c was allowed" >&2; exit 1; }
printf '%s\n' "$out" | grep -q 'android-sched.c' ||
  { echo "R20 did not name android-sched.c: $out" >&2; exit 1; }

echo "R20 pixie-source-hack: OK"
