#!/usr/bin/env bash
# CI preflight: simulate restored caches and run setup + configure before GitHub.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
export ROOT_DIR
export CI=true
export PIXIEWOOD_USE_PIXIE=1
export PIXIEWOOD_MANIFEST="$ROOT_DIR/android/pixiewood-chat-poc.xml"
export PIXIEWOOD_BUILD_DIR="$ROOT_DIR/.pixiewood/bin-aarch64"

# shellcheck source=pixiewood-cache.sh
source "$ROOT_DIR/scripts/android/pixiewood-cache.sh"

simulate_restored_caches() {
  # Partial compile cache: ini + toolchain.cross without usable build tree.
  mkdir -p "$ROOT_DIR/.pixiewood"
  touch "$ROOT_DIR/.pixiewood/pixiewood.ini"
  cat > "$ROOT_DIR/.pixiewood/toolchain.cross" <<EOF
[constants]
toolchain='$ROOT_DIR/.android-sdk/ndk/DOES-NOT-EXIST/toolchains/llvm/prebuilt/linux-x86_64/'
EOF
  rm -rf "$ROOT_DIR/.pixiewood/bin-aarch64"
}

assert_toolchain_ready() {
  pixiewood_toolchain_cross_valid ||
    { echo "toolchain.cross still invalid after setup." >&2; exit 1; }
}

assert_no_gtk_source_trees() {
  [ ! -d "$ROOT_DIR/subprojects/gtk" ] ||
    { echo "subprojects/gtk present; pixie build must not check out GTK." >&2; exit 1; }
  [ ! -d "$ROOT_DIR/.pixiewood/gtk-subproject-bootstrap" ] ||
    { echo "gtk-subproject-bootstrap present; pixie build must not use it." >&2; exit 1; }
}

echo "=== CI preflight: simulate restored caches ==="
simulate_restored_caches

echo "=== CI preflight: setup phase ==="
export PIXIEWOOD_SKIP_SUBPROJECTS_DOWNLOAD=1
PIXIEWOOD_PHASE=setup "$ROOT_DIR/scripts/android/build-chat-poc-apk.sh"
assert_no_gtk_source_trees
assert_toolchain_ready

echo "=== CI preflight: configure phase ==="
export PIXIEWOOD_SKIP_SUBPROJECTS_DOWNLOAD=1
export PIXIEWOOD_SKIP_RECONFIGURE=1
PIXIEWOOD_PHASE=configure "$ROOT_DIR/scripts/android/build-chat-poc-apk.sh"
assert_no_gtk_source_trees
assert_toolchain_ready
[ -f "$PIXIEWOOD_BUILD_DIR/build.ninja" ] ||
  { echo "build.ninja missing after configure." >&2; exit 1; }

echo "android-ci-preflight: OK"