#!/bin/bash
# Bubble tests part 1: Basic Creation (5) + File Ops 1-3 (3) = 8 tests

set -euo pipefail

STOP_ON_FAILURE=false
if [ "${1:-}" = "--stop-on-failure" ] || [ "${1:-}" = "-x" ]; then
    STOP_ON_FAILURE=true
    shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${1:-$PROJECT_ROOT/build}"
source "$SCRIPT_DIR/test-common.sh"

OC_TEST_BUBBLE="$BUILD_DIR/oc-test-bubble"
TEST_DIR="$BUILD_DIR/ollmchat-testing"
TEST_PROJECT_DIR="$TEST_DIR/project"
TEST_DB="$BUILD_DIR/test-bubble.db"
DATA_DIR="$SCRIPT_DIR/data"
export TEST_DB
export TEST_PROJECT_DIR

# ============================================================================
# Category 1: Basic Creation (5) + File Ops 1-3 (3) = 8 tests
# ============================================================================

test_basic_creation_1_empty_file() {
    echo "=== Test 1.1: Create empty file ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_basic_creation_1_empty_file"
    local test_file="$TEST_PROJECT_DIR/newfile"
    rm -f "$test_file"
    bubble_exec "$testname" "touch newfile"
    verify_file_exists "$testname" "$test_file" "Empty file created"
}

test_basic_creation_2_file_with_content() {
    echo "=== Test 1.2: Create file with content ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_basic_creation_2_file_with_content"
    local test_file="$TEST_PROJECT_DIR/file"
    local expected_content="data"
    rm -f "$test_file"
    bubble_exec "$testname" "echo \"$expected_content\" > file"
    verify_file_exists "$testname" "$test_file" "File created"
    verify_file_content "$testname" "$test_file" "$expected_content" "File content"
}

test_basic_creation_3_nested_dirs_and_file() {
    echo "=== Test 1.3: Create nested directories + file ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_basic_creation_3_nested_dirs_and_file"
    local test_dir="$TEST_PROJECT_DIR/a/b/c"
    local test_file="$test_dir/file"
    rm -rf "$TEST_PROJECT_DIR/a"
    bubble_exec "$testname" "mkdir -p a/b/c && touch a/b/c/file"
    verify_dir_exists "$testname" "$test_dir" "Nested directory created"
    verify_file_exists "$testname" "$test_file" "File in nested directory created"
}

test_basic_creation_4_symlink_to_file() {
    echo "=== Test 1.4: Create symlink to overlay file ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_basic_creation_4_symlink_to_file"
    local target_file="$TEST_PROJECT_DIR/target"
    local link_file="$TEST_PROJECT_DIR/link"
    rm -f "$target_file" "$link_file"
    echo "target content" > "$target_file"
    bubble_exec "$testname" "ln -s target link"
    verify_symlink "$testname" "$link_file" "target" "Symlink to file created"
}

test_basic_creation_5_symlink_to_directory() {
    echo "=== Test 1.5: Create symlink to overlay directory ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_basic_creation_5_symlink_to_directory"
    local target_dir="$TEST_PROJECT_DIR/dir"
    local link_dir="$TEST_PROJECT_DIR/linkdir"
    rm -rf "$target_dir" "$link_dir"
    mkdir -p "$target_dir"
    bubble_exec "$testname" "ln -s dir linkdir"
    verify_symlink "$testname" "$link_dir" "dir" "Symlink to directory created"
}

test_file_ops_1_append() {
    echo "=== Test 2.1: Append to file ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_file_ops_1_append"
    local test_file="$TEST_PROJECT_DIR/file"
    local initial_content="initial"
    local append_content="more"
    local expected_content="${initial_content}${append_content}"
    echo -n "$initial_content" > "$test_file"
    bubble_exec "$testname" "echo -n \"$append_content\" >> file"
    verify_file_content "$testname" "$test_file" "$expected_content" "File content after append"
}

test_file_ops_2_overwrite() {
    echo "=== Test 2.2: Overwrite file content ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_file_ops_2_overwrite"
    local test_file="$TEST_PROJECT_DIR/file"
    local new_content="new"
    echo "old content" > "$test_file"
    bubble_exec "$testname" "echo \"$new_content\" > file"
    verify_file_content "$testname" "$test_file" "$new_content" "File content after overwrite"
}

test_file_ops_3_truncate() {
    echo "=== Test 2.3: Truncate file ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_file_ops_3_truncate"
    local test_file="$TEST_PROJECT_DIR/file"
    echo "some content" > "$test_file"
    bubble_exec "$testname" "truncate -s 0 file"
    verify_file_content "$testname" "$test_file" "" "File truncated to empty"
}

run_part_1() {
    run_test test_basic_creation_1_empty_file
    run_test test_basic_creation_2_file_with_content
    run_test test_basic_creation_3_nested_dirs_and_file
    run_test test_basic_creation_4_symlink_to_file
    run_test test_basic_creation_5_symlink_to_directory
    run_test test_file_ops_1_append
    run_test test_file_ops_2_overwrite
    run_test test_file_ops_3_truncate
}

main() {
    echo "Starting overlay bubblewrap tests (part 1)..."
    echo "Test directory: $TEST_DIR"
    echo "Project directory: $TEST_PROJECT_DIR"
    echo "Test database: $TEST_DB"
    echo ""
    setup_test_env
    run_part_1
    print_test_summary
    if [ $TESTS_FAILED -eq 0 ]; then
        [ -z "${GENERATE_EXPECTED_MODE:-}" ] && rm -rf "$TEST_DIR"
        echo ""
        echo "All tests passed! Test directory cleaned up."
        exit 0
    else
        echo ""
        echo -e "${YELLOW}Some tests failed. Test files left in $TEST_DIR for debugging.${NC}"
        exit 1
    fi
}

# Run main only when this script is executed (not when sourced)
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main
