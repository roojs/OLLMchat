#!/usr/bin/env bash
# R04 — CI run 27586907940: Undefined constant 'toolchain' after partial compile cache restore.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR

# shellcheck source=pixiewood-cache.sh
source "$ROOT_DIR/scripts/android/pixiewood-cache.sh"

mkdir -p "$ROOT_DIR/.pixiewood"
touch "$ROOT_DIR/.pixiewood/pixiewood.ini"
cat > "$ROOT_DIR/.pixiewood/toolchain.cross" <<EOF
[constants]
toolchain='$ROOT_DIR/.android-sdk/ndk/DOES-NOT-EXIST/toolchains/llvm/prebuilt/linux-x86_64/'
EOF
mkdir -p "$ROOT_DIR/.pixiewood/bin-aarch64"
touch "$ROOT_DIR/.pixiewood/bin-aarch64/build.ninja"

ensure_pixiewood_compile_state_consistent

if [ -f "$ROOT_DIR/.pixiewood/toolchain.cross" ]; then
  echo "stale toolchain.cross should have been discarded" >&2
  exit 1
fi
if [ -f "$ROOT_DIR/.pixiewood/pixiewood.ini" ]; then
  echo "stale pixiewood.ini should have been discarded with bad toolchain" >&2
  exit 1
fi
if [ -d "$ROOT_DIR/.pixiewood/bin-aarch64" ]; then
  echo "stale bin-aarch64 should have been discarded with bad toolchain" >&2
  exit 1
fi

echo "R04 stale-toolchain-discard: OK"
