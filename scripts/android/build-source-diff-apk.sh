#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PIXIEWOOD_MANIFEST="${PIXIEWOOD_MANIFEST:-$ROOT_DIR/android/pixiewood-source-diff.xml}"
export PIXIEWOOD_VERIFY_APK_SCRIPT="${PIXIEWOOD_VERIFY_APK_SCRIPT:-$ROOT_DIR/scripts/android/verify-source-diff-apk.sh}"
"$ROOT_DIR/scripts/android/build-pixiewood-apk.sh"
cp -a \
  "$ROOT_DIR/.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk" \
  "$ROOT_DIR/.pixiewood/oc-test-source-diff-arm64-v8a-debug.apk"
