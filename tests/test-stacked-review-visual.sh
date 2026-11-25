#!/bin/bash
# Tier C — manual visual sign-off (not run under meson; needs DISPLAY + human Accept clicks).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${1:-$PROJECT_ROOT/build}"

source "$SCRIPT_DIR/test-common.sh"

if [ -z "${DISPLAY:-}" ]; then
    test_pass "Tier C skipped (no DISPLAY)"
    exit 0
fi

BIN="$BUILD_DIR/tests/test-stacked-review-scenario"
if [ ! -x "$BIN" ]; then
    echo -e "${RED}Build: ninja -C $BUILD_DIR tests/test-stacked-review-scenario${NC}" >&2
    exit 1
fi

test_pass "Tier C ready: run visual sign-off"
echo "  $SCRIPT_DIR/run-stacked-review-visual-demo.sh $BUILD_DIR"
echo "  (or: $BIN --visual)"
exit 0