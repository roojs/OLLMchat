#!/usr/bin/env bash
# R01 — CI run 27520220666: icon staging failed (sidebar-hide-symbolic.svg missing).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
MANIFEST="$ROOT_DIR/android/icons/manifest"
INDEX="$ROOT_DIR/android/icons/Adwaita/index.theme"

[ -f "$MANIFEST" ] || { echo "missing $MANIFEST" >&2; exit 1; }
[ -f "$INDEX" ] || { echo "missing $INDEX" >&2; exit 1; }

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  [ -z "$line" ] && continue

  dest_relpath="${line%%$'\t'*}"
  line="${line#*$'\t'}"
  source_theme="${line%%$'\t'*}"
  source_relpath="${line#*$'\t'}"

  if [ "$source_theme" = bundled ]; then
    src="$ROOT_DIR/android/icons/Adwaita/$dest_relpath"
    [ -f "$src" ] || { echo "bundled icon missing: $src" >&2; exit 1; }
  fi
done < "$MANIFEST"

echo "R01 bundled-android-icons: OK"
