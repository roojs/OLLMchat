#!/usr/bin/env bash
# R12 — verify-apk.sh libgtk-4.so string checks must match C string literals in the
# patch marker (C comments are stripped from release .so files; CI run 27615842437).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR
VERIFY="$ROOT_DIR/scripts/android/verify-apk.sh"
MARKER="$ROOT_DIR/subprojects/gtk/gdk/android/gdkandroidollmchatpatch.c"

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

prepare_android_subprojects_before_meson

[ -f "$VERIFY" ] || { echo "missing verify-apk.sh" >&2; exit 1; }
[ -f "$MARKER" ] || { echo "missing patch marker: $MARKER" >&2; exit 1; }

mapfile -t patterns < <(
  grep "lib/arm64-v8a/libgtk-4.so" "$VERIFY" |
    sed -n "s/.*grep -q '\\([^']*\\)'.*/\\1/p"
)

if [ "${#patterns[@]}" -eq 0 ]; then
  echo "no libgtk-4.so string patterns found in verify-apk.sh" >&2
  exit 1
fi

for pattern in "${patterns[@]}"; do
  if ! grep -q "\"$pattern\"" "$MARKER"; then
    echo "verify-apk.sh greps libgtk-4.so for '$pattern' but patch marker has no string literal" >&2
    echo "C comments are not present in stripped libgtk-4.so (see CI run 27615842437)." >&2
    exit 1
  fi
done

echo "R12 verify-apk-libgtk-strings: OK (${#patterns[@]} patterns)"
