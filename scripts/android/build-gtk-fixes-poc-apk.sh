#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PIXIEWOOD_MANIFEST="${PIXIEWOOD_MANIFEST:-$ROOT_DIR/android/pixiewood-gtk-fixes-poc.xml}"
export PIXIEWOOD_VERIFY_APK_SCRIPT="${PIXIEWOOD_VERIFY_APK_SCRIPT:-$ROOT_DIR/scripts/android/verify-gtk-fixes-apk.sh}"
exec "$ROOT_DIR/scripts/android/build-pixiewood-apk.sh"
