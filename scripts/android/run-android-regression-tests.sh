#!/usr/bin/env bash
# Run Android build regression tests before pushing to GitHub.
#
# Usage:
#   scripts/android/run-android-regression-tests.sh           # fast tests (~30s)
#   scripts/android/run-android-regression-tests.sh --full    # fast + CI preflight (~2-5 min)
#
# See docs/android-build-regression-tests.md for failure → test mapping.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGRESSION_DIR="$ROOT_DIR/scripts/android/regression"
MODE="${1:-}"

run_test() {
  local script="$1"
  echo ""
  echo "======== $(basename "$script") ========"
  "$script"
}

FAST_TESTS=(
  "$REGRESSION_DIR/test-r01-bundled-android-icons.sh"
  "$REGRESSION_DIR/test-r02-gtk-bootstrap-restore.sh"
  "$REGRESSION_DIR/test-r03-gtk-patch-marker.sh"
  "$REGRESSION_DIR/test-r04-stale-toolchain-discard.sh"
  "$REGRESSION_DIR/test-r05-wrap-redirects-need-gtk.sh"
)

for script in "${FAST_TESTS[@]}"; do
  [ -x "$script" ] || chmod +x "$script"
  run_test "$script"
done

if [ "$MODE" = "--full" ]; then
  run_test "$ROOT_DIR/scripts/android/verify-android-ci-preflight.sh"
elif [ -n "$MODE" ] && [ "$MODE" != "--full" ]; then
  echo "Unknown option: $MODE (use --full or no args)" >&2
  exit 2
fi

if [ "$MODE" = "--full" ]; then
  echo "android-regression-tests: all passed (full)"
else
  echo "android-regression-tests: all passed (quick)"
fi
