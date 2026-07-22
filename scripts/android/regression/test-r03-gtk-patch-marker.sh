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
grep -q 'ollmchat-android-bugs-v11' "$MARKER" ||
  { echo "patch marker missing ollmchat-android-bugs-v11 tag" >&2; exit 1; }
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
grep -q 'in_long_press' "$ROOT_DIR/subprojects/gtk/gtk/gtktext.c" ||
  { echo "gtktext.c long-press paste bubble path missing" >&2; exit 1; }
grep -q 'Touch drag selects only after long-press' "$ROOT_DIR/subprojects/gtk/gtk/gtktextview.c" ||
  { echo "gtktextview.c touch long-press selection gate missing" >&2; exit 1; }
grep -q 'deleteBackwardOrSelection' "$ROOT_DIR/subprojects/gtk/gdk/android/glue/java/org/gtk/android/ImContext.java" ||
  { echo "ImContext.java selection-aware delete missing" >&2; exit 1; }
grep -q 'priv->in_long_press = FALSE' "$ROOT_DIR/subprojects/gtk/gtk/gtktextview.c" ||
  { echo "gtktextview.c sticky in_long_press clear missing" >&2; exit 1; }
# Comment text is "Composing span into GTK" (capital C) in android-bugs.patch.
grep -qi 'composing span into GTK' "$ROOT_DIR/subprojects/gtk/gdk/android/glue/java/org/gtk/android/ImContext.java" ||
  { echo "ImContext.java finishComposingText composing-span commit missing" >&2; exit 1; }
grep -q 'IME delete does not go through the key controller' "$ROOT_DIR/subprojects/gtk/gtk/gtktext.c" ||
  { echo "gtktext.c IME delete bubble hide missing" >&2; exit 1; }
grep -q 'Emitting drag-update in that case is wrong' "$ROOT_DIR/subprojects/gtk/gtk/gtkgesturedrag.c" ||
  { echo "gtkgesturedrag.c zero-offset drag-update skip missing" >&2; exit 1; }
grep -q 'gsk_gpu_device_make_current' "$ROOT_DIR/subprojects/gtk/gsk/gpu/gskgpudevice.c" ||
  { echo "gskgpudevice.c display-context atlas create missing" >&2; exit 1; }
grep -q 'gsk_gpu_device_make_current' "$ROOT_DIR/subprojects/gtk/gsk/gpu/gskgpuuploadop.c" ||
  { echo "gskgpuuploadop.c display-context atlas upload missing" >&2; exit 1; }
grep -q 'gdk_android_scan_gio_modules' "$ROOT_DIR/subprojects/gtk/gdk/android/gdkandroidruntime.c" &&
  { echo "gdkandroidruntime.c must not contain GDK TLS scan (app loads TLS)" >&2; exit 1; }

echo "R03 gtk-patch-marker: OK"
