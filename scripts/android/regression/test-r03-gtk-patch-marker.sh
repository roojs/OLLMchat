#!/usr/bin/env bash
# R03 — roojs/gtk fork checkout must include OLLMchat Android runtime fixes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR
MARKER="$ROOT_DIR/subprojects/gtk/gdk/android/gdkandroidollmchatpatch.c"
WRAP="$ROOT_DIR/android/pixiewood-wraps/gtk/gtk.wrap"

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

grep -q 'github.com/roojs/gtk.git' "$WRAP" ||
  { echo "gtk.wrap must point at roojs/gtk fork: $WRAP" >&2; exit 1; }

prepare_android_subprojects_before_meson

gtk_subproject_matches_wrap_revision ||
  { echo "subprojects/gtk revision does not match gtk.wrap" >&2; exit 1; }

[ -f "$MARKER" ] || { echo "fork marker missing: $MARKER" >&2; exit 1; }
grep -q 'ollmchat-android-bugs-v4' "$MARKER" ||
  { echo "fork marker missing ollmchat-android-bugs-v4 tag" >&2; exit 1; }
grep -q 'ollmchat-android-popup-v4' "$MARKER" ||
  { echo "fork marker missing ollmchat-android-popup-v4 tag" >&2; exit 1; }
grep -q 'ollmchat-android-tls-v4' "$MARKER" ||
  { echo "fork marker missing ollmchat-android-tls-v4 tag" >&2; exit 1; }
grep -q 'g_debug' "$MARKER" ||
  { echo "fork marker missing g_debug reference" >&2; exit 1; }
grep -q '#include <glib.h>' "$MARKER" ||
  { echo "fork marker missing glib.h include for g_debug" >&2; exit 1; }
tail -1 "$MARKER" | grep -q '^}' ||
  { echo "fork marker file truncated (missing closing brace)" >&2; exit 1; }

grep -q 'syncEditableFromGtk' "$ROOT_DIR/subprojects/gtk/gdk/android/glue/java/org/gtk/android/ImContext.java" ||
  { echo "ImContext.java editable sync helper missing" >&2; exit 1; }

echo "R03 gtk-fork-marker: OK"
