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
  assets/share/gio/modules/libgioopenssl.so
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
    echo "Matching assets/gio entries:" >&2
    grep 'assets/.*gio' "$apk_list" >&2 || true
    echo "Matching assets/icons entries:" >&2
    grep 'assets/share/icons/' "$apk_list" >&2 || true
    exit 1
  fi
done

apk_extract="$(mktemp -d)"
trap 'rm -f "$apk_list"; rm -rf "$apk_extract"' EXIT
unzip -q "$APK" "lib/arm64-v8a/libgtk-4.so" "classes.dex" "assets/share/ollmchat-android-runtime.tag" -d "$apk_extract"

if ! strings "$apk_extract/lib/arm64-v8a/libgtk-4.so" | grep -q 'ollmchat-android-bugs-v2'; then
  echo "libgtk-4.so missing android-bugs patch tag (ollmchat-android-bugs-v2)." >&2
  echo "Pixiewood compile cache should have been discarded automatically; check pixiewood_prefix_has_patched_gtk." >&2
  exit 1
fi

if ! grep -q 'ollmchat-android-bugs-v2' "$apk_extract/assets/share/ollmchat-android-runtime.tag"; then
  echo "APK missing assets/share/ollmchat-android-runtime.tag (ollmchat-android-bugs-v2)." >&2
  exit 1
fi

apk_gio_modules="$(mktemp -d)"
trap 'rm -f "$apk_list"; rm -rf "$apk_extract" "$apk_gio_modules"' EXIT
unzip -q "$APK" "assets/share/gio/modules/*" -d "$apk_gio_modules"

if ! compgen -G "$apk_gio_modules/assets/share/gio/modules/libssl.so*" >/dev/null; then
  echo "APK missing libssl.so beside GIO TLS module (assets/share/gio/modules/)." >&2
  exit 1
fi

if ! compgen -G "$apk_gio_modules/assets/share/gio/modules/libcrypto.so*" >/dev/null; then
  echo "APK missing libcrypto.so beside GIO TLS module (assets/share/gio/modules/)." >&2
  exit 1
fi

if ! strings "$apk_extract/lib/arm64-v8a/libgtk-4.so" | grep -q 'ollmchat-android-popup-v2'; then
  echo "libgtk-4.so missing android popup patch tag (ollmchat-android-popup-v2)." >&2
  exit 1
fi

if ! strings "$apk_extract/lib/arm64-v8a/libgtk-4.so" | grep -q 'ollmchat-android-tls-v2'; then
  echo "libgtk-4.so missing android TLS preload patch tag (ollmchat-android-tls-v2)." >&2
  exit 1
fi

if ! strings "$apk_extract/classes.dex" | grep -q 'lambda\$deleteSurroundingText'; then
  echo "classes.dex missing patched ImContext deleteSurroundingText handler." >&2
  exit 1
fi

if ! strings "$apk_extract/classes.dex" | grep -q 'syncEditableFromGtk'; then
  echo "classes.dex missing ImContext.syncEditableFromGtk (hold-backspace IME sync)." >&2
  exit 1
fi

echo "APK verify OK: $APK"
