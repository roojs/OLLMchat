#!/usr/bin/env bash
set -euo pipefail

# Verify a built Android APK contains the chat libraries and bundled CA trust.
#
# TLS uses static gioopenssl (g_io_openssl_load) linked into the app — not
# assets/share/gio/modules/libgioopenssl.so.
#
# Usage:
#   scripts/android/verify-apk.sh
#   scripts/android/verify-apk.sh path/to/app-arm64-v8a-debug.apk

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APK="${1:-$ROOT_DIR/.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk}"
MANIFEST="$ROOT_DIR/android/icons/manifest"

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
  assets/share/ssl/certs/ca-certificates.crt
  assets/share/ollmchat-android-runtime.tag
  assets/share/icons/Adwaita/index.theme
)

if [ -f "$MANIFEST" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [ -z "$line" ] && continue
    dest_relpath="${line%%$'\t'*}"
    required+=("assets/share/icons/Adwaita/$dest_relpath")
  done < "$MANIFEST"
fi

for path in "${required[@]}"; do
  if ! grep -q "$path" "$apk_list"; then
    echo "Missing from APK: $path" >&2
    echo "Matching lib/arm64-v8a entries:" >&2
    grep 'lib/arm64-v8a/' "$apk_list" >&2 || true
    echo "Matching assets/icons entries:" >&2
    grep 'assets/share/icons/' "$apk_list" >&2 || true
    exit 1
  fi
done

apk_extract="$(mktemp -d)"
trap 'rm -f "$apk_list"; rm -rf "$apk_extract"' EXIT
unzip -q "$APK" "lib/arm64-v8a/libgtk-4.so" "classes.dex" "assets/share/ollmchat-android-runtime.tag" -d "$apk_extract"

if ! grep -q 'ollmchat-android-bugs-v11' < <(strings "$apk_extract/lib/arm64-v8a/libgtk-4.so"); then
  echo "libgtk-4.so missing android-bugs patch tag (ollmchat-android-bugs-v11)." >&2
  echo "Pixiewood compile cache should have been discarded automatically; check pixiewood_prefix_has_patched_gtk." >&2
  exit 1
fi

if ! grep -q 'ollmchat-android-bugs-v11' "$apk_extract/assets/share/ollmchat-android-runtime.tag"; then
  echo "APK missing assets/share/ollmchat-android-runtime.tag (ollmchat-android-bugs-v11)." >&2
  exit 1
fi

if grep -q 'assets/share/gio/modules/libgioopenssl.so' "$apk_list"; then
  echo "APK must not ship assets/share/gio/modules/libgioopenssl.so (static gioopenssl)." >&2
  exit 1
fi

if ! grep -q 'ollmchat-android-popup-v5' < <(strings "$apk_extract/lib/arm64-v8a/libgtk-4.so"); then
  echo "libgtk-4.so missing android popup patch tag (ollmchat-android-popup-v5)." >&2
  exit 1
fi

if ! grep -q 'lambda\$deleteSurroundingText' < <(strings "$apk_extract/classes.dex"); then
  echo "classes.dex missing patched ImContext deleteSurroundingText handler." >&2
  exit 1
fi

if ! grep -q 'syncEditableFromGtk' < <(strings "$apk_extract/classes.dex"); then
  echo "classes.dex missing ImContext.syncEditableFromGtk (hold-backspace IME sync)." >&2
  exit 1
fi

echo "APK verify OK: $APK"
