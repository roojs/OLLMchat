#!/bin/bash
# Tier C — visual sign-off for stacked modified approval (manual Accept in real widgets).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${1:-$ROOT/build}"
BIN="$BUILD/tests/test-stacked-review-scenario"

if [ -z "${DISPLAY:-}" ]; then
  echo "Need a graphical session (DISPLAY)." >&2
  exit 1
fi

if [ ! -x "$BIN" ]; then
  echo "Build first: ninja -C $BUILD tests/test-stacked-review-scenario" >&2
  exit 1
fi

echo "=== Stacked review — visual sign-off (Tier C) ==="
echo "Run: $BIN --visual"
echo ""
echo "1. Window opens with stacked.txt and 3 diff hunks."
echo "2. Click Accept for each hunk (review bar)."
echo "3. Expect: needs-review queue clears, bar stays (often \"Changes accepted\")."
echo "4. Close the window — exit 0 if checks pass."
echo ""
echo "=== preflight (3x Accept, highlight audit, no manual UI) ==="
"$BIN"
echo ""
echo "Preflight OK — optional visual:"
exec "$BIN" --visual