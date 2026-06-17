#!/usr/bin/env bash
# R11 — Android TLS uses static gioopenssl (g_io_openssl_load), not asset modules.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/android/build-pixiewood-apk.sh"

grep -q 'ollmchat-android-runtime.tag' "$BUILD_SCRIPT" ||
  { echo "build-pixiewood-apk.sh must write ollmchat-android-runtime.tag" >&2; exit 1; }

grep -q 'ollmchat-android-bugs-v5' "$ROOT_DIR/scripts/android/verify-apk.sh" ||
  { echo "verify-apk.sh must check ollmchat-android-bugs-v5 tag" >&2; exit 1; }

grep -q 'g_io_openssl_load' "$ROOT_DIR/ollmapp/android/android-gio-tls.c" ||
  { echo "android-gio-tls.c must call g_io_openssl_load" >&2; exit 1; }

grep -q "dependency('gioopenssl')" "$ROOT_DIR/ollmapp/meson.build" ||
  { echo "ollmapp/meson.build must link dependency('gioopenssl') for android_poc" >&2; exit 1; }

echo "R11 gio-openssl-deps: OK"
