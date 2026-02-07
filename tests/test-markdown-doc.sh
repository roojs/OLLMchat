#!/bin/bash
# Document renderer round-trip test: for each tests/markdown/*.md,
# run md → JSON (in build dir), then JSON → md, and compare input vs round-trip output.

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

OC_DOC_TEST="$BUILD_DIR/oc-markdown-doc-test"
MD_DATA="$SCRIPT_DIR/markdown"
OUT_DIR="${OUT_DIR:-$BUILD_DIR/tests/markdown-doc-out}"

if [ ! -f "$OC_DOC_TEST" ]; then
	echo -e "${RED}Error: oc-markdown-doc-test not found at $OC_DOC_TEST${NC}"
	echo "Build with: meson compile -C build"
	exit 1
fi
if [ ! -d "$MD_DATA" ]; then
	echo -e "${RED}Error: Markdown test data not found at $MD_DATA${NC}"
	exit 1
fi
mkdir -p "$OUT_DIR"

# Run from tests/ so paths to .md files are markdown/foo.md
cd "$SCRIPT_DIR"

for f in markdown/*.md; do
	[ -f "$f" ] || continue
	base=$(basename "$f" .md)
	json_file="$OUT_DIR/$base.json"
	roundtrip_file="$OUT_DIR/$base-roundtrip.md"

	# md → JSON
	if ! "$OC_DOC_TEST" "$f" > "$json_file" 2>/dev/null; then
		test_fail "$base: md → JSON failed"
		continue
	fi
	# JSON → md (second positional overrides output format)
	if ! "$OC_DOC_TEST" "$json_file" markdown > "$roundtrip_file" 2>/dev/null; then
		test_fail "$base: JSON → md failed"
		continue
	fi
	# Compare original vs round-trip
	test-match "markdown-doc $base" "$roundtrip_file" "$f" "round-trip md matches input"
done

print_test_summary
[ "$TESTS_FAILED" -eq 0 ] || exit 1
