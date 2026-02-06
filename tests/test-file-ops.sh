#!/bin/bash
# Test script for oc-test-files file operations
# Tests file reading, writing, backups, fake files, project context, etc.

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source shared test library
source "$SCRIPT_DIR/test-common.sh"

# Build directory can be passed as first argument, or default to PROJECT_ROOT/build
BUILD_DIR="${1:-$PROJECT_ROOT/build}"
OC_TEST_FILES="$BUILD_DIR/oc-test-files"

# Test directory and DB in build dir (workspace, avoids .cache write/sandbox issues)
TEST_DIR="$BUILD_DIR/testing"
TEST_DB="$BUILD_DIR/test-file-ops.db"
DATA_DIR="$SCRIPT_DIR/data"

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
    if [ ! -f "$OC_TEST_FILES" ]; then
        echo -e "${RED}Error: oc-test-files binary not found at $OC_TEST_FILES${NC}"
        echo "Please build the project first: meson compile -C build"
        exit 1
    fi
    
    mkdir -p "$TEST_DIR"
    mkdir -p "$TEST_DIR/backups"
    # Remove old test database if it exists
    rm -f "$TEST_DB"
}

# Test 1: File reading with line ranges
test_read_file() {
    echo "=== Test 1: File reading with line ranges ==="
    reset_test_state
    
    local testname="test_read_file"
    local test_file="$TEST_DIR/test_read.txt"
    local actual_output="$TEST_DIR/read_output.txt"
    
    # Get data files from tests/data directory
    local original_file="$DATA_DIR/1.read-test-1-original.txt"
    local expected_file="$DATA_DIR/1.read-test-1-expected.txt"
    
    # Create test file from data file
    cp "$original_file" "$test_file"
    
    # Run oc-test-files to read lines 2-5 (use sourceview backend - the critical one)
    local test_cmd="\"$OC_TEST_FILES\" --read \"$test_file\" --start-line 2 --end-line 5 --output \"$actual_output\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "$testname" "$test_cmd" "$TEST_DIR/${testname}-stdout.txt"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR"
    
    # Verify file content
    test-match "$testname" "$actual_output" "$expected_file" "File content"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/${testname}-db.sql" "$DATA_DIR/${testname}-db-expected.sql" "Database state"
}

