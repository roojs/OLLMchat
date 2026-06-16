#!/usr/bin/env bash
# R11 — OpenSSL runtimes must ship beside libgioopenssl.so in APK assets.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/android/build-pixiewood-apk.sh"

grep -q 'libssl.so' "$BUILD_SCRIPT" ||
  { echo "build-pixiewood-apk.sh must copy libssl beside GIO modules" >&2; exit 1; }
grep -q 'libcrypto.so' "$BUILD_SCRIPT" ||
  { echo "build-pixiewood-apk.sh must copy libcrypto beside GIO modules" >&2; exit 1; }
grep -q 'ollmchat-android-runtime.tag' "$BUILD_SCRIPT" ||
  { echo "build-pixiewood-apk.sh must write ollmchat-android-runtime.tag" >&2; exit 1; }

grep -q 'libssl.so' "$ROOT_DIR/scripts/android/verify-apk.sh" ||
  { echo "verify-apk.sh must require libssl in assets/share/gio/modules/" >&2; exit 1; }
grep -q 'ollmchat-android-bugs-v2' "$ROOT_DIR/scripts/android/verify-apk.sh" ||
  { echo "verify-apk.sh must check ollmchat-android-bugs-v2 tag" >&2; exit 1; }

grep -q 'RTLD_GLOBAL' "$ROOT_DIR/ollmapp/android/android-gio-tls.c" ||
  { echo "android-gio-tls.c must preload OpenSSL with RTLD_GLOBAL" >&2; exit 1; }

echo "R11 gio-openssl-deps: OK"
