#!/usr/bin/env bash
# R11 — GIO TLS backend must preload OpenSSL from native lib dir.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/android/build-pixiewood-apk.sh"

grep -q 'ollmchat-android-runtime.tag' "$BUILD_SCRIPT" ||
  { echo "build-pixiewood-apk.sh must write ollmchat-android-runtime.tag" >&2; exit 1; }

grep -q 'ollmchat-android-bugs-v4' "$ROOT_DIR/scripts/android/verify-apk.sh" ||
  { echo "verify-apk.sh must check ollmchat-android-bugs-v4 tag" >&2; exit 1; }

grep -q 'RTLD_GLOBAL' "$ROOT_DIR/ollmapp/android/android-gio-tls.c" ||
  { echo "android-gio-tls.c must preload OpenSSL with RTLD_GLOBAL" >&2; exit 1; }

echo "R11 gio-openssl-deps: OK"
