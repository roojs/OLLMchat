#!/usr/bin/env bash
# R07 — Runtime APK checks: patched GTK in libgtk-4.so, TLS module, ImContext fix.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
APK="${1:-$ROOT_DIR/.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk}"

if [ ! -f "$APK" ]; then
  echo "R07 skipped (no APK at $APK)" >&2
  exit 0
fi

"$ROOT_DIR/scripts/android/verify-apk.sh" "$APK"
echo "R07 apk-runtime-patches: OK"
