#!/bin/bash
# Bubble tests part 4: Deletion 4-5 (2) + Type Swap (6) = 8 tests

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

# Part 4: Deletion 4-5, Type Swap 1-6
test_deletion_4_delete_symlink() {
    echo "=== Test 5.4: Delete symlink (target unaffected) ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_deletion_4_delete_symlink"
    local target_file="$TEST_PROJECT_DIR/target"
    local link_file="$TEST_PROJECT_DIR/link"
    rm -f "$target_file" "$link_file"
    echo "target content" > "$target_file"
    ln -s target "$link_file"
    bubble_exec "$testname" "rm link"
    verify_file_not_exists "$testname" "$link_file" "Symlink deleted"
    verify_file_exists "$testname" "$target_file" "Target file still exists"
}

test_deletion_5_delete_with_open_handle() {
    echo "=== Test 5.5: Delete with open handle ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_deletion_5_delete_with_open_handle"
    local test_file="$TEST_PROJECT_DIR/file"
    echo "content" > "$test_file"
    bubble_exec "$testname" "cat file > /dev/null && rm file"
    verify_file_not_exists "$testname" "$test_file" "File deleted (even with open handle)"
}

test_type_swap_1_file_to_dir() {
    echo "=== Test 6.1: File → Directory ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_type_swap_1_file_to_dir"
    local test_path="$TEST_PROJECT_DIR/file"
    echo "content" > "$test_path"
    bubble_exec "$testname" "rm file && mkdir file"
    if [ ! -f "$test_path" ]; then
        test_pass "$testname: File removed"
    else
        test_fail "$testname: File removed (file still exists as file: $test_path)"
    fi
    verify_dir_exists "$testname" "$test_path" "Directory created at same path"
}

test_type_swap_2_dir_to_file() {
    echo "=== Test 6.2: Directory → File ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_type_swap_2_dir_to_file"
    local test_path="$TEST_PROJECT_DIR/dir"
    mkdir -p "$test_path"
    bubble_exec "$testname" "rmdir dir && touch dir"
    if [ ! -d "$test_path" ]; then
        test_pass "$testname: Directory removed"
    else
        test_fail "$testname: Directory removed (directory still exists as directory: $test_path)"
    fi
    verify_file_exists "$testname" "$test_path" "File created at same path"
}

test_type_swap_3_file_to_symlink() {
    echo "=== Test 6.3: File → Symlink ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_type_swap_3_file_to_symlink"
    local test_path="$TEST_PROJECT_DIR/file"
    local target_path="$TEST_PROJECT_DIR/target"
    echo "content" > "$test_path"
    echo "target content" > "$target_path"
    bubble_exec "$testname" "rm file && ln -s target file"
    verify_file_not_exists "$testname" "$test_path" "File removed"
    verify_symlink "$testname" "$test_path" "target" "Symlink created at same path"
}

test_type_swap_4_symlink_to_file() {
    echo "=== Test 6.4: Symlink → File ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_type_swap_4_symlink_to_file"
    local test_path="$TEST_PROJECT_DIR/link"
    local target_path="$TEST_PROJECT_DIR/target"
    rm -f "$test_path" "$target_path"
    echo "target content" > "$target_path"
    ln -s target "$test_path"
    bubble_exec "$testname" "rm link && touch link"
    if [ -L "$test_path" ]; then
        test_fail "$testname: Symlink removed (still a symlink: $test_path)"
    else
        test_pass "$testname: Symlink removed"
    fi
    verify_file_exists "$testname" "$test_path" "File created at same path"
}

test_type_swap_5_symlink_to_absolute_outside() {
    echo "=== Test 6.5: Create symlink to absolute path outside project ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_type_swap_5_symlink_to_absolute_outside"
    local link_file="$TEST_PROJECT_DIR/link"
    local target_file="$BUILD_DIR/oc-test-bubble"
    if [ ! -f "$target_file" ]; then
        echo -e "${YELLOW}Skipping test: oc-test-bubble not found at $target_file${NC}"
        return 0
    fi
    rm -f "$link_file"
    bubble_exec "$testname" "ln -s '$target_file' link"
    verify_symlink "$testname" "$link_file" "$target_file" "Symlink to absolute path outside project created"
}

test_type_swap_6_symlink_to_relative_outside() {
    echo "=== Test 6.6: Create symlink to relative path outside project ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_type_swap_6_symlink_to_relative_outside"
    local link_file="$TEST_PROJECT_DIR/link"
    local target_file="$BUILD_DIR/oc-test-bubble"
    if [ ! -f "$target_file" ]; then
        echo -e "${YELLOW}Skipping test: oc-test-bubble not found at $target_file${NC}"
        return 0
    fi
    rm -f "$link_file"
    local relative_target="../../oc-test-bubble"
    bubble_exec "$testname" "ln -s '$relative_target' link"
    verify_symlink "$testname" "$link_file" "$relative_target" "Symlink to relative path outside project created"
}

run_part_4() {
    run_test test_deletion_4_delete_symlink
    run_test test_deletion_5_delete_with_open_handle
    run_test test_type_swap_1_file_to_dir
    run_test test_type_swap_2_dir_to_file
    run_test test_type_swap_3_file_to_symlink
    run_test test_type_swap_4_symlink_to_file
    run_test test_type_swap_5_symlink_to_absolute_outside
    run_test test_type_swap_6_symlink_to_relative_outside
}

main() {
    echo "Starting overlay bubblewrap tests (part 4)..."
    echo "Test directory: $TEST_DIR"
    echo "Project directory: $TEST_PROJECT_DIR"
    echo "Test database: $TEST_DB"
    echo ""
    setup_test_env
    run_part_4
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
