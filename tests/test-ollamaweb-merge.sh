#!/bin/bash
# Offline test: double-search merge (popular + newest fixtures).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-common.sh"

_build_arg="${1:-$PROJECT_ROOT/build}"
if [ -d "$_build_arg" ]; then
	BUILD_DIR="$(cd "$_build_arg" && pwd)"
elif [ -d "$PROJECT_ROOT/$_build_arg" ]; then
	BUILD_DIR="$(cd "$PROJECT_ROOT/$_build_arg" && pwd)"
else
	BUILD_DIR="$PROJECT_ROOT/build"
fi

OC_TEST="$BUILD_DIR/examples/oc-test-ollamaweb"
FIXTURE_DIR="$SCRIPT_DIR/data/ollamaweb"
POPULAR="$FIXTURE_DIR/search-popular.html"
NEWEST="$FIXTURE_DIR/search-newest.html"
EXPECTED="$FIXTURE_DIR/search-double-merge.expected.json"

if [ ! -f "$OC_TEST" ]; then
	echo -e "${RED}Error: oc-test-ollamaweb not found${NC}"
	exit 1
fi

if [ ! -f "$EXPECTED" ]; then
	echo -e "${RED}Error: missing $EXPECTED${NC}"
	exit 1
fi

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
"$OC_TEST" --merge "$POPULAR" "$NEWEST" >"$out"
if diff -u "$EXPECTED" "$out" >/dev/null; then
	echo -e "${GREEN}PASS${NC} search-double-merge"
	exit 0
fi
echo -e "${RED}FAIL${NC} search-double-merge"
diff -u "$EXPECTED" "$out" || true
exit 1
