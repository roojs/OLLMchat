#!/usr/bin/env bash
set -euo pipefail

# Verify the GTK fixes harness APK (minimal TLS/IME/paste test app).
#
# Usage:
#   scripts/android/verify-gtk-fixes-apk.sh
#   scripts/android/verify-gtk-fixes-apk.sh path/to/app-arm64-v8a-debug.apk

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APK="${1:-$ROOT_DIR/.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk}"

if [ ! -f "$APK" ]; then
  echo "APK not found: $APK" >&2
  echo "Build first: scripts/android/build-gtk-fixes-poc-apk.sh" >&2
  exit 1
fi

apk_list="$(mktemp)"
trap 'rm -f "$apk_list"' EXIT
unzip -l "$APK" > "$apk_list"

required=(
  lib/arm64-v8a/libollmchat-android-gtk-fixes-poc.so
  assets/share/gio/modules/libgioopenssl.so
  assets/share/ssl/certs/ca-certificates.crt
  assets/share/ollmchat-android-runtime.tag
)

for path in "${required[@]}"; do
  if ! grep -q "$path" "$apk_list"; then
    echo "Missing from APK: $path" >&2
    grep 'lib/arm64-v8a/' "$apk_list" >&2 || true
    exit 1
  fi
done

apk_extract="$(mktemp -d)"
trap 'rm -f "$apk_list"; rm -rf "$apk_extract"' EXIT
unzip -q "$APK" \
  "lib/arm64-v8a/libgtk-4.so" \
  "classes.dex" \
  "assets/share/ollmchat-android-runtime.tag" \
  -d "$apk_extract"

for tag in ollmchat-android-bugs-v4 ollmchat-android-popup-v4 ollmchat-android-tls-v4; do
  if ! grep -q "$tag" < <(strings "$apk_extract/lib/arm64-v8a/libgtk-4.so"); then
    echo "libgtk-4.so missing patch tag: $tag" >&2
    exit 1
  fi
done

if ! grep -q 'ollmchat-android-bugs-v4' "$apk_extract/assets/share/ollmchat-android-runtime.tag"; then
  echo "APK missing ollmchat-android-bugs-v4 runtime tag." >&2
  exit 1
fi

apk_gio_modules="$(mktemp -d)"
trap 'rm -f "$apk_list"; rm -rf "$apk_extract" "$apk_gio_modules"' EXIT
unzip -q "$APK" "assets/share/gio/modules/*" -d "$apk_gio_modules"

if compgen -G "$apk_gio_modules/assets/share/gio/modules/libssl.so*" >/dev/null; then
  echo "APK must not ship libssl.so under assets/share/gio/modules/." >&2
  exit 1
fi

if compgen -G "$apk_gio_modules/assets/share/gio/modules/libcrypto.so*" >/dev/null; then
  echo "APK must not ship libcrypto.so under assets/share/gio/modules/." >&2
  exit 1
fi

if ! grep -q 'lambda\$deleteSurroundingText' < <(strings "$apk_extract/classes.dex"); then
  echo "classes.dex missing ImContext deleteSurroundingText handler." >&2
  exit 1
fi

echo "GTK fixes APK verify OK: $APK"
