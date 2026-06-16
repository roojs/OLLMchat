#!/usr/bin/env bash
# R03 — android-bugs.patch must apply; marker file proves patch is in the tree.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR
PATCH="$ROOT_DIR/android/pixiewood-wraps/gtk/android-bugs.patch"
MARKER="$ROOT_DIR/subprojects/gtk/gdk/android/gdkandroidollmchatpatch.c"

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

[ -f "$PATCH" ] || { echo "missing patch: $PATCH" >&2; exit 1; }

prepare_android_subprojects_before_meson

[ -f "$MARKER" ] || { echo "patch marker missing: $MARKER" >&2; exit 1; }
grep -q 'ollmchat-android-bugs-v1' "$MARKER" ||
  { echo "patch marker missing ollmchat-android-bugs-v1 tag" >&2; exit 1; }
grep -q 'g_debug' "$MARKER" ||
  { echo "patch marker missing g_debug reference" >&2; exit 1; }
tail -1 "$MARKER" | grep -q '^}' ||
  { echo "patch marker file truncated (missing closing brace)" >&2; exit 1; }

# ImContext.java and gdkandroidpopup.c hunks must be present when patch applied.
grep -q 'syncEditableFromGtk' "$ROOT_DIR/subprojects/gtk/gdk/android/glue/java/org/gtk/android/ImContext.java" ||
  { echo "ImContext.java editable sync helper missing" >&2; exit 1; }

echo "R03 gtk-patch-marker: OK"
