#!/usr/bin/env bash
# R03 — GTK subproject must be checked out (no android-bugs.patch; pixie chat uses prebuilt GTK).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR
unset PIXIEWOOD_USE_PIXIE
WRAP="$ROOT_DIR/android/pixiewood-wraps/gtk/gtk.wrap"

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"

grep -q 'gitlab.gnome.org/GNOME/gtk.git' "$WRAP" ||
  { echo "gtk.wrap must point at upstream GNOME GTK: $WRAP" >&2; exit 1; }

prepare_android_subprojects_before_meson

gtk_subproject_is_complete ||
  { echo "GTK subproject incomplete after prepare" >&2; exit 1; }
[ -f "$ROOT_DIR/subprojects/gtk/subprojects/graphene.wrap" ] ||
  { echo "GTK nested wraps missing" >&2; exit 1; }

echo "R03 gtk-subproject-ready: OK"