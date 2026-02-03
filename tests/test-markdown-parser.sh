#!/bin/bash
# Test script for markdown parser (libocmarkdown)
# Uses oc-markdown-test (DummyRenderer trace) and oc-md2html (HTML output).
# Tests: simple formatting, blocks (headings, lists, code, etc.), tables.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test-common.sh"

# Build directory: first argument or PROJECT_ROOT/build (resolve to absolute for cd)
_build_arg="${1:-$PROJECT_ROOT/build}"
if [ -d "$_build_arg" ]; then
	BUILD_DIR="$(cd "$_build_arg" && pwd)"
elif [ -d "$PROJECT_ROOT/$_build_arg" ]; then
	BUILD_DIR="$(cd "$PROJECT_ROOT/$_build_arg" && pwd)"
else
	BUILD_DIR="$PROJECT_ROOT/build"
fi
OC_MARKDOWN_TEST="$BUILD_DIR/oc-markdown-test"
OC_MD2HTML="$BUILD_DIR/oc-md2html"

DATA_DIR="$SCRIPT_DIR/data"
MD_DATA="$DATA_DIR/markdown"
# Use build/tests/markdown-parser-out so it works in sandbox and meson test runs
TEST_DIR="${TEST_DIR:-$BUILD_DIR/tests/markdown-parser-out}"

setup_test_env() {
	if [ ! -f "$OC_MARKDOWN_TEST" ]; then
		echo -e "${RED}Error: oc-markdown-test not found at $OC_MARKDOWN_TEST${NC}"
		echo "Build with: meson compile -C build"
		exit 1
	fi
	if [ ! -f "$OC_MD2HTML" ]; then
		echo -e "${RED}Error: oc-md2html not found at $OC_MD2HTML${NC}"
		echo "Build with: meson compile -C build"
		exit 1
	fi
	if [ ! -d "$MD_DATA" ]; then
		echo -e "${RED}Error: Markdown test data not found at $MD_DATA${NC}"
		exit 1
	fi
	mkdir -p "$TEST_DIR"
}

# Human-readable test labels for the summary (order must match test order)
MARKDOWN_TEST_LABELS=(
	"1. Formatting (HTML)"
	"2. Blocks (callback trace)"
	"3. Tables (HTML)"
	"4. Links (callback trace)"
)
# Substrings that identify each test in FAILED_TESTS descriptions
MARKDOWN_TEST_KEYS=("Formatting HTML" "Blocks callback" "Tables HTML" "Links callback")

# Test 1: Simple formatting (bold, italic, code, etc.) → HTML
test_formatting() {
	echo "=== Test 1: Formatting (HTML output) ==="
	reset_test_state
	local testname="markdown_formatting"
	local actual="$TEST_DIR/formatting-actual.html"
	local expected="$MD_DATA/formatting-expected.html"
	# Run from tests/ so trace paths are relative; suppress stderr (debug logs)
	(cd "$SCRIPT_DIR" && "$OC_MD2HTML" "data/markdown/formatting.md" 2>/dev/null) > "$actual"
	test-match "$testname" "$actual" "$expected" "Formatting HTML output" || true
}

# Test 2: Blocks (headings, lists, blockquote, code block) → callback trace
test_blocks() {
	echo "=== Test 2: Blocks (callback trace) ==="
	reset_test_state
	local testname="markdown_blocks"
	local actual="$TEST_DIR/blocks-actual-trace.txt"
	local expected="$MD_DATA/blocks-expected-trace.txt"
	(cd "$SCRIPT_DIR" && "$OC_MARKDOWN_TEST" "data/markdown/blocks.md" 2>/dev/null) > "$actual"
	test-match "$testname" "$actual" "$expected" "Blocks callback trace" || true
}

# Test 3: Tables → HTML
test_tables() {
	echo "=== Test 3: Tables (HTML output) ==="
	reset_test_state
	local testname="markdown_tables"
	local actual="$TEST_DIR/tables-actual.html"
	local expected="$MD_DATA/tables-expected.html"
	(cd "$SCRIPT_DIR" && "$OC_MD2HTML" "data/markdown/tables.md" 2>/dev/null) > "$actual"
	test-match "$testname" "$actual" "$expected" "Tables HTML output" || true
}

