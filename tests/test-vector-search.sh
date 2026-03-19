#!/bin/bash
# Repro script for isolated single-file vector indexing/search.
# Uses a fixed data directory under build/test/vector-test and runs the full flow:
# 1. clean data dir
# 2. index one file
# 3. inspect metadata with --show-info
# 4. run the target semantic search
# 5. dump vector from test DB to TEST_DIR/dump-test.txt
# 6. optionally dump from live DB to TEST_DIR/dump-live.txt and diff

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FORCE_REINDEX=0
while [ "${1:-}" = "--force-reindex" ]; do
    FORCE_REINDEX=1
    shift
done

_build_arg="${1:-$PROJECT_ROOT/build}"
if [ -d "$_build_arg" ]; then
    BUILD_DIR="$(cd "$_build_arg" && pwd)"
elif [ -d "$PROJECT_ROOT/$_build_arg" ]; then
    BUILD_DIR="$(cd "$PROJECT_ROOT/$_build_arg" && pwd)"
else
    BUILD_DIR="$PROJECT_ROOT/build"
fi

OC_VECTOR_INDEX="$BUILD_DIR/oc-vector-index"
OC_VECTOR_SEARCH="$BUILD_DIR/oc-vector-search"
TEST_DIR="$BUILD_DIR/test/vector-test"
TARGET_FILE="liboccoder/Task/List.vala"
TARGET_AST_PATH="OLLMcoder.Task-List-write"
QUERY="task list file write"

FAILURES=0

require_binary() {
    local path="$1"
    local name="$2"
    if [ ! -f "$path" ]; then
        echo "Error: $name not found at $path"
        echo "Build with: meson compile -C build"
        exit 1
    fi
}

run_step() {
    local step_name="$1"
    local log_file="$2"
    shift 2

    echo ""
    echo "=== $step_name ==="
    echo "Log: $log_file"
    echo "Command: $*"

    "$@" >"$log_file" 2>&1
    local status=$?

    cat "$log_file"

    if [ $status -eq 0 ]; then
        echo "Status: PASS"
    else
        echo "Status: FAIL (exit $status)"
        FAILURES=$((FAILURES + 1))
    fi

    return 0
}

require_file_for_search() {
    local path="$1"
    local label="$2"
    if [ -f "$path" ]; then
        echo ""
        echo "Verified $label: $path"
        return 0
    fi

    echo ""
    echo "Missing $label: $path"
    FAILURES=$((FAILURES + 1))
    return 1
}

echo "=== Vector search isolated repro ==="
echo "Project root: $PROJECT_ROOT"
echo "Build dir: $BUILD_DIR"
echo "Test dir: $TEST_DIR"
echo "Target file: $TARGET_FILE"
echo "Query: $QUERY"
[ "$FORCE_REINDEX" -eq 1 ] && echo "Force reindex: yes"

require_binary "$OC_VECTOR_INDEX" "oc-vector-index"
require_binary "$OC_VECTOR_SEARCH" "oc-vector-search"

INDEX_EXISTS=0
if [ -f "$TEST_DIR/files.sqlite" ] && [ -f "$TEST_DIR/codedb.faiss.vectors" ]; then
    INDEX_EXISTS=1
fi

if [ "$FORCE_REINDEX" -eq 1 ]; then
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    run_step \
        "Index single file" \
        "$TEST_DIR/index.log" \
        "$OC_VECTOR_INDEX" \
        "--data-dir=$TEST_DIR" \
        --create-project \
        "--only-file=$TARGET_FILE" \
        "$PROJECT_ROOT"
elif [ "$INDEX_EXISTS" -eq 1 ]; then
    echo ""
    echo "=== Using existing index (skip index step; use --force-reindex to recreate) ==="
    mkdir -p "$TEST_DIR"
else
    mkdir -p "$TEST_DIR"
    run_step \
        "Index single file" \
        "$TEST_DIR/index.log" \
        "$OC_VECTOR_INDEX" \
        "--data-dir=$TEST_DIR" \
        --create-project \
        "--only-file=$TARGET_FILE" \
        "$PROJECT_ROOT"
fi

