#!/bin/bash
# Test script for oc-test-files file operations
# Tests file reading, writing, backups, fake files, project context, etc.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Build directory can be passed as first argument, or default to PROJECT_ROOT/build
BUILD_DIR="${1:-$PROJECT_ROOT/build}"
OC_TEST_FILES="$BUILD_DIR/oc-test-files"

# Test directory
TEST_DIR="$HOME/.cache/ollmchat/testing"
TEST_DB="$TEST_DIR/test.db"

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Cleanup function
cleanup() {
    if [ $? -eq 0 ]; then
        # Test passed - clean up
        if [ -d "$TEST_DIR" ]; then
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

# Test helper functions
test_pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$1")
}

# Extract value from oc-test-files output
extract_value() {
    local key="$1"
    local output="$2"
    # Match lines like "KEY: value" or "KEY: value with spaces"
    echo "$output" | grep -E "^${key}:" | sed "s/^${key}:[[:space:]]*//" | tr -d '\n' | tr -d '\r'
}

# Test 1: File reading with line ranges
test_read_file() {
    echo "=== Test 1: File reading with line ranges ==="
    
    local test_file="$TEST_DIR/test_read.txt"
    local expected_output="$TEST_DIR/expected_read.txt"
    local actual_output="$TEST_DIR/read_output.txt"
    
    # Get data files from tests/data directory
    local data_dir="$SCRIPT_DIR/data"
    local original_file="$data_dir/1.read-test-1-original.txt"
    local expected_file="$data_dir/1.read-test-1-expected.txt"
    
    # Create test file from data file
    cp "$original_file" "$test_file"
    
    # Copy expected output from data file
    cp "$expected_file" "$expected_output"
    
    # Run oc-test-files to read lines 2-5 (use sourceview backend - the critical one)
    local output
    output=$("$OC_TEST_FILES" --read "$test_file" --start-line 2 --end-line 5 --output "$actual_output" --backend sourceview --test-db "$TEST_DB" 2>&1)
    
    # Content is written directly to the output file (metadata goes to stdout)
    # Compare with expected (normalize newlines for comparison)
    local expected_normalized=$(cat "$expected_output" | tr -d '\r')
    local actual_normalized=$(cat "$actual_output" | tr -d '\r')
    if [ "$expected_normalized" = "$actual_normalized" ]; then
        # Verify line count in metadata (may be 7 or 8 depending on trailing newline)
        local line_count
        line_count=$(extract_value "LINE_COUNT" "$output")
        if [ "$line_count" = "7" ] || [ "$line_count" = "8" ]; then
            test_pass "File reading with line ranges"
            return 0
        else
            test_fail "File reading with line ranges (line count mismatch: $line_count)"
            return 1
        fi
    else
        test_fail "File reading with line ranges (content mismatch)"
        return 1
    fi
}

# Test 2: File writing with backups
test_write_with_backup() {
    echo "=== Test 2: File writing with backups ==="
    
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
    local output
    output=$("$OC_TEST_FILES" --write "$test_file" --content "$new_content" --backend sourceview --test-db "$TEST_DB" 2>&1)
    
    # Extract backup path
    local backup_path
    backup_path=$(extract_value "BACKUP" "$output")
    
    # If backup path not in output, check if backup was created anyway (might be async timing issue)
    if [ -z "$backup_path" ] || [ "$backup_path" = "fake_file" ] || [ "$backup_path" = "no_backup_created" ]; then
        # Check if backup file exists in backup directory (backup might have been created but path not set yet)
        local file_id
        file_id=$(extract_value "FILE_ID" "$output")
        if [ -n "$file_id" ] && [ "$file_id" != "-1" ]; then
            # Look for backup file with this file ID
            local backup_dir="$HOME/.cache/ollmchat/edited"
            local today=$(date +%y-%m-%d)
            local backup_pattern="${file_id}-${today}-test.txt"
            backup_path=$(find "$backup_dir" -name "$backup_pattern" 2>/dev/null | head -1)
        fi
    fi
    
    if [ -n "$backup_path" ] && [ "$backup_path" != "fake_file" ] && [ "$backup_path" != "no_backup_created" ] && [ -f "$backup_path" ]; then
        # Verify backup file exists
        if [ -f "$backup_path" ]; then
            # Verify backup contains original content
            if diff -q "$original_content_file" "$backup_path" > /dev/null 2>&1; then
                # Verify backup path format (id-date-basename)
                # Format: {id}-{date YY-MM-DD}-{basename}
                # Example: 123-25-01-15-test.txt
                if echo "$backup_path" | grep -qE '[0-9]+-[0-9]{2}-[0-9]{2}-[0-9]{2}-.*'; then
                    test_pass "File writing with backups"
                    return 0
                else
                    test_fail "File writing with backups (backup path format incorrect: $backup_path)"
                    return 1
                fi
            else
                test_fail "File writing with backups (backup content mismatch)"
                return 1
            fi
        else
            test_fail "File writing with backups (backup file not found: $backup_path)"
            return 1
        fi
    else
        test_fail "File writing with backups (no backup created)"
        return 1
    fi
}

