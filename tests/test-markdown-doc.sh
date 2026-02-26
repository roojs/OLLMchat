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
	[ "$base" = "README" ] && continue
	# -expected.md files are comparison fixtures, not inputs to round-trip
	case "$base" in *-expected) continue ;; esac
	# known-fail-* files document known parser limitations (e.g. bold across newline); skip round-trip
	case "$base" in known-fail-*) continue ;; esac
	# verify-issue* files: one-off verification inputs; not part of regular run
	case "$base" in verify-issue*) continue ;; esac
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
	# Compare: roundtrip-output vs original (the input file). Diffs handle accepted round-trip differences.
	roundtrip_output="${OUT_DIR}/${base}-roundtrip-output.md"
	expected_src="$f"
	if [ -f "$MD_DATA/${base}-roundtrip-output.diff" ]; then
		expected_side="${OUT_DIR}/${base}-original-with-patch.md"
	else
		expected_side="${OUT_DIR}/${base}-original.md"
	fi
	cp "$roundtrip_file" "$roundtrip_output"
	cp "$expected_src" "$expected_side"
	# Minimal table: assert round-trip preserves cell content
	if [ "$base" = "minimal-table" ]; then
		for want in A B 1 2; do
			if ! grep -qF "$want" "$roundtrip_file"; then
				test_fail "markdown-doc $base: round-trip output missing cell content \"$want\""
				break
			fi
		done
		if [ "$CURRENT_TEST_FAILED" = false ]; then
			test_pass "markdown-doc $base: round-trip preserves table cells A, B, 1, 2"
		fi
	fi
	if [ -f "$MD_DATA/${base}-roundtrip-output.diff" ]; then
		(cd "$OUT_DIR" && patch -p0 --forward -i "$SCRIPT_DIR/markdown/${base}-roundtrip-output.diff") || true
	fi
	test-match "markdown-doc $base" "$roundtrip_output" "$expected_side" "round-trip md matches original (diffs only for accepted differences)"
done

print_test_summary
[ "$TESTS_FAILED" -eq 0 ] || exit 1
