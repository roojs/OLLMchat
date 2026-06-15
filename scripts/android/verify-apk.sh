#!/usr/bin/env bash
set -euo pipefail

# Verify a built Android APK contains the chat libraries and GIO TLS modules.
#
# GIO modules cannot live under lib/ABI/gio/modules/ in an APK: Android only
# extracts top-level lib/ABI/*.so at install time. We ship TLS modules under
# assets/share/gio/modules/; GTK extracts assets to filesDir before main().
#
# Usage:
#   scripts/android/verify-apk.sh
#   scripts/android/verify-apk.sh path/to/app-arm64-v8a-debug.apk

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APK="${1:-$ROOT_DIR/.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk}"

if [ ! -f "$APK" ]; then
  echo "APK not found: $APK" >&2
  echo "Build first: scripts/android/build-chat-poc-apk.sh" >&2
  exit 1
fi

apk_list="$(mktemp)"
trap 'rm -f "$apk_list"' EXIT
unzip -l "$APK" > "$apk_list"

required=(
  lib/arm64-v8a/libollmchat-android-poc.so
  lib/arm64-v8a/libollmchat.so
  assets/share/gio/modules/libgioopenssl.so
)

for path in "${required[@]}"; do
  if ! grep -q "$path" "$apk_list"; then
    echo "Missing from APK: $path" >&2
    echo "Matching lib/arm64-v8a entries:" >&2
    grep 'lib/arm64-v8a/' "$apk_list" >&2 || true
    echo "Matching assets/gio entries:" >&2
    grep 'assets/.*gio' "$apk_list" >&2 || true
    exit 1
  fi
done

echo "APK verify OK: $APK"