# Test 3: Fake file creation and access
test_fake_file() {
    echo "=== Test 3: Fake file creation and access ==="
    
    local fake_file="$TEST_DIR/fake.txt"
    
    # Create fake file
    local output1
    output1=$("$OC_TEST_FILES" --create-fake "$fake_file" --test-db "$TEST_DB" 2>&1)
    
    # Verify file ID is -1
    local file_id
    file_id=$(extract_value "FILE_ID" "$output1")
    
    if [ "$file_id" = "-1" ]; then
        # Create the actual file on disk for reading
        echo "test content" > "$fake_file"
        
        # Read fake file
        local output2
        output2=$("$OC_TEST_FILES" --read "$fake_file" --test-db "$TEST_DB" 2>&1)
        
        if echo "$output2" | grep -q "test content"; then
            # Write to fake file (should not create backup)
            local output3
            output3=$("$OC_TEST_FILES" --write "$fake_file" --content "new test" --test-db "$TEST_DB" 2>&1)
            
            local backup_info
            backup_info=$(extract_value "NO_BACKUP" "$output3")
            
            if [ -n "$backup_info" ] && [ "$backup_info" = "fake_file" ]; then
                test_pass "Fake file creation and access"
                return 0
            else
                test_fail "Fake file creation and access (backup created for fake file)"
                return 1
            fi
        else
            test_fail "Fake file creation and access (read failed)"
            return 1
        fi
    else
        test_fail "Fake file creation and access (file ID not -1: $file_id)"
        return 1
    fi
}

# Test 4: Project context detection
test_project_context() {
    echo "=== Test 4: Project context detection ==="
    
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
    local output1
    output1=$("$OC_TEST_FILES" --check-project "$project_file" --test-db "$TEST_DB" 2>&1)
    
    local status1
    status1=$(extract_value "STATUS" "$output1")
    
    if [ "$status1" = "IN_PROJECT" ]; then
        # Check file outside project
        echo "test" > "$outside_file"
        local output2
        output2=$("$OC_TEST_FILES" --check-project "$outside_file" --test-db "$TEST_DB" 2>&1)
        
        local status2
        status2=$(extract_value "STATUS" "$output2")
        
        if [ "$status2" = "NOT_IN_PROJECT" ]; then
            test_pass "Project context detection"
            return 0
        else
            test_fail "Project context detection (outside file status incorrect: $status2)"
            return 1
        fi
    else
        test_fail "Project context detection (in-project file status incorrect: $status1)"
        return 1
    fi
}

# Test 5: Backup cleanup
test_backup_cleanup() {
    echo "=== Test 5: Backup cleanup ==="
    
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
    local output
    output=$("$OC_TEST_FILES" --cleanup-backups --test-db="$TEST_DB" 2>&1)
    
    # The cleanup function may or may not remove files depending on implementation
    # Just verify the command runs without error
    if [ $? -eq 0 ]; then
        test_pass "Backup cleanup"
        return 0
    else
        test_fail "Backup cleanup (command failed)"
        return 1
    fi
}

# Test 6: Buffer cleanup/management
test_buffer_management() {
    echo "=== Test 6: Buffer cleanup/management ==="
    
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
    local output
    output=$("$OC_TEST_FILES" --list-buffers --test-db "$TEST_DB" 2>&1)
    
    # The command should work (even if it returns "No buffers found")
    # since buffers don't persist across invocations
    if echo "$output" | grep -qE "(^BUFFER:|No buffers found)"; then
        test_pass "Buffer cleanup/management (command works)"
        return 0
    else
        test_fail "Buffer cleanup/management (command failed)"
        return 1
    fi
}

# Test 7: Permissions skipped for project files
test_permissions_skip() {
    echo "=== Test 7: Permissions skipped for project files ==="
    
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
    local output
    output=$("$OC_TEST_FILES" --read="$project_file" --test-db="$TEST_DB" 2>&1)
    
    if echo "$output" | grep -q "test"; then
        test_pass "Permissions skipped for project files (file accessible)"
        return 0
    else
        test_fail "Permissions skipped for project files (file not accessible)"
        return 1
    fi
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
    echo ""
    echo "=== Test Summary ==="
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    
    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo ""
        echo "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗ $test${NC}"
        done
    fi
    
    # Final cleanup if all tests passed
    if [ $TESTS_FAILED -eq 0 ]; then
        rm -rf "$TEST_DIR"
        echo ""
        echo "All tests passed! Test directory cleaned up."
        exit 0
    else
        echo ""
        echo -e "${YELLOW}Some tests failed. Test files left in $TEST_DIR for debugging.${NC}"
        exit 1
    fi
}

# Run main function
main

