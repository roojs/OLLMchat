#!/usr/bin/env bash
# R22 — pixie chat build must not clone or restore GTK source trees.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR
export PIXIEWOOD_USE_PIXIE=1
export PIXIEWOOD_MANIFEST="$ROOT_DIR/android/pixiewood-chat-poc.xml"

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

mkdir -p "$ROOT_DIR/subprojects/gtk"
echo '# trap' > "$ROOT_DIR/subprojects/gtk/meson.build"

out="$(prepare_android_subprojects_before_meson 2>&1)" && code=0 || code=$?
[ "$code" -ne 0 ] || { echo "R22: prepare_android_subprojects should refuse" >&2; exit 1; }
echo "$out" | grep -q 'forbidden when PIXIEWOOD_USE_PIXIE=1' ||
  { echo "R22: unexpected message: $out" >&2; exit 1; }
[ ! -d "$ROOT_DIR/subprojects/gtk" ] ||
  { echo "R22: subprojects/gtk should be purged" >&2; exit 1; }

# ALLOW_GTK_SUBPROJECT must not override PIXIEWOOD_USE_PIXIE=1 (regression used to allow that).
export ALLOW_GTK_SUBPROJECT=1
out="$(prepare_android_subprojects_before_meson 2>&1)" && code=0 || code=$?
[ "$code" -ne 0 ] || { echo "R22: ALLOW_GTK must not bypass pixie" >&2; exit 1; }

echo "R22 pixie-forbids-gtk-checkout: OK"