#!/usr/bin/env bash
# CI preflight: simulate restored caches and run setup + configure before GitHub.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
export ROOT_DIR
export CI=true
export PIXIEWOOD_MANIFEST="$ROOT_DIR/android/pixiewood-chat-poc.xml"
export PIXIEWOOD_BUILD_DIR="$ROOT_DIR/.pixiewood/bin-aarch64"

# shellcheck source=gtk-subproject.sh
source "$ROOT_DIR/scripts/android/gtk-subproject.sh"
# shellcheck source=pixiewood-cache.sh
source "$ROOT_DIR/scripts/android/pixiewood-cache.sh"

install_wraps() {
  local extra="$ROOT_DIR/android/pixiewood-wraps"
  mkdir -p "$ROOT_DIR/subprojects"
  local dep_dir wrap
  for dep_dir in "$extra"/*/; do
    for wrap in "$dep_dir"/*.wrap; do
      [ -f "$wrap" ] && cp -a "$wrap" "$ROOT_DIR/subprojects/"
    done
  done
}

simulate_restored_caches() {
  install_wraps

  # Broken subprojects cache (missing nested gtk wraps).
  rm -rf "$ROOT_DIR/subprojects/gtk"
  mkdir -p "$ROOT_DIR/subprojects/gtk"
  echo '# broken stub' > "$ROOT_DIR/subprojects/gtk/meson.build"

  # Partial compile cache: ini + toolchain.cross without usable build tree.
  mkdir -p "$ROOT_DIR/.pixiewood"
  touch "$ROOT_DIR/.pixiewood/pixiewood.ini"
  cat > "$ROOT_DIR/.pixiewood/toolchain.cross" <<EOF
[constants]
toolchain='$ROOT_DIR/.android-sdk/ndk/DOES-NOT-EXIST/toolchains/llvm/prebuilt/linux-x86_64/'
EOF
  rm -rf "$ROOT_DIR/.pixiewood/bin-aarch64"
}

assert_gtk_ready() {
  gtk_subproject_is_complete ||
    { echo "GTK subproject incomplete after repair." >&2; exit 1; }
  [ -f "$(gtk_subproject_patch_marker)" ] ||
    { echo "GTK patch marker missing." >&2; exit 1; }
}

assert_toolchain_ready() {
  pixiewood_toolchain_cross_valid ||
    { echo "toolchain.cross still invalid after setup." >&2; exit 1; }
}

echo "=== CI preflight: simulate restored caches ==="
simulate_restored_caches

echo "=== CI preflight: setup phase ==="
export PIXIEWOOD_SKIP_SUBPROJECTS_DOWNLOAD=1
PIXIEWOOD_PHASE=setup "$ROOT_DIR/scripts/android/build-pixiewood-apk.sh"
assert_gtk_ready
assert_toolchain_ready

echo "=== CI preflight: configure phase ==="
export PIXIEWOOD_SKIP_SUBPROJECTS_DOWNLOAD=1
export PIXIEWOOD_SKIP_RECONFIGURE=1
PIXIEWOOD_PHASE=configure "$ROOT_DIR/scripts/android/build-pixiewood-apk.sh"
assert_toolchain_ready
[ -f "$PIXIEWOOD_BUILD_DIR/build.ninja" ] ||
  { echo "build.ninja missing after configure." >&2; exit 1; }

echo "android-ci-preflight: OK"