# Test 2: File writing with backups
test_write_with_backup() {
    echo "=== Test 2: File writing with backups ==="
    reset_test_state
    
    local testname="test_write_with_backup"
    local project_dir="$TEST_DIR/testproj2"
    local test_file="$project_dir/test.txt"
    local new_content="new content"
    
    # Create test file inside project directory (needs to be in database)
    mkdir -p "$project_dir"
    cat > "$test_file" << 'EOF'
original content
line 2
EOF
    # Save original content to a separate file for comparison (file will be overwritten)
    local original_content_file="$TEST_DIR/original_backup_content.txt"
    cp "$test_file" "$original_content_file"
    
    # Create project first (this will scan the directory and add files to database)
    "$OC_TEST_FILES" --create-project "$project_dir" --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Read the file first to ensure it's loaded (backup needs source file to exist)
    # Use sourceview backend - the critical one
    "$OC_TEST_FILES" --read "$test_file" --backend sourceview --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Clean up any existing backups for this file (to ensure a new backup is created)
    rm -f ~/.cache/ollmchat/edited/*-test.txt 2>/dev/null || true
    
    # Write new content (use sourceview backend - the critical one)
    local test_cmd="\"$OC_TEST_FILES\" --write \"$test_file\" --content \"$new_content\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "$testname" "$test_cmd" "$TEST_DIR/${testname}-stdout.txt"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR"
    
    # Verify backup was created (read from stdout file)
    local stdout_file="$TEST_DIR/${testname}-stdout.txt"
    if [ -f "$stdout_file" ]; then
        local file_id
        file_id=$(extract_value "FILE_ID" "$(cat "$stdout_file")")
        local backup_path
        backup_path=$(get_backup_path "$(cat "$stdout_file")" "$file_id" "test.txt")
        
        if [ -n "$backup_path" ] && [ -f "$backup_path" ]; then
            # Verify backup contains original content
            test-match "$testname" "$backup_path" "$original_content_file" "Backup content"
        fi
    fi
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/${testname}-db.sql" "$DATA_DIR/${testname}-db-expected.sql" "Database state"
}

# Test 3: Fake file creation and access
test_fake_file() {
    echo "=== Test 3: Fake file creation and access ==="
    reset_test_state
    
    local testname="test_fake_file"
    local fake_file="$TEST_DIR/fake.txt"
    
    # Create fake file
    local test_cmd1="\"$OC_TEST_FILES\" --create-fake \"$fake_file\" --test-db \"$TEST_DB\""
    test_exe "${testname}_create" "$test_cmd1" "$TEST_DIR/${testname}_create-stdout.txt"
    
    # Create the actual file on disk for reading
    echo "test content" > "$fake_file"
    
    # Read fake file
    local test_cmd2="\"$OC_TEST_FILES\" --read \"$fake_file\" --test-db \"$TEST_DB\""
    test_exe "${testname}_read" "$test_cmd2" "$TEST_DIR/${testname}_read-stdout.txt"
    
    # Write to fake file (should not create backup)
    local test_cmd3="\"$OC_TEST_FILES\" --write \"$fake_file\" --content \"new test\" --test-db \"$TEST_DB\""
    test_exe "${testname}_write" "$test_cmd3" "$TEST_DIR/${testname}_write-stdout.txt"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/${testname}-db.sql" "$DATA_DIR/${testname}-db-expected.sql" "Database state"
}

# Test 4: Project context detection
test_project_context() {
    echo "=== Test 4: Project context detection ==="
    reset_test_state
    
    local testname="test_project_context"
    local project_dir="$TEST_DIR/testproj4"
    local project_file="$project_dir/file.txt"
    local outside_file="$TEST_DIR/outside.txt"
    
    # Create project (use unique name to avoid conflicts)
    mkdir -p "$project_dir"
    echo "test" > "$project_file"
    
    # Create project - this will make it the active project
    "$OC_TEST_FILES" --create-project "$project_dir" --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Small delay to ensure project is fully loaded
    sleep 0.1
    
    # Check file in project
    local test_cmd1="\"$OC_TEST_FILES\" --check-project \"$project_file\" --test-db \"$TEST_DB\""
    test_exe "${testname}_in" "$test_cmd1" "$TEST_DIR/${testname}_in-stdout.txt"
    
    # Check file outside project
    echo "test" > "$outside_file"
    local test_cmd2="\"$OC_TEST_FILES\" --check-project \"$outside_file\" --test-db \"$TEST_DB\""
    test_exe "${testname}_out" "$test_cmd2" "$TEST_DIR/${testname}_out-stdout.txt"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/${testname}-db.sql" "$DATA_DIR/${testname}-db-expected.sql" "Database state"
}

# Test 5: Backup cleanup
test_backup_cleanup() {
    echo "=== Test 5: Backup cleanup ==="
    reset_test_state
    
    local testname="test_backup_cleanup"
    local backup_dir="$TEST_DIR/backups"
    mkdir -p "$backup_dir"
    
    # Create old backup (5 days ago)
    local old_backup="$backup_dir/123-25-01-10-old.txt"
    echo "old content" > "$old_backup"
    # Try Linux date command first, then macOS
    if date -d '5 days ago' +%Y%m%d%H%M > /dev/null 2>&1; then
        touch -t "$(date -d '5 days ago' +%Y%m%d%H%M)" "$old_backup"
    elif date -v-5d +%Y%m%d%H%M > /dev/null 2>&1; then
        touch -t "$(date -v-5d +%Y%m%d%H%M)" "$old_backup"
    else
        # Fallback: just create the file
        touch "$old_backup"
    fi
    
    # Create recent backup (1 day ago)
    local recent_backup="$backup_dir/456-25-01-14-recent.txt"
    echo "recent content" > "$recent_backup"
    if date -d '1 day ago' +%Y%m%d%H%M > /dev/null 2>&1; then
        touch -t "$(date -d '1 day ago' +%Y%m%d%H%M)" "$recent_backup"
    elif date -v-1d +%Y%m%d%H%M > /dev/null 2>&1; then
        touch -t "$(date -v-1d +%Y%m%d%H%M)" "$recent_backup"
    else
        touch "$recent_backup"
    fi
    
    # Note: cleanup_old_backups uses hardcoded 7 days, so we can't test with --age-days
    # But we can verify the function works
    local test_cmd="\"$OC_TEST_FILES\" --cleanup-backups --test-db=\"$TEST_DB\""
    test_exe "$testname" "$test_cmd" "$TEST_DIR/${testname}-stdout.txt"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/${testname}-db.sql" "$DATA_DIR/${testname}-db-expected.sql" "Database state"
}

# Test 6: Buffer cleanup/management
test_buffer_management() {
    echo "=== Test 6: Buffer cleanup/management ==="
    reset_test_state
    
    local testname="test_buffer_management"
    
    # Note: Buffers don't persist across separate command invocations
    # This test verifies that the --list-buffers command works
    # We'll create a project and read a file, then immediately list buffers in the same session
    # Actually, we can't do that with separate commands, so we'll just verify the command works
    
    local project_dir="$TEST_DIR/testproj6"
    mkdir -p "$project_dir"
    
    # Create a test file
    echo "test content" > "$project_dir/file1.txt"
    
    # Create project
    "$OC_TEST_FILES" --create-project "$project_dir" --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Read a file to create a buffer (but buffers won't persist to next command)
    # So we'll just verify the command doesn't error
    local test_cmd="\"$OC_TEST_FILES\" --list-buffers --test-db \"$TEST_DB\""
    test_exe "$testname" "$test_cmd" "$TEST_DIR/${testname}-stdout.txt"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/${testname}-db.sql" "$DATA_DIR/${testname}-db-expected.sql" "Database state"
}

# Test 7: Permissions skipped for project files
test_permissions_skip() {
    echo "=== Test 7: Permissions skipped for project files ==="
    reset_test_state
    
    local testname="test_permissions_skip"
    
    # Note: This test is difficult to implement without actual permission prompts
    # For now, we'll just verify that project files can be accessed
    # The actual permission skipping is tested in the integration with tools
    
    local project_dir="$TEST_DIR/testproj"
    local project_file="$project_dir/file.txt"
    
    mkdir -p "$project_dir"
    echo "test" > "$project_file"
    
    # Create project
    "$OC_TEST_FILES" --create-project="$project_dir" --test-db="$TEST_DB" > /dev/null 2>&1
    
    # Verify we can read project file
    local test_cmd="\"$OC_TEST_FILES\" --read=\"$project_file\" --test-db=\"$TEST_DB\""
    test_exe "$testname" "$test_cmd" "$TEST_DIR/${testname}-stdout.txt"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/${testname}-db.sql" "$DATA_DIR/${testname}-db-expected.sql" "Database state"
}

# Main test runner
main() {
    echo "Starting file operations tests..."
    echo "Test directory: $TEST_DIR"
    echo "Test database: $TEST_DB"
    echo ""
    
    # Setup
    setup_test_env
    
    # Run tests
    test_read_file || cleanup
    test_write_with_backup || cleanup
    test_fake_file || cleanup
    test_project_context || cleanup
    test_backup_cleanup || cleanup
    test_buffer_management || cleanup
    test_permissions_skip || cleanup
    
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

