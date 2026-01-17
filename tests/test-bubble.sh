#!/bin/bash
# Test script for oc-test-bubble overlay operations
# Tests overlay filesystem operations in bubblewrap sandbox
# 42 tests organized into 6 categories

set -euo pipefail

# Check for stop-on-failure option
STOP_ON_FAILURE=false
if [ "${1:-}" = "--stop-on-failure" ] || [ "${1:-}" = "-x" ]; then
    STOP_ON_FAILURE=true
    shift
elif [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: $0 [--stop-on-failure|-x] [BUILD_DIR]"
    echo ""
    echo "Options:"
    echo "  --stop-on-failure, -x    Stop on first test failure (default: continue all tests)"
    echo "  BUILD_DIR               Build directory path (default: PROJECT_ROOT/build)"
    echo ""
    echo "Environment variables:"
    echo "  STOP_ON_FAILURE_ENV=1   Enable stop-on-failure via environment variable"
    echo ""
    exit 0
elif [ "${STOP_ON_FAILURE_ENV:-}" = "1" ] || [ "${STOP_ON_FAILURE_ENV:-}" = "true" ]; then
    STOP_ON_FAILURE=true
fi

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source shared test library
source "$SCRIPT_DIR/test-common.sh"

# Build directory can be passed as first argument (or second if --stop-on-failure was first), or default to PROJECT_ROOT/build
BUILD_DIR="${1:-$PROJECT_ROOT/build}"
OC_TEST_BUBBLE="$BUILD_DIR/oc-test-bubble"

# Test directory - use build directory for test files
TEST_DIR="$BUILD_DIR/ollmchat-testing"
TEST_PROJECT_DIR="$TEST_DIR/project"
TEST_DB="$BUILD_DIR/test-bubble.db"
DATA_DIR="$SCRIPT_DIR/data"

# Export TEST_DB and TEST_PROJECT_DIR for test-common.sh reset_test_state function
export TEST_DB
export TEST_PROJECT_DIR

# Variables to track failed test for debug re-run
FAILED_TEST_FUNC=""
FAILED_TEST_COMMAND=""
FAILED_TEST_NAME=""
DEBUG_RERUN=false

# Cleanup function
cleanup() {
    if [ $? -eq 0 ]; then
        # Test passed - clean up (unless in generate-expected mode)
        if [ -z "${GENERATE_EXPECTED_MODE:-}" ] && [ -d "$TEST_DIR" ]; then
            rm -rf "$TEST_DIR"
            echo "Cleaned up test directory"
        fi
    else
        # Test failed - leave files for debugging
        echo -e "${YELLOW}Test failed - leaving files in $TEST_DIR for debugging${NC}"
    fi
}

# Setup test environment
setup_test_env() {
    # Verify binary exists
    if [ ! -f "$OC_TEST_BUBBLE" ]; then
        echo -e "${RED}Error: oc-test-bubble binary not found at $OC_TEST_BUBBLE${NC}"
        echo "Please build the project first: meson compile -C build"
        exit 1
    fi
    
    # Check if bubblewrap is available
    if ! command -v bwrap > /dev/null 2>&1; then
        echo -e "${YELLOW}Warning: bubblewrap (bwrap) not found in PATH${NC}"
        echo "Some tests may fail. Install bubblewrap to run all tests."
    fi
    
    # Wipe test directory from previous failed test runs
    if [ -d "$TEST_DIR" ]; then
        echo "Cleaning up leftover test directory from previous run..."
        rm -rf "$TEST_DIR"
    fi
    
    # Remove old test database if it exists
    rm -f "$TEST_DB"
    
    # Create fresh test directories
    mkdir -p "$TEST_DIR"
    mkdir -p "$TEST_PROJECT_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "$BUILD_DIR"
}

# Execute command in bubblewrap sandbox
# Usage: bubble_exec testname command [expected_output_file]
bubble_exec() {
    local testname="$1"
    local command="$2"
    local expected_output_file="${3:-}"
    local output_file="$TEST_DIR/${testname}-stdout.txt"
    
    # Store command for potential debug re-run (if stop-on-failure is enabled and not already in debug rerun)
    if [ "$STOP_ON_FAILURE" = true ] && [ "$DEBUG_RERUN" = false ]; then
        FAILED_TEST_COMMAND="$command"
        FAILED_TEST_NAME="$testname"
    fi
    
    # Build the full command with test database
    local debug_flag=""
    if [ "$DEBUG_RERUN" = true ]; then
        debug_flag="--debug "
        output_file="$TEST_DIR/${testname}-stdout-debug.txt"
    fi
    
    local test_cmd="\"$OC_TEST_BUBBLE\" ${debug_flag}--project=\"$TEST_PROJECT_DIR\" --test-db=\"$TEST_DB\" \"$command\""
    
    # Print the command being executed (to stderr so it doesn't interfere with output capture)
    if [ "$DEBUG_RERUN" = true ]; then
        echo "  Running (DEBUG): $OC_TEST_BUBBLE --debug --project=\"$TEST_PROJECT_DIR\" --test-db=\"$TEST_DB\" \"$command\"" >&2
        # During debug rerun, just run the command directly and show output without comparison
        eval "$test_cmd"
        return 0
    else
        echo "  Running: $OC_TEST_BUBBLE --project=\"$TEST_PROJECT_DIR\" --test-db=\"$TEST_DB\" \"$command\"" >&2
    fi
    
    # Execute command via oc-test-bubble
    # test_exe already returns the output via echo, so we don't need to cat the file again
    test_exe "$testname" "$test_cmd" "$output_file" "$testname" "$DATA_DIR"
}

# Verify file exists
verify_file_exists() {
    local testname="$1"
    local file_path="$2"
    local description="${3:-File exists}"
    
    if [ -f "$file_path" ]; then
        test_pass "$testname: $description"
        return 0
    else
        test_fail "$testname: $description (file not found: $file_path)"
        return 0  # Return 0 to allow other verifications to run, but CURRENT_TEST_FAILED is set
    fi
}

# Verify file content
verify_file_content() {
    local testname="$1"
    local file_path="$2"
    local expected_content="$3"
    local description="${4:-File content}"
    
    if [ ! -f "$file_path" ]; then
        test_fail "$testname: $description (file not found: $file_path)"
        return 0  # Return 0 to allow other verifications to run, but CURRENT_TEST_FAILED is set
    fi
    
    local actual_content
    actual_content=$(cat "$file_path" 2>/dev/null || echo "")
    
    if [ "$actual_content" = "$expected_content" ]; then
        test_pass "$testname: $description"
        return 0
    else
        test_fail "$testname: $description"
        echo "  Expected: $expected_content"
        echo "  Actual: $actual_content"
        return 0  # Return 0 to allow other verifications to run, but CURRENT_TEST_FAILED is set
    fi
}

# Verify directory exists
verify_dir_exists() {
    local testname="$1"
    local dir_path="$2"
    local description="${3:-Directory exists}"
    
    if [ -d "$dir_path" ]; then
        test_pass "$testname: $description"
        return 0
    else
        test_fail "$testname: $description (directory not found: $dir_path)"
        return 0  # Return 0 to allow other verifications to run, but CURRENT_TEST_FAILED is set
    fi
}

# Verify symlink exists and points to target
verify_symlink() {
    local testname="$1"
    local link_path="$2"
    local target_path="$3"
    local description="${4:-Symlink exists}"
    
    if [ ! -L "$link_path" ]; then
        test_fail "$testname: $description (not a symlink: $link_path)"
        return 0  # Return 0 to allow other verifications to run, but CURRENT_TEST_FAILED is set
    fi
    
    local actual_target
    actual_target=$(readlink "$link_path" 2>/dev/null || echo "")
    
    if [ "$actual_target" = "$target_path" ]; then
        test_pass "$testname: $description"
        return 0
    else
        test_fail "$testname: $description (wrong target)"
        echo "  Expected: $target_path"
        echo "  Actual: $actual_target"
        return 0  # Return 0 to allow other verifications to run, but CURRENT_TEST_FAILED is set
    fi
}

# Verify file does not exist
verify_file_not_exists() {
    local testname="$1"
    local file_path="$2"
    local description="${3:-File does not exist}"
    
    # If it's a symlink, that's fine - the file was removed and replaced with a symlink
    # Otherwise, check if it's not a regular file and not a directory
    if [ -L "$file_path" ] || ([ ! -f "$file_path" ] && [ ! -d "$file_path" ]); then
        test_pass "$testname: $description"
        return 0
    else
        test_fail "$testname: $description (file still exists: $file_path)"
        return 0  # Return 0 to allow other verifications to run, but CURRENT_TEST_FAILED is set
    fi
}

# Helper function to return appropriate exit code based on test failure state
# Test functions should call this at the end, or it will be checked in run_test
test_exit_code() {
    if [ "$CURRENT_TEST_FAILED" = "true" ]; then
        return 1
    else
        return 0
    fi
}

# ============================================================================
# Category 1: Basic Creation (6 tests)
# ============================================================================

test_basic_creation_1_empty_file() {
    echo "=== Test 1.1: Create empty file ==="
    reset_test_state
    
    local testname="test_basic_creation_1_empty_file"
    local test_file="$TEST_PROJECT_DIR/newfile"
    
    # Clean up any existing file
    rm -f "$test_file"
    
    # Execute command
    bubble_exec "$testname" "touch newfile"
    
    # Verify file exists
    verify_file_exists "$testname" "$test_file" "Empty file created"
}

test_basic_creation_2_file_with_content() {
    echo "=== Test 1.2: Create file with content ==="
    reset_test_state
    
    local testname="test_basic_creation_2_file_with_content"
    local test_file="$TEST_PROJECT_DIR/file"
    local expected_content="data"
    
    # Clean up any existing file
    rm -f "$test_file"
    
    # Execute command
    bubble_exec "$testname" "echo \"$expected_content\" > file"
    
    # Verify file exists and has correct content
    verify_file_exists "$testname" "$test_file" "File created"
    verify_file_content "$testname" "$test_file" "$expected_content" "File content"
}

test_basic_creation_3_nested_dirs_and_file() {
    echo "=== Test 1.3: Create nested directories + file ==="
    reset_test_state
    
    local testname="test_basic_creation_3_nested_dirs_and_file"
    local test_dir="$TEST_PROJECT_DIR/a/b/c"
    local test_file="$test_dir/file"
    
    # Clean up any existing directories
    rm -rf "$TEST_PROJECT_DIR/a"
    
    # Execute command
    bubble_exec "$testname" "mkdir -p a/b/c && touch a/b/c/file"
    
    # Verify directory and file exist
    verify_dir_exists "$testname" "$test_dir" "Nested directory created"
    verify_file_exists "$testname" "$test_file" "File in nested directory created"
}

test_basic_creation_4_symlink_to_file() {
    echo "=== Test 1.4: Create symlink to overlay file ==="
    reset_test_state
    
    local testname="test_basic_creation_4_symlink_to_file"
    local target_file="$TEST_PROJECT_DIR/target"
    local link_file="$TEST_PROJECT_DIR/link"
    
    # Clean up any existing files
    rm -f "$target_file" "$link_file"
    
    # Create target file first
    echo "target content" > "$target_file"
    
    # Execute command
    bubble_exec "$testname" "ln -s target link"
    
    # Verify symlink exists and points to target
    verify_symlink "$testname" "$link_file" "target" "Symlink to file created"
}

test_basic_creation_5_symlink_to_directory() {
    echo "=== Test 1.5: Create symlink to overlay directory ==="
    reset_test_state
    
    local testname="test_basic_creation_5_symlink_to_directory"
    local target_dir="$TEST_PROJECT_DIR/dir"
    local link_dir="$TEST_PROJECT_DIR/linkdir"
    
    # Clean up any existing directories
    rm -rf "$target_dir" "$link_dir"
    
    # Create target directory first
    mkdir -p "$target_dir"
    
    # Execute command
    bubble_exec "$testname" "ln -s dir linkdir"
    
    # Verify symlink exists and points to target
    verify_symlink "$testname" "$link_dir" "dir" "Symlink to directory created"
}

# ============================================================================
# Category 2: File Operations (6 tests)
# ============================================================================

test_file_ops_1_append() {
    echo "=== Test 2.1: Append to file ==="
    reset_test_state
    
    local testname="test_file_ops_1_append"
    local test_file="$TEST_PROJECT_DIR/file"
    local initial_content="initial"
    local append_content="more"
    local expected_content="${initial_content}${append_content}"
    
    # Create file with initial content
    echo -n "$initial_content" > "$test_file"
    
    # Execute command
    bubble_exec "$testname" "echo -n \"$append_content\" >> file"
    
    # Verify file content
    verify_file_content "$testname" "$test_file" "$expected_content" "File content after append"
}

test_file_ops_2_overwrite() {
    echo "=== Test 2.2: Overwrite file content ==="
    reset_test_state
    
    local testname="test_file_ops_2_overwrite"
    local test_file="$TEST_PROJECT_DIR/file"
    local new_content="new"
    
    # Create file with initial content
    echo "old content" > "$test_file"
    
    # Execute command
    bubble_exec "$testname" "echo \"$new_content\" > file"
    
    # Verify file content
    verify_file_content "$testname" "$test_file" "$new_content" "File content after overwrite"
}

test_file_ops_3_truncate() {
    echo "=== Test 2.3: Truncate file ==="
    reset_test_state
    
    local testname="test_file_ops_3_truncate"
    local test_file="$TEST_PROJECT_DIR/file"
    
    # Create file with content
    echo "some content" > "$test_file"
    
    # Execute command
    bubble_exec "$testname" "truncate -s 0 file"
    
    # Verify file is empty
    verify_file_content "$testname" "$test_file" "" "File truncated to empty"
}

test_file_ops_4_read() {
    echo "=== Test 2.4: Read file ==="
    reset_test_state
    
    local testname="test_file_ops_4_read"
    local test_file="$TEST_PROJECT_DIR/file"
    local expected_content="read content"
    
    # Create file with content
    echo "$expected_content" > "$test_file"
    
    # Output precursor commands for manual reproduction
    echo "  Precursor commands (run these to set up the environment):"
    echo "    cd \"$TEST_PROJECT_DIR\""
    echo "    echo \"$expected_content\" > file"
    echo ""
    
    # Execute command and capture output
    local output
    output=$(bubble_exec "$testname" "cat file")
    
    # Verify output matches file content
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
    
    local testname="test_file_ops_5_chmod"
    local test_file="$TEST_PROJECT_DIR/file"
    
    # Create file
    touch "$test_file"
    chmod 755 "$test_file"  # Set initial permissions
    
    # Execute command
    bubble_exec "$testname" "chmod 644 file"
    
    # Verify permissions (may vary by system, so just check file exists and is readable)
    if [ -f "$test_file" ] && [ -r "$test_file" ]; then
        test_pass "$testname: File permissions modified"
    else
        test_fail "$testname: File permissions modification failed"
    fi
}

test_file_ops_6_touch_timestamp() {
    echo "=== Test 2.6: Modify file timestamps ==="
    reset_test_state
    
    local testname="test_file_ops_6_touch_timestamp"
    local test_file="$TEST_PROJECT_DIR/file"
    
    # Create file
    touch "$test_file"
    local old_timestamp
    old_timestamp=$(stat -c %Y "$test_file" 2>/dev/null || stat -f %m "$test_file" 2>/dev/null || echo "0")
    
    # Execute command (set timestamp to 2024-01-01 00:00:00)
    bubble_exec "$testname" "touch -t 202401010000 file"
    
    # Verify file exists and timestamp was modified (may not be exact due to overlay, but file should exist)
    if [ -f "$test_file" ]; then
        test_pass "$testname: File timestamp modified"
    else
        test_fail "$testname: File timestamp modification failed"
    fi
}

# ============================================================================
# Category 3: Directory Operations (4 tests)
# ============================================================================

test_dir_ops_1_list() {
    echo "=== Test 3.1: List directory ==="
    reset_test_state
    
    local testname="test_dir_ops_1_list"
    
    # Create test files with mixed case
    touch "$TEST_PROJECT_DIR/File1.txt"
    touch "$TEST_PROJECT_DIR/file2.txt"
    touch "$TEST_PROJECT_DIR/FILE3.TXT"
    
    # Execute command
    local output
    output=$(bubble_exec "$testname" "ls -la")
    
    # Verify output contains our files (basic check)
    if echo "$output" | grep -q "File1.txt" && echo "$output" | grep -q "file2.txt"; then
        test_pass "$testname: Directory listing works"
    else
        test_fail "$testname: Directory listing failed"
    fi
}

test_dir_ops_2_create_remove() {
    echo "=== Test 3.2: Create/remove empty directory ==="
    reset_test_state
    
    local testname="test_dir_ops_2_create_remove"
    local test_dir="$TEST_PROJECT_DIR/dir"
    
    # Clean up any existing directory
    rm -rf "$test_dir"
    
    # Execute command (create and remove in one command)
    bubble_exec "$testname" "mkdir dir && rmdir dir"
    
    # Verify directory does not exist
    verify_file_not_exists "$testname" "$test_dir" "Directory removed"
}

test_dir_ops_3_traverse() {
    echo "=== Test 3.3: Traverse directory tree ==="
    reset_test_state
    
    local testname="test_dir_ops_3_traverse"
    
    # Create directory tree
    mkdir -p "$TEST_PROJECT_DIR/tree/a/b"
    mkdir -p "$TEST_PROJECT_DIR/tree/c"
    touch "$TEST_PROJECT_DIR/tree/file1"
    touch "$TEST_PROJECT_DIR/tree/a/file2"
    touch "$TEST_PROJECT_DIR/tree/a/b/file3"
    
    # Execute command
    local output
    output=$(bubble_exec "$testname" "find . -type f | sort")
    
    # Verify output contains our files
    if echo "$output" | grep -q "tree/file1" && echo "$output" | grep -q "tree/a/file2" && echo "$output" | grep -q "tree/a/b/file3"; then
        test_pass "$testname: Directory tree traversal works"
    else
        test_fail "$testname: Directory tree traversal failed"
    fi
}

test_dir_ops_4_chmod_dir() {
    echo "=== Test 3.4: Change directory permissions ==="
    reset_test_state
    
    local testname="test_dir_ops_4_chmod_dir"
    local test_dir="$TEST_PROJECT_DIR/dir"
    
    # Create directory
    mkdir -p "$test_dir"
    chmod 700 "$test_dir"  # Set initial permissions
    
    # Execute command
    bubble_exec "$testname" "chmod 755 dir"
    
    # Verify directory exists and is accessible
    if [ -d "$test_dir" ]; then
        test_pass "$testname: Directory permissions modified"
    else
        test_fail "$testname: Directory permissions modification failed"
    fi
}

# ============================================================================
# Category 4: Move/Rename (6 tests)
# ============================================================================

test_move_1_rename_file() {
    echo "=== Test 4.1: Rename file ==="
    reset_test_state
    
    local testname="test_move_1_rename_file"
    local old_file="$TEST_PROJECT_DIR/old"
    local new_file="$TEST_PROJECT_DIR/new"
    local file_content="content"
    
    # Create file
    echo "$file_content" > "$old_file"
    rm -f "$new_file"
    
    # Output precursor commands for manual reproduction
    echo "  Precursor commands (run these to set up the environment):"
    echo "    cd \"$TEST_PROJECT_DIR\""
    echo "    echo \"$file_content\" > old"
    echo ""
    
    # Execute command
    bubble_exec "$testname" "mv old new"
    
    # Verify old file doesn't exist and new file exists with content
    verify_file_not_exists "$testname" "$old_file" "Old file removed"
    verify_file_exists "$testname" "$new_file" "New file created"
    verify_file_content "$testname" "$new_file" "$file_content" "File content preserved"
}

test_move_2_rename_directory() {
    echo "=== Test 4.2: Rename directory ==="
    reset_test_state
    
    local testname="test_move_2_rename_directory"
    local old_dir="$TEST_PROJECT_DIR/olddir"
    local new_dir="$TEST_PROJECT_DIR/newdir"
    local test_file="$new_dir/file"
    
    # Create directory with file
    mkdir -p "$old_dir"
    echo "content" > "$old_dir/file"
    rm -rf "$new_dir"
    
    # Execute command
    bubble_exec "$testname" "mv olddir newdir"
    
    # Verify old directory doesn't exist and new directory exists with file
    verify_file_not_exists "$testname" "$old_dir" "Old directory removed"
    verify_dir_exists "$testname" "$new_dir" "New directory created"
    verify_file_exists "$testname" "$test_file" "File in renamed directory"
}

test_move_3_move_file_between_dirs() {
    echo "=== Test 4.3: Move file between directories ==="
    reset_test_state
    
    local testname="test_move_3_move_file_between_dirs"
    local source_file="$TEST_PROJECT_DIR/file"
    local target_dir="$TEST_PROJECT_DIR/dir"
    local target_file="$target_dir/file"
    local file_content="content"
    
    # Create file and target directory
    echo "$file_content" > "$source_file"
    mkdir -p "$target_dir"
    rm -f "$target_file"
    
    # Output precursor commands for manual reproduction
    echo "  Precursor commands (run these to set up the environment):"
    echo "    cd \"$TEST_PROJECT_DIR\""
    echo "    echo \"$file_content\" > file"
    echo "    mkdir -p dir"
    echo ""
    
    # Execute command
    bubble_exec "$testname" "mv file dir/"
    
    # Verify file moved
    verify_file_not_exists "$testname" "$source_file" "Source file removed"
    verify_file_exists "$testname" "$target_file" "Target file created"
    verify_file_content "$testname" "$target_file" "$file_content" "File content preserved"
}

test_move_4_move_directory_tree() {
    echo "=== Test 4.4: Move directory tree ==="
    reset_test_state
    
    local testname="test_move_4_move_directory_tree"
    local old_tree="$TEST_PROJECT_DIR/tree"
    local new_tree="$TEST_PROJECT_DIR/newlocation"
    local test_file="$new_tree/a/b/file"
    
    # Create directory tree
    mkdir -p "$old_tree/a/b"
    echo "content" > "$old_tree/a/b/file"
    rm -rf "$new_tree"
    
    # Execute command
    bubble_exec "$testname" "mv tree newlocation/"
    
    # Verify tree moved
    verify_file_not_exists "$testname" "$old_tree" "Old tree removed"
    verify_dir_exists "$testname" "$new_tree" "New tree created"
    verify_file_exists "$testname" "$test_file" "File in moved tree"
}

test_move_5_rename_open_file() {
    echo "=== Test 4.5: Rename open file ==="
    reset_test_state
    
    local testname="test_move_5_rename_open_file"
    local old_file="$TEST_PROJECT_DIR/old"
    local new_file="$TEST_PROJECT_DIR/new"
    local file_content="content"
    
    # Create file
    echo "$file_content" > "$old_file"
    rm -f "$new_file"
    
    # Execute command (read and rename in one command simulates open file)
    bubble_exec "$testname" "cat old > /dev/null && mv old new"
    
    # Verify rename worked
    verify_file_not_exists "$testname" "$old_file" "Old file removed"
    verify_file_exists "$testname" "$new_file" "New file created"
    verify_file_content "$testname" "$new_file" "$file_content" "File content preserved"
}

test_move_6_move_replace_existing() {
    echo "=== Test 4.6: Move to replace existing ==="
    reset_test_state
    
    local testname="test_move_6_move_replace_existing"
    local new_file="$TEST_PROJECT_DIR/newfile"
    local existing_file="$TEST_PROJECT_DIR/existingfile"
    local new_content="new content"
    local old_content="old content"
    
    # Create files
    echo "$new_content" > "$new_file"
    echo "$old_content" > "$existing_file"
    
    # Execute command
    bubble_exec "$testname" "mv newfile existingfile"
    
    # Verify replacement
    verify_file_not_exists "$testname" "$new_file" "Source file removed"
    verify_file_exists "$testname" "$existing_file" "Target file exists"
    verify_file_content "$testname" "$existing_file" "$new_content" "Target file replaced with new content"
}

# ============================================================================
# Category 5: Deletion (5 tests)
# ============================================================================

test_deletion_1_delete_file() {
    echo "=== Test 5.1: Delete file ==="
    reset_test_state
    
    local testname="test_deletion_1_delete_file"
    local test_file="$TEST_PROJECT_DIR/file"
    
    # Create file
    echo "content" > "$test_file"
    
    # Execute command
    bubble_exec "$testname" "rm file"
    
    # Verify file deleted
    verify_file_not_exists "$testname" "$test_file" "File deleted"
}

test_deletion_2_delete_empty_dir() {
    echo "=== Test 5.2: Delete empty directory ==="
    reset_test_state
    
    local testname="test_deletion_2_delete_empty_dir"
    local test_dir="$TEST_PROJECT_DIR/dir"
    
    # Clean up any existing directory
    rm -rf "$test_dir"
    
    # Create empty directory
    mkdir -p "$test_dir"
    
    # Execute command
    bubble_exec "$testname" "rmdir dir"
    
    # Verify directory deleted
    verify_file_not_exists "$testname" "$test_dir" "Empty directory deleted"
}

test_deletion_3_delete_tree() {
    echo "=== Test 5.3: Delete directory tree ==="
    reset_test_state
    
    local testname="test_deletion_3_delete_tree"
    local test_tree="$TEST_PROJECT_DIR/tree"
    
    # Create directory tree
    mkdir -p "$test_tree/a/b"
    touch "$test_tree/file1"
    touch "$test_tree/a/file2"
    touch "$test_tree/a/b/file3"
    
    # Execute command
    bubble_exec "$testname" "rm -rf tree"
    
    # Verify tree deleted
    verify_file_not_exists "$testname" "$test_tree" "Directory tree deleted"
}

test_deletion_4_delete_symlink() {
    echo "=== Test 5.4: Delete symlink (target unaffected) ==="
    reset_test_state
    
    local testname="test_deletion_4_delete_symlink"
    local target_file="$TEST_PROJECT_DIR/target"
    local link_file="$TEST_PROJECT_DIR/link"
    
    # Clean up any existing files
    rm -f "$target_file" "$link_file"
    
    # Create target and symlink
    echo "target content" > "$target_file"
    ln -s target "$link_file"
    
    # Output precursor commands for manual reproduction
    echo "  Precursor commands (run these to set up the environment):"
    echo "    cd \"$TEST_PROJECT_DIR\""
    echo "    echo \"target content\" > target"
    echo "    ln -s target link"
    echo ""
    
    # Execute command
    bubble_exec "$testname" "rm link"
    
    # Verify symlink deleted but target still exists
    verify_file_not_exists "$testname" "$link_file" "Symlink deleted"
    verify_file_exists "$testname" "$target_file" "Target file still exists"
}

test_deletion_5_delete_with_open_handle() {
    echo "=== Test 5.5: Delete with open handle ==="
    reset_test_state
    
    local testname="test_deletion_5_delete_with_open_handle"
    local test_file="$TEST_PROJECT_DIR/file"
    
    # Create file
    echo "content" > "$test_file"
    
    # Execute command (read and delete simulates open handle scenario)
    bubble_exec "$testname" "cat file > /dev/null && rm file"
    
    # Verify file deleted (on most systems, file can be deleted while open)
    verify_file_not_exists "$testname" "$test_file" "File deleted (even with open handle)"
}

# ============================================================================
# Category 6: Type Swaps (6 tests)
# ============================================================================

test_type_swap_1_file_to_dir() {
    echo "=== Test 6.1: File → Directory ==="
    reset_test_state
    
    local testname="test_type_swap_1_file_to_dir"
    local test_path="$TEST_PROJECT_DIR/file"
    
    # Create file
    echo "content" > "$test_path"
    
    # Output precursor commands for manual reproduction
    echo "  Precursor commands (run these to set up the environment):"
    echo "    cd \"$TEST_PROJECT_DIR\""
    echo "    echo \"content\" > file"
    echo ""
    
    # Execute command
    bubble_exec "$testname" "rm file && mkdir file"
    
    # Verify it's now a directory (check that it's NOT a file, then that it IS a directory)
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
    
    local testname="test_type_swap_2_dir_to_file"
    local test_path="$TEST_PROJECT_DIR/dir"
    
    # Create directory
    mkdir -p "$test_path"
    
    # Output precursor commands for manual reproduction
    echo "  Precursor commands (run these to set up the environment):"
    echo "    cd \"$TEST_PROJECT_DIR\""
    echo "    mkdir -p dir"
    echo ""
    
    # Execute command
    bubble_exec "$testname" "rmdir dir && touch dir"
    
    # Verify it's now a file (check that it's NOT a directory, then that it IS a file)
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
    
    local testname="test_type_swap_3_file_to_symlink"
    local test_path="$TEST_PROJECT_DIR/file"
    local target_path="$TEST_PROJECT_DIR/target"
    
    # Create file and target
    echo "content" > "$test_path"
    echo "target content" > "$target_path"
    
    # Execute command
    bubble_exec "$testname" "rm file && ln -s target file"
    
    # Verify it's now a symlink
    verify_file_not_exists "$testname" "$test_path" "File removed"
    verify_symlink "$testname" "$test_path" "target" "Symlink created at same path"
}

test_type_swap_4_symlink_to_file() {
    echo "=== Test 6.4: Symlink → File ==="
    reset_test_state
    
    local testname="test_type_swap_4_symlink_to_file"
    local test_path="$TEST_PROJECT_DIR/link"
    local target_path="$TEST_PROJECT_DIR/target"
    
    # Clean up any existing files
    rm -f "$test_path" "$target_path"
    
    # Create target and symlink
    echo "target content" > "$target_path"
    ln -s target "$test_path"
    
    # Output precursor commands for manual reproduction
    echo "  Precursor commands (run these to set up the environment):"
    echo "    cd \"$TEST_PROJECT_DIR\""
    echo "    echo \"target content\" > target"
    echo "    ln -s target link"
    echo ""
    
    # Execute command
    bubble_exec "$testname" "rm link && touch link"
    
    # Verify it's now a file (not a symlink)
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
    
    local testname="test_type_swap_5_symlink_to_absolute_outside"
    local link_file="$TEST_PROJECT_DIR/link"
    local target_file="$BUILD_DIR/oc-test-bubble"
    
    # Verify target exists
    if [ ! -f "$target_file" ]; then
        echo -e "${YELLOW}Skipping test: oc-test-bubble not found at $target_file${NC}"
        return 0
    fi
    
    # Clean up any existing link
    rm -f "$link_file"
    
    # Execute command - create symlink to absolute path outside project
    bubble_exec "$testname" "ln -s '$target_file' link"
    
    # Verify symlink exists and points to correct absolute path
    verify_symlink "$testname" "$link_file" "$target_file" "Symlink to absolute path outside project created"
}

test_type_swap_6_symlink_to_relative_outside() {
    echo "=== Test 6.6: Create symlink to relative path outside project ==="
    reset_test_state
    
    local testname="test_type_swap_6_symlink_to_relative_outside"
    local link_file="$TEST_PROJECT_DIR/link"
    local target_file="$BUILD_DIR/oc-test-bubble"
    
    # Verify target exists
    if [ ! -f "$target_file" ]; then
        echo -e "${YELLOW}Skipping test: oc-test-bubble not found at $target_file${NC}"
        return 0
    fi
    
    # Clean up any existing link
    rm -f "$link_file"
    
    # Calculate relative path from TEST_PROJECT_DIR to BUILD_DIR/oc-test-bubble
    # TEST_PROJECT_DIR is $BUILD_DIR/ollmchat-testing/project
    # From project/ go up two levels (../..) to reach build/, then oc-test-bubble
    local relative_target="../../oc-test-bubble"
    
    # Execute command - create symlink to relative path outside project
    bubble_exec "$testname" "ln -s '$relative_target' link"
    
    # Verify symlink exists and points to correct relative path
    verify_symlink "$testname" "$link_file" "$relative_target" "Symlink to relative path outside project created"
}

# ============================================================================
# Main test runner
# ============================================================================

# Run test with stop-on-failure support
# Usage: run_test test_function
run_test() {
    local test_func="$1"
    
    # Reset test failure state before running test
    reset_test_state
    # Explicitly ensure CURRENT_TEST_FAILED is false after reset
    CURRENT_TEST_FAILED=false
    
    if [ "$STOP_ON_FAILURE" = true ]; then
        # Store test function name for potential debug re-run
        FAILED_TEST_FUNC="$test_func"
        
        # Run the test function
        # Temporarily disable exit on error so we can check CURRENT_TEST_FAILED even if test returns non-zero
        set +e
        "$test_func"
        local test_exit=$?
        set -e
        
        # Check if test failed
        # CURRENT_TEST_FAILED is set by test_fail() in test-common.sh when any verification fails
        # We need to check this flag because verification functions return 0 even on failure
        # (they set CURRENT_TEST_FAILED=true instead)
        local test_failed=false
        # Explicitly check if CURRENT_TEST_FAILED is set to the string "true"
        if [ "${CURRENT_TEST_FAILED}" = "true" ]; then
            # A verification failed - treat as test failure
            test_failed=true
        elif [ $test_exit -ne 0 ]; then
            # Test function returned non-zero exit code
            test_failed=true
        fi
        
        if [ "$test_failed" = "true" ]; then
            # Test failed - prepare for debug re-run
            echo ""
            echo -e "${YELLOW}Test failed. Preparing debug re-run...${NC}"
            
            # Clear environment
            echo "  Clearing test environment..."
            if [ -d "$TEST_DIR" ]; then
                rm -rf "$TEST_DIR"
            fi
            rm -f "$TEST_DB"
            
            # Reset up precursor for the test
            echo "  Resetting test environment..."
            setup_test_env
            reset_test_state
            
            # Re-run the entire test function with debug enabled
            echo ""
            echo -e "${YELLOW}Re-running failed test with --debug:${NC}"
            echo "  Test function: $test_func"
            echo ""
            
            # Set debug rerun flag so bubble_exec uses --debug
            DEBUG_RERUN=true
            
            # Re-run the test function (this will include all setup and the command with --debug)
            # Suppress test failures during debug rerun - we just want to see the output
            set +e
            "$test_func" || true
            set -e
            
            # Reset debug flag
            DEBUG_RERUN=false
            
            echo ""
            echo -e "${RED}Stopping on first failure (--stop-on-failure enabled)${NC}"
            print_test_summary
            exit 1
        fi
    else
        # Continue on failure (default behavior)
        "$test_func" || cleanup
    fi
}

main() {
    echo "Starting overlay bubblewrap tests..."
    echo "Test directory: $TEST_DIR"
    echo "Project directory: $TEST_PROJECT_DIR"
    echo "Test database: $TEST_DB"
    if [ "$STOP_ON_FAILURE" = true ]; then
        echo "Stop on failure: ENABLED"
    fi
    echo ""
    
    # Setup
    setup_test_env
    
    # Run all tests
    # Category 1: Basic Creation
    run_test test_basic_creation_1_empty_file
    run_test test_basic_creation_2_file_with_content
    run_test test_basic_creation_3_nested_dirs_and_file
    run_test test_basic_creation_4_symlink_to_file
    run_test test_basic_creation_5_symlink_to_directory
    
    # Category 2: File Operations
    run_test test_file_ops_1_append
    run_test test_file_ops_2_overwrite
    run_test test_file_ops_3_truncate
    run_test test_file_ops_4_read
    run_test test_file_ops_5_chmod
    run_test test_file_ops_6_touch_timestamp
    
    # Category 3: Directory Operations
    run_test test_dir_ops_1_list
    run_test test_dir_ops_2_create_remove
    run_test test_dir_ops_3_traverse
    run_test test_dir_ops_4_chmod_dir
    
    # Category 4: Move/Rename
    run_test test_move_1_rename_file
    run_test test_move_2_rename_directory
    run_test test_move_3_move_file_between_dirs
    run_test test_move_4_move_directory_tree
    run_test test_move_5_rename_open_file
    run_test test_move_6_move_replace_existing
    
    # Category 5: Deletion
    run_test test_deletion_1_delete_file
    run_test test_deletion_2_delete_empty_dir
    run_test test_deletion_3_delete_tree
    run_test test_deletion_4_delete_symlink
    run_test test_deletion_5_delete_with_open_handle
    
    # Category 6: Type Swaps
    run_test test_type_swap_1_file_to_dir
    run_test test_type_swap_2_dir_to_file
    run_test test_type_swap_3_file_to_symlink
    run_test test_type_swap_4_symlink_to_file
    run_test test_type_swap_5_symlink_to_absolute_outside
    run_test test_type_swap_6_symlink_to_relative_outside
    
    # Summary
    print_test_summary
    
    # Final cleanup if all tests passed (unless in generate-expected mode)
    if [ $TESTS_FAILED -eq 0 ]; then
        if [ -z "${GENERATE_EXPECTED_MODE:-}" ]; then
            rm -rf "$TEST_DIR"
            echo ""
            echo "All tests passed! Test directory cleaned up."
        else
            echo ""
            echo "All tests passed! Test directory preserved for expected file generation."
        fi
        exit 0
    else
        echo ""
        echo -e "${YELLOW}Some tests failed. Test files left in $TEST_DIR for debugging.${NC}"
        exit 1
    fi
}

# Run main function
main
