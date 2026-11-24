#!/bin/bash
# Tier C — manual / optional: oc-test-source-diff + isolated ollmfilesd data dir.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${1:-$PROJECT_ROOT/build}"

source "$SCRIPT_DIR/test-common.sh"

OC_DIFF="$BUILD_DIR/examples/oc-test-source-diff"
OLLMFILESD="$BUILD_DIR/ollmfilesd/ollmfilesd"

if [ -z "${DISPLAY:-}" ]; then
    test_pass "Tier C skipped (no DISPLAY)"
    exit 0
fi

if [ ! -x "$OC_DIFF" ] || [ ! -x "$OLLMFILESD" ]; then
    echo -e "${RED}Build missing oc-test-source-diff or ollmfilesd${NC}" >&2
    exit 1
fi

if [ -z "${STACKED_REVIEW_DATA_DIR:-}" ]; then
    echo "Tier C: run Tier A first; on failure export STACKED_REVIEW_DATA_DIR=$BUILD_DIR/test-rpc-stacked-review-*"
    echo "Then: STACKED_REVIEW_DATA_DIR=<dir> $0"
    test_pass "Tier C skipped (no STACKED_REVIEW_DATA_DIR)"
    exit 0
fi

test_pass "Tier C: open editor with:"
echo "  OLLM_OLLMFILESD=$OLLMFILESD"
echo "  # start daemon: OLLMFILES_IS_TEST=1 $OLLMFILESD --data-dir=$STACKED_REVIEW_DATA_DIR"
echo "  $OC_DIFF --selectors"
echo "  # open project, open stacked-review.txt, Accept hunks until done"