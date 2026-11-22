#!/usr/bin/env bash
# Chat POC Android APK — PIXIEWOOD_USE_PIXIE=1 always. DO NOT WORK AROUND THIS
# (no local GTK checkout, patches, or C edits; see refuse-gtk-subproject.sh).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PIXIEWOOD_USE_PIXIE=1
export PIXIEWOOD_MANIFEST="${PIXIEWOOD_MANIFEST:-$ROOT_DIR/android/pixiewood-chat-poc.xml}"
export PIXIEWOOD_VERIFY_APK_SCRIPT="${PIXIEWOOD_VERIFY_APK_SCRIPT:-$ROOT_DIR/scripts/android/verify-apk.sh}"
export PIXIEWOOD_BUILD_DIR="${OLLMCHAT_PIXIEWOOD:-$ROOT_DIR/.pixiewood}/bin-${PIXIEWOOD_ARCH:-aarch64}"
"$ROOT_DIR/scripts/android/refuse-pixie-source-hack.sh"
exec "$ROOT_DIR/scripts/android/build-pixiewood-apk.sh"
