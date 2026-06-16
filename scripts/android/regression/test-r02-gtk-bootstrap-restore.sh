#!/usr/bin/env bash
# R02 — CI runs 27585547860, 27585952776, 27586582052:
# wrap-redirect subprojects/gtk/subprojects/graphene.wrap does not exist.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

install_wraps() {
  local extra="$ROOT_DIR/android/pixiewood-wraps"
  mkdir -p "$ROOT_DIR/subprojects"
  local dep_dir wrap
  for dep_dir in "$extra"/*/; do
    for wrap in "$dep_dir"/*.wrap; do
      [ -f "$wrap" ] && cp -a "$wrap" "$ROOT_DIR/subprojects/"
    done
  done
}

install_wraps
prepare_android_subprojects_before_meson
gtk_bootstrap_cache_is_valid || { echo "could not seed GTK bootstrap cache" >&2; exit 1; }

rm -rf "$ROOT_DIR/subprojects/gtk"
mkdir -p "$ROOT_DIR/subprojects/gtk"
echo '# broken stub' > "$ROOT_DIR/subprojects/gtk/meson.build"

log="$(mktemp)"
prepare_android_subprojects_before_meson > "$log" 2>&1

grep -q 'Restoring GTK from bootstrap cache' "$log" ||
  { echo "expected bootstrap restore; log:" >&2; cat "$log" >&2; exit 1; }
gtk_subproject_is_complete ||
  { echo "GTK still incomplete after bootstrap restore" >&2; exit 1; }
[ -f "$(gtk_subproject_patch_marker)" ] ||
  { echo "GTK patch marker missing after bootstrap restore" >&2; exit 1; }

echo "R02 gtk-bootstrap-restore: OK"
