#!/usr/bin/env bash
# R03 — android-bugs.patch must apply; marker file proves patch is in the tree.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR
PATCH="$ROOT_DIR/android/pixiewood-wraps/gtk/android-bugs.patch"
MARKER="$ROOT_DIR/subprojects/gtk/gdk/android/gdkandroidollmchatpatch.c"
WRAP="$ROOT_DIR/android/pixiewood-wraps/gtk/gtk.wrap"

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

[ -f "$PATCH" ] || { echo "missing patch: $PATCH" >&2; exit 1; }

grep -q 'gitlab.gnome.org/GNOME/gtk.git' "$WRAP" ||
  { echo "gtk.wrap must point at upstream GNOME GTK: $WRAP" >&2; exit 1; }

prepare_android_subprojects_before_meson

[ -f "$MARKER" ] || { echo "patch marker missing: $MARKER" >&2; exit 1; }
grep -q 'ollmchat-android-bugs-v12' "$MARKER" ||
  { echo "patch marker missing ollmchat-android-bugs-v12 tag" >&2; exit 1; }
grep -q 'g_debug' "$MARKER" ||
  { echo "patch marker missing g_debug reference" >&2; exit 1; }
grep -q '#include <glib.h>' "$MARKER" ||
  { echo "patch marker missing glib.h include for g_debug" >&2; exit 1; }
tail -1 "$MARKER" | grep -q '^}' ||
  { echo "patch marker file truncated (missing closing brace)" >&2; exit 1; }

grep -q 'syncEditableFromGtk' "$ROOT_DIR/subprojects/gtk/gdk/android/glue/java/org/gtk/android/ImContext.java" ||
  { echo "ImContext.java editable sync helper missing" >&2; exit 1; }
grep -q 'sendKeyEvent' "$ROOT_DIR/subprojects/gtk/gdk/android/glue/java/org/gtk/android/ImContext.java" ||
  { echo "ImContext.java hold-delete sendKeyEvent path missing" >&2; exit 1; }
grep -q 'notifyGtkTextChanged' "$ROOT_DIR/subprojects/gtk/gdk/android/glue/java/org/gtk/android/ImContext.java" ||
  { echo "ImContext.java notifyGtkTextChanged missing" >&2; exit 1; }
grep -q 'runThenPushToGtk' "$ROOT_DIR/subprojects/gtk/gdk/android/glue/java/org/gtk/android/ImContext.java" ||
  { echo "ImContext.java runThenPushToGtk missing" >&2; exit 1; }
grep -q 'deleteSelectionIfAny' "$ROOT_DIR/subprojects/gtk/gdk/android/glue/java/org/gtk/android/ImContext.java" ||
  { echo "ImContext.java selection-aware delete missing" >&2; exit 1; }
grep -q 'gtk_text_touch_new' "$ROOT_DIR/subprojects/gtk/gtk/gtktext.c" ||
  { echo "gtktext.c GtkTextTouch wiring missing" >&2; exit 1; }
grep -q 'gtk_text_touch_new' "$ROOT_DIR/subprojects/gtk/gtk/gtktextview.c" ||
  { echo "gtktextview.c GtkTextTouch wiring missing" >&2; exit 1; }
grep -q 'gtktexttouch.c' "$ROOT_DIR/subprojects/gtk/gtk/meson.build" ||
  { echo "gtk/meson.build gtktexttouch.c missing" >&2; exit 1; }
grep -q 'drag-update is for actual movement, not a stationary press' "$ROOT_DIR/subprojects/gtk/gtk/gtkgesturedrag.c" ||
  { echo "gtkgesturedrag.c zero-offset drag-update skip missing" >&2; exit 1; }
grep -q 'gsk_gpu_device_make_current' "$ROOT_DIR/subprojects/gtk/gsk/gpu/gskgpudevice.c" ||
  { echo "gskgpudevice.c display-context atlas create missing" >&2; exit 1; }
grep -q 'gsk_gpu_device_make_current' "$ROOT_DIR/subprojects/gtk/gsk/gpu/gskgpuuploadop.c" ||
  { echo "gskgpuuploadop.c display-context atlas upload missing" >&2; exit 1; }
grep -q 'commit_in_progress' "$ROOT_DIR/subprojects/gtk/gdk/android/gdkandroidclipboard-private.h" ||
  { echo "clipboard commit_in_progress guard missing" >&2; exit 1; }
grep -q 'gdk_android_scan_gio_modules' "$ROOT_DIR/subprojects/gtk/gdk/android/gdkandroidruntime.c" &&
  { echo "gdkandroidruntime.c must not contain GDK TLS scan (app loads TLS)" >&2; exit 1; }

echo "R03 gtk-patch-marker: OK"
