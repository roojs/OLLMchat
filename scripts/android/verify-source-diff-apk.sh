#!/usr/bin/env bash
set -euo pipefail

# Verify the source-diff smoke APK. Same checks as the chat APK, with
# liboc-test-source-diff.so instead of the chat application library.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APK="${1:-$ROOT_DIR/.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk}"
MANIFEST="$ROOT_DIR/android/icons/manifest"

if [ ! -f "$APK" ]; then
  echo "APK not found: $APK" >&2
  echo "Build first: scripts/android/build-source-diff-apk.sh" >&2
  exit 1
fi

apk_list="$(mktemp)"
trap 'rm -f "$apk_list"' EXIT
unzip -l "$APK" > "$apk_list"

required=(
  lib/arm64-v8a/liboc-test-source-diff.so
  lib/arm64-v8a/libollmchat.so
  assets/share/ssl/certs/ca-certificates.crt
  assets/share/ollmchat-android-runtime.tag
  assets/share/icons/Adwaita/index.theme
  assets/share/gtksourceview-5/language-specs/language2.rng
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
    exit 1
  fi
done

apk_extract="$(mktemp -d)"
trap 'rm -f "$apk_list"; rm -rf "$apk_extract"' EXIT
unzip -q "$APK" "lib/arm64-v8a/libgtk-4.so" "classes.dex" "assets/share/ollmchat-android-runtime.tag" -d "$apk_extract"

if ! grep -q 'ollmchat-android-bugs-v16' < <(strings "$apk_extract/lib/arm64-v8a/libgtk-4.so"); then
  echo "libgtk-4.so missing android-bugs patch tag (ollmchat-android-bugs-v16)." >&2
  exit 1
fi

if ! grep -q 'ollmchat-android-bugs-v16' "$apk_extract/assets/share/ollmchat-android-runtime.tag"; then
  echo "APK missing assets/share/ollmchat-android-runtime.tag (ollmchat-android-bugs-v16)." >&2
  exit 1
fi

aapt="$(ls -d "${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/build-tools/"*/aapt 2>/dev/null | sort -V | tail -1)"
if [ -z "$aapt" ]; then
  echo "aapt not found; cannot check the source-diff package id." >&2
  exit 1
fi
pkg="$("$aapt" dump badging "$APK" | sed -n "s/^package: name='\\([^']*\\)'.*/\\1/p")"
if [ "$pkg" != "org.roojs.ollmchat.sourcediff" ]; then
  echo "APK package is '$pkg', expected org.roojs.ollmchat.sourcediff." >&2
  echo "A chat package id would replace org.roojs.ollmchat.androidpoc on install." >&2
  exit 1
fi

echo "APK verify OK: $APK"
