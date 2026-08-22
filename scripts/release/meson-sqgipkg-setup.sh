#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?mode required: linux}"
BUILD_DIR="${2:?build directory required}"

if [ "$MODE" != linux ]; then
  echo "Unknown mode: $MODE (expected linux)" >&2
  exit 1
fi

export PKG_CONFIG_SYSROOT_DIR="${SQGI_LINUX_SYSROOT:?SQGI_LINUX_SYSROOT is not set}"
export PKG_CONFIG_LIBDIR="${SQGI_LINUX_SYSROOT}/usr/lib/${SQGI_LINUX_TRIPLET}/pkgconfig:${SQGI_LINUX_SYSROOT}/usr/share/pkgconfig"
ARGS=(
  --prefix /usr
  --buildtype=release
  -Ddocs=false
  -Dexamples=false
  -Dtests=false
  -Dlocal_gguf=disabled
  -Dsysroot="$SQGI_LINUX_SYSROOT"
  -Dsysroot_triplet="$SQGI_LINUX_TRIPLET"
)
if [ -n "${SQGI_LINUX_MESON_CROSS_FILE:-}" ]; then
  ARGS+=(--cross-file "$SQGI_LINUX_MESON_CROSS_FILE")
fi

if [ -f "$BUILD_DIR/build.ninja" ]; then
  meson setup "$BUILD_DIR" --reconfigure "${ARGS[@]}"
else
  meson setup "$BUILD_DIR" --wipe "${ARGS[@]}" \
    || meson setup "$BUILD_DIR" "${ARGS[@]}"
fi
