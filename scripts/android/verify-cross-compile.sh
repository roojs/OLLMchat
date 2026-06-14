#!/usr/bin/env bash
set -euo pipefail

# Compile the chat POC Vala libraries locally after cross-configure.
#
# Configure-only checks (verify-cross-configure.sh) miss Vala --pkg / vapi
# problems such as missing or duplicated gee-0.8, json-glib, libsoup, etc.
# Run this before pushing Android meson.build / vapi / wrap changes.
#
# Prerequisites: same as verify-cross-configure.sh (SDK, host valac/ninja, …).
#
# Usage:
#   scripts/android/verify-cross-compile.sh
#   scripts/android/verify-cross-compile.sh --with-app   # also build ollmchat-android-poc

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$ROOT_DIR/.pixiewood/bin-aarch64"
WITH_APP=false

for arg in "$@"; do
  case "$arg" in
    --with-app) WITH_APP=true ;;
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

if [ ! -f "$BUILD_DIR/build.ninja" ]; then
  echo "No cross build tree at $BUILD_DIR; running configure first." >&2
  "$ROOT_DIR/scripts/android/verify-cross-configure.sh"
fi

targets=(
  subprojects/glib-networking-2.80.1/tls/openssl/libgioopenssl.so
  libocmarkdown/libocmarkdown.so
  libocmarkdown/ocmarkdown.vapi
  libocsqlite/libocsqlite.so
  libocsqlite/ocsqlite.vapi
  libollamaweb/libollamaweb.so
  libollamaweb/ollamaweb.vapi
  libollmchat/libollmchat.so
)

if [ "$WITH_APP" = true ]; then
  targets+=(
    ollmapp/libollmchat-android-poc.so
    ollmchat-android-poc
  )
fi

echo "Compiling Android cross targets: ${targets[*]}" >&2
ninja -C "$BUILD_DIR" "${targets[@]}"
echo "Android cross compile smoke test succeeded." >&2
