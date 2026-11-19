#!/usr/bin/env bash
# Stop an Android chat build that compiles the GTK stack from source,
# or that still contains a local GLib scheduler hack.
set -euo pipefail

ROOT_DIR="${PIXIEWOOD_CHECK_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PIXIEWOOD_BUILD_DIR="${PIXIEWOOD_BUILD_DIR:-$ROOT_DIR/.pixiewood/bin-aarch64}"
PIXIEWOOD_USE_PIXIE="${PIXIEWOOD_USE_PIXIE:-}"

stop_hack() {
  echo "Stop. A hack has been done that is not allowed." >&2
  echo "$1" >&2
  echo "The chat APK uses the published pixie libraries. It does not compile that stack from source and it does not patch GLib." >&2
  exit 1
}

if [ "$PIXIEWOOD_USE_PIXIE" != 1 ]; then
  stop_hack "PIXIEWOOD_USE_PIXIE is not 1, so this build would compile the GTK stack from source."
fi

if [ -f "$ROOT_DIR/ollmapp/android/android-sched.c" ]; then
  stop_hack "ollmapp/android/android-sched.c is present."
fi
if [ -f "$ROOT_DIR/android/pixiewood-wraps/glib/packagefiles/glib/sched-inherit.patch" ]; then
  stop_hack "android/pixiewood-wraps/glib/packagefiles/glib/sched-inherit.patch is present."
fi
wrap="$ROOT_DIR/android/pixiewood-wraps/glib/glib.wrap"
if [ -f "$wrap" ] && grep -q 'sched-inherit.patch' "$wrap"; then
  stop_hack "glib.wrap lists sched-inherit.patch."
fi
gthread="$ROOT_DIR/subprojects/glib/glib/gthread-posix.c"
if [ -f "$gthread" ] && grep -q 'PTHREAD_EXPLICIT_SCHED' "$gthread"; then
  stop_hack "subprojects/glib/glib/gthread-posix.c forces a scheduler. That change belongs in the pixie GLib package."
fi

log="$PIXIEWOOD_BUILD_DIR/meson-logs/meson-log.txt"
if [ -f "$log" ] && ! grep -q 'pkg-config-wrapper' "$log"; then
  stop_hack "The Meson build directory was configured without the pixie sysroot ($PIXIEWOOD_BUILD_DIR)."
fi

ninja="$PIXIEWOOD_BUILD_DIR/build.ninja"
if [ -f "$ninja" ] && grep -E -q '^build .*subprojects/(glib|gtk)/' "$ninja"; then
  stop_hack "The Meson build compiles glib or gtk from subprojects/."
fi

manifest="$(dirname "$PIXIEWOOD_BUILD_DIR")/pixie/share/pixiewood/MANIFEST.json"
if [ "${PIXIEWOOD_CHECK_WRAPS:-}" = 1 ] && [ -f "$manifest" ]; then
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -f "$ROOT_DIR/subprojects/$name.wrap" ]; then
      stop_hack "subprojects/$name.wrap is still installed, so Meson can compile $name from source."
    fi
  done < <(jq -r '.provided_dependencies[]' "$manifest")
fi
