#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APK="${1:-$ROOT_DIR/.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk}"
PKG=org.roojs.ollmchat.gtkfixespoc

if [ ! -f "$APK" ]; then
  echo "APK not found: $APK" >&2
  echo "Build first: scripts/android/build-gtk-fixes-poc-apk.sh" >&2
  exit 1
fi

adb install -r -d "$APK"
adb shell am start -n "$PKG/org.gtk.android.ToplevelActivity"
echo "Installed and launched $PKG"
