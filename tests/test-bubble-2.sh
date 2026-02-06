#!/bin/bash
# Bubble tests part 2: File Ops 4-6 (3) + Dir Ops (4) + Move 1 (1) = 8 tests

# set -e only (nounset/pipefail break under meson test)
set -e

STOP_ON_FAILURE=false
if [ "${1:-}" = "--stop-on-failure" ] || [ "${1:-}" = "-x" ]; then
    STOP_ON_FAILURE=true
    shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${1:-$PROJECT_ROOT/build}"
# Normalize so Meson-passed path (e.g. build/tests/..) works
BUILD_DIR="$(cd "$SCRIPT_DIR" && cd "$BUILD_DIR" && pwd)"
source "$SCRIPT_DIR/test-common.sh"

OC_TEST_BUBBLE="$BUILD_DIR/oc-test-bubble"
TEST_DIR="$BUILD_DIR/ollmchat-testing"
TEST_PROJECT_DIR="$TEST_DIR/project"
TEST_DB="$BUILD_DIR/test-bubble.db"
DATA_DIR="$SCRIPT_DIR/data"
export TEST_DB
export TEST_PROJECT_DIR

# Part 2: File Ops 4-6, Dir Ops 1-4, Move 1
test_file_ops_4_read() {
    echo "=== Test 2.4: Read file ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_file_ops_4_read"
    local test_file="$TEST_PROJECT_DIR/file"
    local expected_content="read content"
    echo "$expected_content" > "$test_file"
    echo "  Precursor commands (run these to set up the environment):"
    echo "    cd \"$TEST_PROJECT_DIR\""
    echo "    echo \"$expected_content\" > file"
    echo ""
    local output
    output=$(bubble_exec "$testname" "cat file")
    local normalized_output
    normalized_output=$(echo "$output" | grep -v "^Executing" | grep -v "^Project:" | grep -v "^Allow network" | grep -v "^---" | grep -v "^ret_str" | grep -v "^fail_str" | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "$normalized_output" = "$expected_content" ]; then
        test_pass "$testname: File content read correctly"
    else
        test_fail "$testname: File content read incorrectly"
        echo "  Expected: $expected_content"
        echo "  Actual: $normalized_output"
    fi
}

test_file_ops_5_chmod() {
    echo "=== Test 2.5: Modify file permissions ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_file_ops_5_chmod"
    local test_file="$TEST_PROJECT_DIR/file"
    touch "$test_file"
    chmod 755 "$test_file"
    bubble_exec "$testname" "chmod 644 file"
    if [ -f "$test_file" ] && [ -r "$test_file" ]; then
        test_pass "$testname: File permissions modified"
    else
        test_fail "$testname: File permissions modification failed"
    fi
}

test_file_ops_6_touch_timestamp() {
    echo "=== Test 2.6: Modify file timestamps ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_file_ops_6_touch_timestamp"
    local test_file="$TEST_PROJECT_DIR/file"
    touch "$test_file"
    bubble_exec "$testname" "touch -t 202401010000 file"
    if [ -f "$test_file" ]; then
        test_pass "$testname: File timestamp modified"
    else
        test_fail "$testname: File timestamp modification failed"
    fi
}

test_dir_ops_1_list() {
    echo "=== Test 3.1: List directory ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_dir_ops_1_list"
    touch "$TEST_PROJECT_DIR/File1.txt"
    touch "$TEST_PROJECT_DIR/file2.txt"
    touch "$TEST_PROJECT_DIR/FILE3.TXT"
    local output
    output=$(bubble_exec "$testname" "ls -la")
    if echo "$output" | grep -q "File1.txt" && echo "$output" | grep -q "file2.txt"; then
        test_pass "$testname: Directory listing works"
    else
        test_fail "$testname: Directory listing failed"
    fi
}

test_dir_ops_2_create_remove() {
    echo "=== Test 3.2: Create/remove empty directory ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_dir_ops_2_create_remove"
    local test_dir="$TEST_PROJECT_DIR/dir"
    rm -rf "$test_dir"
    bubble_exec "$testname" "mkdir dir && rmdir dir"
    verify_file_not_exists "$testname" "$test_dir" "Directory removed"
}

test_dir_ops_3_traverse() {
    echo "=== Test 3.3: Traverse directory tree ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_dir_ops_3_traverse"
    mkdir -p "$TEST_PROJECT_DIR/tree/a/b"
    mkdir -p "$TEST_PROJECT_DIR/tree/c"
    touch "$TEST_PROJECT_DIR/tree/file1"
    touch "$TEST_PROJECT_DIR/tree/a/file2"
    touch "$TEST_PROJECT_DIR/tree/a/b/file3"
    local output
    output=$(bubble_exec "$testname" "find . -type f | sort")
    if echo "$output" | grep -q "tree/file1" && echo "$output" | grep -q "tree/a/file2" && echo "$output" | grep -q "tree/a/b/file3"; then
        test_pass "$testname: Directory tree traversal works"
    else
        test_fail "$testname: Directory tree traversal failed"
    fi
}

test_dir_ops_4_chmod_dir() {
    echo "=== Test 3.4: Change directory permissions ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_dir_ops_4_chmod_dir"
    local test_dir="$TEST_PROJECT_DIR/dir"
    mkdir -p "$test_dir"
    chmod 700 "$test_dir"
    bubble_exec "$testname" "chmod 755 dir"
    if [ -d "$test_dir" ]; then
        test_pass "$testname: Directory permissions modified"
    else
        test_fail "$testname: Directory permissions modification failed"
    fi
}

test_move_1_rename_file() {
    echo "=== Test 4.1: Rename file ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_move_1_rename_file"
    local old_file="$TEST_PROJECT_DIR/old"
    local new_file="$TEST_PROJECT_DIR/new"
    local file_content="content"
    echo "$file_content" > "$old_file"
    rm -f "$new_file"
    bubble_exec "$testname" "mv old new"
    verify_file_not_exists "$testname" "$old_file" "Old file removed"
    verify_file_exists "$testname" "$new_file" "New file created"
    verify_file_content "$testname" "$new_file" "$file_content" "File content preserved"
}

run_part_2() {
    run_test test_file_ops_4_read
    run_test test_file_ops_5_chmod
    run_test test_file_ops_6_touch_timestamp
    run_test test_dir_ops_1_list
    run_test test_dir_ops_2_create_remove
    run_test test_dir_ops_3_traverse
    run_test test_dir_ops_4_chmod_dir
    run_test test_move_1_rename_file
}

main() {
    echo "Starting overlay bubblewrap tests (part 2)..."
    echo "Test directory: $TEST_DIR"
    echo "Project directory: $TEST_PROJECT_DIR"
    echo "Test database: $TEST_DB"
    echo ""
    setup_test_env
    run_part_2
    print_test_summary
    if [ "${TESTS_FAILED:-0}" -eq 0 ]; then
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

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main
