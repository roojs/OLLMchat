#!/usr/bin/env bash
set -euo pipefail

# Meson front-end for Pixiewood Android cross builds.
#
# Pixiewood invokes meson setup without our android/pixiewood-extra.cross
# and with host g-ir-scanner on PATH. That makes json-glib/libsoup subprojects
# try to generate GIR for the Android host and fail. This wrapper:
#   - shadows g-ir-scanner on PATH
#   - injects android/pixiewood-extra.cross on meson setup

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXTRA_CROSS="$ROOT_DIR/android/pixiewood-extra.cross"
REAL_MESON="$("$ROOT_DIR/scripts/android/ensure-meson.sh")"
# shellcheck source=android-meson-path.sh
source "$ROOT_DIR/scripts/android/android-meson-path.sh"

inject_extra_cross_file() {
  local arg already=false
  for arg in "$@"; do
    if [ "$arg" = "$EXTRA_CROSS" ]; then
      already=true
      break
    fi
  done
  if [ "$already" = true ] || [ ! -f "$EXTRA_CROSS" ]; then
    printf '%s\n' "$@"
    return
  fi
  printf '%s\n' "$@" --cross-file "$EXTRA_CROSS"
}

if [ "$#" -eq 0 ]; then
  exec env PATH="$(android_meson_path)" "$REAL_MESON"
fi

if [ "$1" = "setup" ]; then
  mapfile -t meson_args < <(inject_extra_cross_file "$@")
  exec env PATH="$(android_meson_path)" "$REAL_MESON" "${meson_args[@]}"
fi

exec env PATH="$(android_meson_path)" "$REAL_MESON" "$@"
