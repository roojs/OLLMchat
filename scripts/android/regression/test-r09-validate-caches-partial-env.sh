#!/usr/bin/env bash
# R09 — CI run 27590212384: validate-restored-caches.sh must tolerate unset
# CACHE_MATCHED_PIXIEWOOD_BUILD_KEY (R08 calls it with only subprojects env).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
export ROOT_DIR

output="$(
  PIXIEWOOD_DEPS_HASH="cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe" \
    CACHE_MATCHED_SUBPROJECTS_KEY="android-subprojects-v1-stable-deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef" \
    scripts/android/validate-restored-caches.sh 2>&1
)"

echo "$output" | grep -q 'pixiewood_compile_cache_usable=' ||
  { echo "validate-restored-caches.sh did not print usable status" >&2; exit 1; }

echo "R09 validate-caches-partial-env: OK"
