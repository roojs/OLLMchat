#!/bin/bash
# Bubble tests part 3: Move 2-6 (5) + Deletion 1-3 (3) = 8 tests

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

# Part 3: Move 2-6, Deletion 1-3
test_move_2_rename_directory() {
    echo "=== Test 4.2: Rename directory ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_move_2_rename_directory"
    local old_dir="$TEST_PROJECT_DIR/olddir"
    local new_dir="$TEST_PROJECT_DIR/newdir"
    local test_file="$new_dir/file"
    mkdir -p "$old_dir"
    echo "content" > "$old_dir/file"
    rm -rf "$new_dir"
    bubble_exec "$testname" "mv olddir newdir"
    verify_file_not_exists "$testname" "$old_dir" "Old directory removed"
    verify_dir_exists "$testname" "$new_dir" "New directory created"
    verify_file_exists "$testname" "$test_file" "File in renamed directory"
}

test_move_3_move_file_between_dirs() {
    echo "=== Test 4.3: Move file between directories ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_move_3_move_file_between_dirs"
    local source_file="$TEST_PROJECT_DIR/file"
    local target_dir="$TEST_PROJECT_DIR/dir"
    local target_file="$target_dir/file"
    local file_content="content"
    echo "$file_content" > "$source_file"
    mkdir -p "$target_dir"
    rm -f "$target_file"
    bubble_exec "$testname" "mv file dir/"
    verify_file_not_exists "$testname" "$source_file" "Source file removed"
    verify_file_exists "$testname" "$target_file" "Target file created"
    verify_file_content "$testname" "$target_file" "$file_content" "File content preserved"
}

test_move_4_move_directory_tree() {
    echo "=== Test 4.4: Move directory tree ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_move_4_move_directory_tree"
    local old_tree="$TEST_PROJECT_DIR/tree"
    local new_tree="$TEST_PROJECT_DIR/newlocation"
    local test_file="$new_tree/a/b/file"
    mkdir -p "$old_tree/a/b"
    echo "content" > "$old_tree/a/b/file"
    rm -rf "$new_tree"
    bubble_exec "$testname" "mv tree newlocation/"
    verify_file_not_exists "$testname" "$old_tree" "Old tree removed"
    verify_dir_exists "$testname" "$new_tree" "New tree created"
    verify_file_exists "$testname" "$test_file" "File in moved tree"
}

test_move_5_rename_open_file() {
    echo "=== Test 4.5: Rename open file ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_move_5_rename_open_file"
    local old_file="$TEST_PROJECT_DIR/old"
    local new_file="$TEST_PROJECT_DIR/new"
    local file_content="content"
    echo "$file_content" > "$old_file"
    rm -f "$new_file"
    bubble_exec "$testname" "cat old > /dev/null && mv old new"
    verify_file_not_exists "$testname" "$old_file" "Old file removed"
    verify_file_exists "$testname" "$new_file" "New file created"
    verify_file_content "$testname" "$new_file" "$file_content" "File content preserved"
}

test_move_6_move_replace_existing() {
    echo "=== Test 4.6: Move to replace existing ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_move_6_move_replace_existing"
    local new_file="$TEST_PROJECT_DIR/newfile"
    local existing_file="$TEST_PROJECT_DIR/existingfile"
    local new_content="new content"
    local old_content="old content"
    echo "$new_content" > "$new_file"
    echo "$old_content" > "$existing_file"
    bubble_exec "$testname" "mv newfile existingfile"
    verify_file_not_exists "$testname" "$new_file" "Source file removed"
    verify_file_exists "$testname" "$existing_file" "Target file exists"
    verify_file_content "$testname" "$existing_file" "$new_content" "Target file replaced with new content"
}

test_deletion_1_delete_file() {
    echo "=== Test 5.1: Delete file ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_deletion_1_delete_file"
    local test_file="$TEST_PROJECT_DIR/file"
    echo "content" > "$test_file"
    bubble_exec "$testname" "rm file"
    verify_file_not_exists "$testname" "$test_file" "File deleted"
}

test_deletion_2_delete_empty_dir() {
    echo "=== Test 5.2: Delete empty directory ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_deletion_2_delete_empty_dir"
    local test_dir="$TEST_PROJECT_DIR/dir"
    rm -rf "$test_dir"
    mkdir -p "$test_dir"
    bubble_exec "$testname" "rmdir dir"
    verify_file_not_exists "$testname" "$test_dir" "Empty directory deleted"
}

test_deletion_3_delete_tree() {
    echo "=== Test 5.3: Delete directory tree ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_deletion_3_delete_tree"
    local test_tree="$TEST_PROJECT_DIR/tree"
    mkdir -p "$test_tree/a/b"
    touch "$test_tree/file1"
    touch "$test_tree/a/file2"
    touch "$test_tree/a/b/file3"
    bubble_exec "$testname" "rm -rf tree"
    verify_file_not_exists "$testname" "$test_tree" "Directory tree deleted"
}

run_part_3() {
    run_test test_move_2_rename_directory
    run_test test_move_3_move_file_between_dirs
    run_test test_move_4_move_directory_tree
    run_test test_move_5_rename_open_file
    run_test test_move_6_move_replace_existing
    run_test test_deletion_1_delete_file
    run_test test_deletion_2_delete_empty_dir
    run_test test_deletion_3_delete_tree
}

main() {
    echo "Starting overlay bubblewrap tests (part 3)..."
    echo "Test directory: $TEST_DIR"
    echo "Project directory: $TEST_PROJECT_DIR"
    echo "Test database: $TEST_DB"
    echo ""
    setup_test_env
    run_part_3
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