if require_file_for_search "$TEST_DIR/files.sqlite" "SQL database" && \
   require_file_for_search "$TEST_DIR/codedb.faiss.vectors" "vector index"; then
    run_step \
        "Show indexed metadata" \
        "$TEST_DIR/show-info.log" \
        "$OC_VECTOR_SEARCH" \
        "--data-dir=$TEST_DIR" \
        "--show-info=$TARGET_FILE" \
        "$PROJECT_ROOT"

    run_step \
        "Search test DB (single-file vector filter)" \
        "$TEST_DIR/search.log" \
        "$OC_VECTOR_SEARCH" \
        "--data-dir=$TEST_DIR" \
        "--only-file=$TARGET_FILE" \
        --debug \
        "--debug-ast-path=$TARGET_AST_PATH" \
        -e method \
        -n 20 \
        "$PROJECT_ROOT" \
        "$QUERY"

    echo ""
    echo "=== Search live DB (same query, --only-file=$TARGET_FILE) ==="
    echo "Log: $TEST_DIR/search-live.log"
    if "$OC_VECTOR_SEARCH" \
        "--only-file=$TARGET_FILE" \
        --debug \
        "--debug-ast-path=$TARGET_AST_PATH" \
        -e method \
        -n 20 \
        "$PROJECT_ROOT" \
        "$QUERY" >"$TEST_DIR/search-live.log" 2>&1; then
        echo "Status: PASS"
        echo ""
        echo "=== Compare: live (only-file) vs test (only-file) — same results? ==="
        if diff <(grep -v '^Filters:' "$TEST_DIR/search.log") <(grep -v '^Filters:' "$TEST_DIR/search-live.log") >"$TEST_DIR/search-live-vs-test.log" 2>&1; then
            echo "Results: IDENTICAL (live DB filtered by file matches test DB search)"
        else
            echo "Results: DIFFER (live vs test search results differ)"
            cat "$TEST_DIR/search-live-vs-test.log"
            FAILURES=$((FAILURES + 1))
        fi
    else
        echo "Status: SKIP or FAIL (live DB may not have this project/file)"
        cat "$TEST_DIR/search-live.log"
        FAILURES=$((FAILURES + 1))
    fi

    run_step \
        "Search test DB without --only-file (all files)" \
        "$TEST_DIR/search-all.log" \
        "$OC_VECTOR_SEARCH" \
        "--data-dir=$TEST_DIR" \
        --debug \
        "--debug-ast-path=$TARGET_AST_PATH" \
        -e method \
        -n 20 \
        "$PROJECT_ROOT" \
        "$QUERY"

    echo ""
    echo "=== Compare: test only-file vs test all-files (same results?) ==="
    if diff <(grep -v '^Filters:' "$TEST_DIR/search.log") <(grep -v '^Filters:' "$TEST_DIR/search-all.log") >"$TEST_DIR/search-compare.log" 2>&1; then
        echo "Results: IDENTICAL (test DB: searching that file only matches searching all)"
    else
        echo "Results: DIFFER"
        cat "$TEST_DIR/search-compare.log"
        FAILURES=$((FAILURES + 1))
    fi

    echo ""
    echo "=== Dump vector from test DB ==="
    echo "Output: $TEST_DIR/dump-test.txt"
    if "$OC_VECTOR_SEARCH" --data-dir="$TEST_DIR" "$PROJECT_ROOT" --dump-vector="$TARGET_AST_PATH" >"$TEST_DIR/dump-test.txt" 2>"$TEST_DIR/dump-test.log"; then
        echo "Status: PASS ($(wc -l <"$TEST_DIR/dump-test.txt") lines)"
    else
        cat "$TEST_DIR/dump-test.log"
        echo "Status: FAIL"
        FAILURES=$((FAILURES + 1))
    fi

    echo ""
    echo "=== Dump vector from live DB (for comparison) ==="
    echo "Output: $TEST_DIR/dump-live.txt"
    if "$OC_VECTOR_SEARCH" "$PROJECT_ROOT" --dump-vector="$TARGET_AST_PATH" >"$TEST_DIR/dump-live.txt" 2>"$TEST_DIR/dump-live.log"; then
        echo "Status: PASS ($(wc -l <"$TEST_DIR/dump-live.txt") lines)"
        if [ -f "$TEST_DIR/dump-test.txt" ] && [ -f "$TEST_DIR/dump-live.txt" ]; then
            echo ""
            echo "=== Diff (live vs test) ==="
            if diff "$TEST_DIR/dump-live.txt" "$TEST_DIR/dump-test.txt" >"$TEST_DIR/dump-diff.log" 2>&1; then
                echo "Vectors: IDENTICAL"
            else
                echo "Vectors: DIFFER"
                cat "$TEST_DIR/dump-diff.log"
            fi
        fi
    else
        echo "Status: SKIP (live DB may not have this project/path)"
        cat "$TEST_DIR/dump-live.log" 2>/dev/null || true
    fi
else
    echo ""
    echo "Skipping search steps because the isolated index was not created."
fi

echo ""
echo "=== Output files ==="
ls -la "$TEST_DIR"

echo ""
if [ $FAILURES -eq 0 ]; then
    echo "Vector search repro completed successfully."
    exit 0
fi

echo "Vector search repro completed with $FAILURES failing step(s)."
exit 1
