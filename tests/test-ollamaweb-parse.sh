#!/bin/bash
# Offline tests for libollamaweb HTML parsers (fixture HTML vs golden JSON).

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

OC_TEST="$BUILD_DIR/oc-test-ollamaweb"
FIXTURE_DIR="$SCRIPT_DIR/data/ollamaweb"

if [ ! -x "$OC_TEST" ]; then
	OC_TEST="$BUILD_DIR/examples/oc-test-ollamaweb"
fi

if [ ! -f "$OC_TEST" ]; then
	echo -e "${RED}Error: oc-test-ollamaweb not found (tried $BUILD_DIR/oc-test-ollamaweb)${NC}"
	echo "Build with: meson compile -C build"
	exit 1
fi

if [ ! -d "$FIXTURE_DIR" ]; then
	echo -e "${RED}Error: fixture dir missing: $FIXTURE_DIR${NC}"
	exit 1
fi

FAILED=0
PASSED=0

for html in "$FIXTURE_DIR"/*.html; do
	base="$(basename "$html" .html)"
	expected="$FIXTURE_DIR/${base}.expected.json"
	if [ ! -f "$expected" ]; then
		echo -e "${YELLOW}SKIP${NC} $base (no ${base}.expected.json)"
		continue
	fi
	out="$(mktemp)"
	trap 'rm -f "$out"' EXIT
	if [[ "$base" == tags-* ]]; then
		"$OC_TEST" --tags "$html" >"$out"
	else
		"$OC_TEST" "$html" >"$out"
	fi
	if diff -u "$expected" "$out" >/dev/null; then
		echo -e "${GREEN}PASS${NC} $base"
		PASSED=$((PASSED + 1))
	else
		echo -e "${RED}FAIL${NC} $base"
		diff -u "$expected" "$out" || true
		FAILED=$((FAILED + 1))
	fi
	rm -f "$out"
	trap - EXIT
done

echo ""
echo "ollamaweb parse: $PASSED passed, $FAILED failed"
if [ "$FAILED" -gt 0 ]; then
	exit 1
fi
