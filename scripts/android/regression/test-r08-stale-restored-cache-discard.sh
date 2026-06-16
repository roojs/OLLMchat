#!/usr/bin/env bash
# R08 — restore-keys must not leave stale subprojects/gtk when PIXIEWOOD_DEPS_HASH changed.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

prepare_android_subprojects_before_meson

marker="$(gtk_subproject_patch_marker)"
if [ ! -f "$marker" ]; then
  echo "expected patched gtk tree before stale-cache simulation" >&2
  exit 1
fi

# Restored cache entry from a previous deps generation; current hash is different.
old_hash="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
current_hash="cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe"

PIXIEWOOD_DEPS_HASH="$current_hash" \
  CACHE_MATCHED_SUBPROJECTS_KEY="android-subprojects-v1-stable-${old_hash}" \
  scripts/android/validate-restored-caches.sh >/dev/null

if [ -d "$ROOT_DIR/subprojects/gtk" ]; then
  echo "stale subprojects/gtk should have been discarded" >&2
  exit 1
fi

echo "R08 stale-restored-cache-discard: OK"
