#!/bin/bash
# Run the stacked-review scenario (matches docs/bugs/2026-11-24-ISSUE-stacked-modified-chunk-approval-loop.md Desired behavior).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${1:-$ROOT/build}"
BIN="$BUILD/tests/test-stacked-review-scenario"

if [ ! -x "$BIN" ]; then
  echo "Build first: ninja -C $BUILD tests/test-stacked-review-scenario"
  exit 1
fi

echo "=== Stacked review demo ==="
echo "Run: $BIN"
echo "Walkthrough: open file → Accept 3 hunks → expect full approve, no second wave."
echo "Today: expect FAIL on 'second diff wave' or 'still on needs-review list'."
echo ""
exec "$BIN" "${@:2}"