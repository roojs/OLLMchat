#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ROOT_DIR/.android-sdk}"
PIXIEWOOD_MANIFEST="${PIXIEWOOD_MANIFEST:-$ROOT_DIR/android/pixiewood-shell-poc.xml}"
PIXIEWOOD_DIR="${PIXIEWOOD_DIR:-$ROOT_DIR/.android-tools/gtk-android-builder}"
PIXIEWOOD_ARCH="${PIXIEWOOD_ARCH:-aarch64}"
PIXIEWOOD_BUILD_DIR="$ROOT_DIR/.pixiewood/bin-$PIXIEWOOD_ARCH"
PIXIEWOOD="${PIXIEWOOD:-}"
GTK_ANDROID_BUILDER_REVISION="${GTK_ANDROID_BUILDER_REVISION:-}"

read_gtk_android_builder_revision() {
  local revision_file="$ROOT_DIR/scripts/android/gtk-android-builder.revision"
  if [ -z "$GTK_ANDROID_BUILDER_REVISION" ] && [ -f "$revision_file" ]; then
    GTK_ANDROID_BUILDER_REVISION="$(
      grep -v '^[[:space:]]*#' "$revision_file" | grep -v '^[[:space:]]*$' | head -n1 | tr -d '[:space:]'
    )"
  fi
}

ensure_gtk_android_builder() {
  if [ -n "$PIXIEWOOD" ]; then
    return
  fi
  if command -v pixiewood >/dev/null 2>&1; then
    PIXIEWOOD="$(command -v pixiewood)"
    return
  fi

  read_gtk_android_builder_revision

  if [ ! -x "$PIXIEWOOD_DIR/pixiewood" ]; then
    rm -rf "$PIXIEWOOD_DIR"
    git clone https://github.com/sp1ritCS/gtk-android-builder.git "$PIXIEWOOD_DIR"
    if [ -n "$GTK_ANDROID_BUILDER_REVISION" ]; then
      git -C "$PIXIEWOOD_DIR" checkout "$GTK_ANDROID_BUILDER_REVISION"
    fi
  fi
  PIXIEWOOD="$PIXIEWOOD_DIR/pixiewood"
}

pixiewood_configure_options() {
  if [ ! -f "$PIXIEWOOD_MANIFEST" ]; then
    echo "Pixiewood manifest not found: $PIXIEWOOD_MANIFEST" >&2
    exit 1
  fi
  python3 - "$PIXIEWOOD_MANIFEST" <<'PY'
import sys
import xml.etree.ElementTree as ET

NS = {
    "pw": "https://sp1rit.arpa/pixiewood/",
}
tree = ET.parse(sys.argv[1])
root = tree.getroot()
for option in root.findall(".//pw:build/pw:configure-options/pw:option", NS):
    text = (option.text or "").strip()
    if text:
        print(text)
PY
}

reconfigure_pixiewood_build() {
  local meson="$1"
  shift
  local -a configure_options=("$@")

  "$meson" setup --reconfigure \
    --cross-file "$ROOT_DIR/.pixiewood/toolchain.cross" \
    --cross-file "$PIXIEWOOD_DIR/prepare/arch/$PIXIEWOOD_ARCH.cross" \
    --cross-file "$PIXIEWOOD_DIR/prepare/android.cross" \
    --buildtype debug \
    "${configure_options[@]}" \
    "$PIXIEWOOD_BUILD_DIR" \
    "$ROOT_DIR"
}

if [ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ] ||
   [ ! -d "$ANDROID_SDK_ROOT/ndk" ]; then
  "$ROOT_DIR/scripts/android/install-sdk.sh"
fi

ensure_gtk_android_builder

export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT
export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"
export CC_FOR_BUILD="${CC_FOR_BUILD:-gcc}"
export CXX_FOR_BUILD="${CXX_FOR_BUILD:-g++}"
MESON_FOR_ANDROID="$("$ROOT_DIR/scripts/android/ensure-meson.sh")"

mapfile -t PIXIEWOOD_CONFIGURE_OPTIONS < <(pixiewood_configure_options)

if [ -f "$PIXIEWOOD_BUILD_DIR/build.ninja" ] &&
   [ -f "$ROOT_DIR/.pixiewood/pixiewood.ini" ] &&
   [ -f "$ROOT_DIR/.pixiewood/toolchain.cross" ]; then
  echo "Reusing cached Pixiewood build tree; reconfiguring Meson only."
  reconfigure_pixiewood_build "$MESON_FOR_ANDROID" "${PIXIEWOOD_CONFIGURE_OPTIONS[@]}"
else
  "$PIXIEWOOD" -C "$ROOT_DIR" prepare \
    --sdk "$ANDROID_SDK_ROOT" \
    --meson "$MESON_FOR_ANDROID" \
    "$PIXIEWOOD_MANIFEST"
fi

"$PIXIEWOOD" -C "$ROOT_DIR" generate
"$PIXIEWOOD" -C "$ROOT_DIR" build

echo "Generated Android artifacts under $ROOT_DIR/.pixiewood/android/app/build/outputs"
