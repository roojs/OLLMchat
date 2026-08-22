#!/usr/bin/env bash
set -euo pipefail

# Compile the Android chat POC meson target locally after cross-configure.
#
# Configure-only checks (verify-cross-configure.sh) miss Vala --pkg / vapi
# problems such as missing or duplicated gee-0.8, json-glib, libsoup, etc.
# A library subset also hid libocrpc.vapi and libocmarkdowngtk (gtksourceview-5).
# Always compile ollmchat-android-poc so ninja pulls every Android meson lib.
# Run this before pushing Android meson.build / vapi / wrap / apt changes.
#
# Prerequisites: same as verify-cross-configure.sh (SDK, host valac/ninja, …).
#
# Usage:
#   scripts/android/verify-cross-compile.sh
#   scripts/android/verify-cross-compile.sh --with-app   # same as default (kept)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$ROOT_DIR/.pixiewood/bin-aarch64"

for arg in "$@"; do
  case "$arg" in
    --with-app) ;;
    -h|--help)
      sed -n '1,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

export PIXIEWOOD_MANIFEST="${PIXIEWOOD_MANIFEST:-$ROOT_DIR/android/pixiewood-chat-poc.xml}"

# Ninja's regenerate rule can invoke meson.real 1.7.0 (no PYTHONPATH). That
# dies on fontconfig 2.18.1 (`meson_version >= 1.11`). Always configure with
# meson-for-pixiewood (1.11+) so build.ninja matches current meson.build.
echo "Reconfiguring Android cross build before compile." >&2
"$ROOT_DIR/scripts/android/verify-cross-configure.sh"

# ollmchat-android-poc depends on every Android meson library (libocrpc,
# libocmarkdowngtk, libollmchatgtk, libocwebkit, …). Listing a subset here
# let CI "Build chat APK" fail on targets this script never compiled.
targets=(
  subprojects/glib-networking-2.80.1/tls/openssl/libgioopenssl.so
  libocrpc/libocrpc.so
  libocrpc/ocrpc.vapi
  libocmarkdown/libocmarkdown.so
  libocmarkdown/ocmarkdown.vapi
  libocsqlite/libocsqlite.so
  libocsqlite/ocsqlite.vapi
  libollamaweb/libollamaweb.so
  libollamaweb/ollamaweb.vapi
  libollmchat/libollmchat.so
  liboccoder/liboccoder.so
  liboccoder/occoder.vapi
  libocmarkdowngtk/libocmarkdowngtk.so
  libollmchatgtk/libollmchatgtk.so
  libocwebkit/libocwebkit.so
  ollmapp/libollmchat-android-poc.so
  ollmchat-android-poc
)

echo "Compiling Android cross targets: ${targets[*]}" >&2
ninja -C "$BUILD_DIR" "${targets[@]}"
echo "Android cross compile smoke test succeeded." >&2
