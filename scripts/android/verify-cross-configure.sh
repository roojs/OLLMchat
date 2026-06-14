#!/usr/bin/env bash
set -euo pipefail

# Run the Android cross Meson configure step locally without building the APK.
#
# This exercises the same path that fails in CI when a subproject dependency
# (json-glib, nghttp2, libsoup, …) is missing or misconfigured. Use it after
# changing android/pixiewood-wraps/* or meson.build before pushing.
#
# Prerequisites (same as the chat POC build):
#   - Android SDK + NDK under .android-sdk/ (scripts/android/install-sdk.sh)
#   - Host build tools: valac, ninja, perl, JDK 17, etc.
#
# Usage:
#   scripts/android/verify-cross-configure.sh
#   PIXIEWOOD_PHASE=configure scripts/android/build-chat-poc-apk.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PIXIEWOOD_MANIFEST="${PIXIEWOOD_MANIFEST:-$ROOT_DIR/android/pixiewood-chat-poc.xml}"
export PIXIEWOOD_PHASE=configure
exec "$ROOT_DIR/scripts/android/build-pixiewood-apk.sh"