# Test 4: Links (inline, title, reference-style, task list not links) → callback trace
test_links() {
	echo "=== Test 4: Links (callback trace) ==="
	reset_test_state
	local testname="markdown_links"
	local actual="$TEST_DIR/links-actual-trace.txt"
	local expected="$MD_DATA/links-expected-trace.txt"
	(cd "$SCRIPT_DIR" && "$OC_MARKDOWN_TEST" "data/markdown/links.md" 2>/dev/null) > "$actual"
	test-match "$testname" "$actual" "$expected" "Links callback trace" || true
}

# Actual/expected paths for each test (order matches MARKDOWN_TEST_LABELS)
MARKDOWN_ACTUAL_FILES=(
	"$TEST_DIR/formatting-actual.html"
	"$TEST_DIR/blocks-actual-trace.txt"
	"$TEST_DIR/tables-actual.html"
)
MARKDOWN_EXPECTED_FILES=(
	"$MD_DATA/formatting-expected.html"
	"$MD_DATA/blocks-expected-trace.txt"
	"$MD_DATA/tables-expected.html"
)

# Print which tests passed/failed and, if any failed, show diffs again at the end
print_markdown_results() {
	local failed_flat
	failed_flat=$(IFS=; echo "${FAILED_TESTS[*]}")
	echo ""
	echo "Markdown parser suite — per test:"
	for i in "${!MARKDOWN_TEST_LABELS[@]}"; do
		if [[ -n "$failed_flat" && "$failed_flat" == *"${MARKDOWN_TEST_KEYS[$i]}"* ]]; then
			echo -e "  ${RED}✗ FAIL${NC} ${MARKDOWN_TEST_LABELS[$i]}"
		else
			echo -e "  ${GREEN}✓ PASS${NC} ${MARKDOWN_TEST_LABELS[$i]}"
		fi
	done
	echo ""
	if [ "$TESTS_FAILED" -eq 0 ]; then
		echo -e "${GREEN}Markdown parser: all 4 tests passed.${NC}"
	else
		echo -e "${RED}Markdown parser: $TESTS_FAILED of 4 tests failed.${NC}"
		echo ""
		echo "=== FAILURE DETAILS (diffs below) ==="
		for i in "${!MARKDOWN_TEST_LABELS[@]}"; do
			if [[ -n "$failed_flat" && "$failed_flat" == *"${MARKDOWN_TEST_KEYS[$i]}"* ]]; then
				local actual="${MARKDOWN_ACTUAL_FILES[$i]}"
				local expected="${MARKDOWN_EXPECTED_FILES[$i]}"
				echo ""
				echo -e "${RED}--- ${MARKDOWN_TEST_LABELS[$i]} ---${NC}"
				echo "  Actual:   $actual"
				echo "  Expected: $expected"
				if [ -f "$actual" ] && [ -f "$expected" ]; then
					echo "  Diff (expected -> actual):"
					diff -u "$expected" "$actual" | sed 's/^/    /' || true
				else
					echo "  (Re-run without cleanup to see diff; see inline diff above.)"
				fi
			fi
		done
	fi
}

# Main
echo ""
echo "=== Markdown parser test suite (4 tests) ==="
echo "  • Formatting: oc-md2html on data/markdown/formatting.md → HTML"
echo "  • Blocks:     oc-markdown-test on data/markdown/blocks.md → callback trace"
echo "  • Tables:     oc-md2html on data/markdown/tables.md → HTML"
echo "  • Links:      oc-markdown-test on data/markdown/links.md → callback trace"
echo ""

setup_test_env
test_formatting
test_blocks
test_tables
test_links
print_test_summary
print_markdown_results
exit $([ "$TESTS_FAILED" -eq 0 ] && echo 0 || echo 1)
