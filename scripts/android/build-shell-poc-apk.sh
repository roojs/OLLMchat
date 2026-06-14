#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ROOT_DIR/.android-sdk}"
PIXIEWOOD_MANIFEST="${PIXIEWOOD_MANIFEST:-$ROOT_DIR/android/pixiewood-shell-poc.xml}"
PIXIEWOOD_DIR="${PIXIEWOOD_DIR:-$ROOT_DIR/.android-tools/gtk-android-builder}"
PIXIEWOOD="${PIXIEWOOD:-}"

if [ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ] ||
   [ ! -d "$ANDROID_SDK_ROOT/ndk" ]; then
  "$ROOT_DIR/scripts/android/install-sdk.sh"
fi

if [ -z "$PIXIEWOOD" ]; then
  if command -v pixiewood >/dev/null 2>&1; then
    PIXIEWOOD="$(command -v pixiewood)"
  else
    if [ ! -x "$PIXIEWOOD_DIR/pixiewood" ]; then
      rm -rf "$PIXIEWOOD_DIR"
      git clone --depth 1 \
        https://github.com/sp1ritCS/gtk-android-builder.git \
        "$PIXIEWOOD_DIR"
    fi
    PIXIEWOOD="$PIXIEWOOD_DIR/pixiewood"
  fi
fi

export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT
export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"
export CC_FOR_BUILD="${CC_FOR_BUILD:-gcc}"
export CXX_FOR_BUILD="${CXX_FOR_BUILD:-g++}"
MESON_FOR_ANDROID="$("$ROOT_DIR/scripts/android/ensure-meson.sh")"

"$PIXIEWOOD" -C "$ROOT_DIR" prepare \
  --sdk "$ANDROID_SDK_ROOT" \
  --meson "$MESON_FOR_ANDROID" \
  "$PIXIEWOOD_MANIFEST"
"$PIXIEWOOD" -C "$ROOT_DIR" generate
"$PIXIEWOOD" -C "$ROOT_DIR" build

echo "Generated Android artifacts under $ROOT_DIR/.pixiewood/android/app/build/outputs"
