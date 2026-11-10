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

pixie_extra_cross() {
  local stripped
  if [ -z "${PIXIEWOOD_PIXIE:-}" ] || [ ! -f "$EXTRA_CROSS" ]; then
    printf '%s\n' "$EXTRA_CROSS"
    return
  fi
  stripped="$(mktemp)"
  grep -v 'glib-mkenums' "$EXTRA_CROSS" > "$stripped"
  printf '%s\n' "$stripped"
}

inject_extra_cross_file() {
  local arg extra pixie_cross="" replaced=false
  local -a out=()
  extra="$(pixie_extra_cross)"
  if [ -n "${PIXIEWOOD_PIXIE:-}" ] && [ -f "$PIXIEWOOD_PIXIE/share/pixiewood/pixie.cross" ]; then
    pixie_cross="$PIXIEWOOD_PIXIE/share/pixiewood/pixie.cross"
  fi
  # The caller already passes pixiewood-extra.cross. That used to count as
  # "already injected", so the pixie sysroot cross file was never added.
  while [ "$#" -gt 0 ]; do
    arg="$1"
    shift
    if [ "$arg" = "--cross-file" ] && [ "$#" -gt 0 ]; then
      if [ -n "$pixie_cross" ] && [ "$1" = "$EXTRA_CROSS" ] && [ "$extra" != "$EXTRA_CROSS" ]; then
        out+=(--cross-file "$extra")
        replaced=true
        shift
        continue
      fi
      if [ -n "$pixie_cross" ] && [ "$1" = "$pixie_cross" ]; then
        pixie_cross=""
      fi
      out+=(--cross-file "$1")
      shift
      continue
    fi
    out+=("$arg")
  done
  if [ -z "$pixie_cross" ]; then
    if [ -f "$EXTRA_CROSS" ]; then
      local has=false
      for arg in "${out[@]}"; do
        if [ "$arg" = "$EXTRA_CROSS" ]; then
          has=true
        fi
      done
      if [ "$has" = false ]; then
        out+=(--cross-file "$EXTRA_CROSS")
      fi
    fi
  elif [ "$replaced" = false ] && [ -f "$extra" ]; then
    local has_extra=false
    for arg in "${out[@]}"; do
      if [ "$arg" = "$extra" ]; then
        has_extra=true
      fi
    done
    if [ "$has_extra" = false ]; then
      out+=(--cross-file "$extra")
    fi
  fi
  if [ -n "$pixie_cross" ]; then
    out+=(--cross-file "$pixie_cross")
  fi
  printf '%s\n' "${out[@]}"
}

if [ "$#" -eq 0 ]; then
  exec env PATH="$(android_meson_path)" "$REAL_MESON"
fi

if [ "$1" = "setup" ]; then
  mapfile -t meson_args < <(inject_extra_cross_file "$@")
  exec env PATH="$(android_meson_path)" "$REAL_MESON" "${meson_args[@]}"
fi

exec env PATH="$(android_meson_path)" "$REAL_MESON" "$@"
