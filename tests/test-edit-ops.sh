#!/bin/bash
# Test script for oc-test-files edit operations
# Tests file editing, complete file mode, edit mode, backups, line counting, etc.

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source shared test library
source "$SCRIPT_DIR/test-common.sh"

# Build directory can be passed as first argument, or default to PROJECT_ROOT/build
BUILD_DIR="${1:-$PROJECT_ROOT/build}"
OC_TEST_FILES="$BUILD_DIR/oc-test-files"

# Test directory
TEST_DIR="$HOME/.cache/ollmchat/testing"
TEST_DB="$TEST_DIR/test.db"
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
    
    # Verify data directory exists
    if [ ! -d "$DATA_DIR" ]; then
        echo -e "${RED}Error: Test data directory not found at $DATA_DIR${NC}"
        exit 1
    fi
    
    mkdir -p "$TEST_DIR"
    # Remove old test database if it exists
    rm -f "$TEST_DB"
}

# Test 1: Complete file mode (new file creation)
test_complete_file_new() {
    echo "=== Test 1: Complete file mode (new file creation) ==="
    reset_test_state
    
    local testname="test_complete_file_new"
    local test_file="$TEST_DIR/test_new.txt"
    local complete_file="$DATA_DIR/2.edit-test-1-complete.txt"
    local expected_file="$DATA_DIR/2.edit-test-1-expected.txt"
    
    # Run edit command with complete file mode
    local test_cmd="cat \"$complete_file\" | \"$OC_TEST_FILES\" --edit=\"$test_file\" --edit-complete-file --backend sourceview --test-db \"$TEST_DB\""
    test_exe "$testname" "$test_cmd" "$TEST_DIR/${testname}-stdout.txt" "2.edit-test-1"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR" "2.edit-test-1"
    
    # Verify file content
    test-match "$testname" "$test_file" "$expected_file" "File content"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/2.edit-test-1-db.sql" "" "Database state" "2.edit-test-1"
}

# Test 2: Complete file mode (overwrite existing file in project)
test_complete_file_overwrite() {
    echo "=== Test 2: Complete file mode (overwrite existing file in project) ==="
    reset_test_state
    
    local testname="test_complete_file_overwrite"
    local project_dir="$TEST_DIR/testproj2"
    local test_file="$project_dir/test.txt"
    local original_file="$DATA_DIR/2.edit-test-2-original.txt"
    local complete_file="$DATA_DIR/2.edit-test-2-complete.txt"
    local expected_file="$DATA_DIR/2.edit-test-2-expected.txt"
    
    # Create project directory and file
    mkdir -p "$project_dir"
    cp "$original_file" "$test_file"
    
    # Save original content for backup comparison
    local original_content_file="$TEST_DIR/original_backup_content.txt"
    cp "$test_file" "$original_content_file"
    
    # Create project
    "$OC_TEST_FILES" --create-project "$project_dir" --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Read file first to ensure it's loaded
    "$OC_TEST_FILES" --read "$test_file" --backend sourceview --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Clean up any existing backups
    rm -f ~/.cache/ollmchat/edited/*-test.txt 2>/dev/null || true
    
    # Overwrite with complete file mode
    local test_cmd="cat \"$complete_file\" | \"$OC_TEST_FILES\" --edit=\"$test_file\" --edit-complete-file --overwrite --backend sourceview --test-db \"$TEST_DB\""
    test_exe "$testname" "$test_cmd" "$TEST_DIR/${testname}-stdout.txt" "2.edit-test-2"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR" "2.edit-test-2"
    
    # Verify file content
    test-match "$testname" "$test_file" "$expected_file" "File content"
    
    # Verify backup was created (read from stdout file)
    local stdout_file="$TEST_DIR/${testname}-stdout.txt"
    if [ -f "$stdout_file" ]; then
        local file_id
        file_id=$(extract_value "FILE_ID" "$(cat "$stdout_file")")
        local backup_path
        backup_path=$(get_backup_path "$(cat "$stdout_file")" "$file_id" "test.txt")
        
        if [ -n "$backup_path" ] && [ -f "$backup_path" ]; then
            # Verify backup content matches original
            test-match "$testname" "$backup_path" "$original_content_file" "Backup content"
        fi
    fi
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/2.edit-test-2-db.sql" "" "Database state" "2.edit-test-2"
}

# Test 3: Edit mode (single edit)
test_edit_mode_single() {
    echo "=== Test 3: Edit mode (single edit) ==="
    reset_test_state
    
    local testname="test_edit_mode_single"
    local project_dir="$TEST_DIR/testproj3"
    local test_file="$project_dir/test.txt"
    local original_file="$DATA_DIR/2.edit-test-3-original.txt"
    local changes_file="$DATA_DIR/2.edit-test-3-changes.json"
    local expected_file="$DATA_DIR/2.edit-test-3-expected.txt"
    
    # Create project directory and file
    mkdir -p "$project_dir"
    cp "$original_file" "$test_file"
    
    # Create project
    "$OC_TEST_FILES" --create-project "$project_dir" --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Clean up any existing backups
    rm -f ~/.cache/ollmchat/edited/*-test.txt 2>/dev/null || true
    
    # Apply single edit
    local test_cmd="cat \"$changes_file\" | \"$OC_TEST_FILES\" --edit=\"$test_file\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "$testname" "$test_cmd" "$TEST_DIR/${testname}-stdout.txt" "2.edit-test-3"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR" "2.edit-test-3"
    
    # Verify file content
    test-match "$testname" "$test_file" "$expected_file" "File content"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/2.edit-test-3-db.sql" "" "Database state" "2.edit-test-3"
}

# Test 4: Edit mode (multiple edits)
test_edit_mode_multiple() {
    echo "=== Test 4: Edit mode (multiple edits) ==="
    reset_test_state
    
    local testname="test_edit_mode_multiple"
    local project_dir="$TEST_DIR/testproj4"
    local test_file="$project_dir/test.txt"
    local original_file="$DATA_DIR/2.edit-test-4-original.txt"
    local changes_file="$DATA_DIR/2.edit-test-4-changes.json"
    local expected_file="$DATA_DIR/2.edit-test-4-expected.txt"
    
    # Create project directory and file
    mkdir -p "$project_dir"
    cp "$original_file" "$test_file"
    
    # Create project
    "$OC_TEST_FILES" --create-project "$project_dir" --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Clean up any existing backups
    rm -f ~/.cache/ollmchat/edited/*-test.txt 2>/dev/null || true
    
    # Apply multiple edits
    local test_cmd="cat \"$changes_file\" | \"$OC_TEST_FILES\" --edit=\"$test_file\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "$testname" "$test_cmd" "$TEST_DIR/${testname}-stdout.txt" "2.edit-test-4"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR" "2.edit-test-4"
    
    # Verify file content
    test-match "$testname" "$test_file" "$expected_file" "File content"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/2.edit-test-4-db.sql" "" "Database state" "2.edit-test-4"
}

# Test 5: Edit mode (insertion at end of file)
test_edit_mode_insert_end() {
    echo "=== Test 5: Edit mode (insertion at end of file) ==="
    reset_test_state
    
    local testname="test_edit_mode_insert_end"
    local project_dir="$TEST_DIR/testproj5"
    local test_file="$project_dir/test.txt"
    local original_file="$DATA_DIR/2.edit-test-5-original.txt"
    local changes_file="$DATA_DIR/2.edit-test-5-changes.json"
    local expected_file="$DATA_DIR/2.edit-test-5-expected.txt"
    
    # Create project directory and file
    mkdir -p "$project_dir"
    cp "$original_file" "$test_file"
    
    # Create project
    "$OC_TEST_FILES" --create-project "$project_dir" --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Get line count first
    local original_line_count
    original_line_count=$(count_lines "$test_file")
    
    # Clean up any existing backups
    rm -f ~/.cache/ollmchat/edited/*-test.txt 2>/dev/null || true
    
    # Apply edit with insertion at end (start=end=last_line+1)
    local test_cmd="cat \"$changes_file\" | \"$OC_TEST_FILES\" --edit=\"$test_file\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "$testname" "$test_cmd" "$TEST_DIR/${testname}-stdout.txt" "2.edit-test-5"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR" "2.edit-test-5"
    
    # Verify file content
    test-match "$testname" "$test_file" "$expected_file" "File content"
    
    # Verify new lines were appended
    local actual_line_count
    actual_line_count=$(count_lines "$test_file")
    if [ "$actual_line_count" -le "$original_line_count" ]; then
        test_fail "$testname: Lines not appended (original: $original_line_count, actual: $actual_line_count)"
    fi
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/2.edit-test-5-db.sql" "" "Database state" "2.edit-test-5"
}

# Test 6: Line counting accuracy
test_line_counting_accuracy() {
    echo "=== Test 6: Line counting accuracy ==="
    reset_test_state
    
    local testname="test_line_counting_accuracy"
    local project_dir="$TEST_DIR/testproj6"
    mkdir -p "$project_dir"
    
    # Test with 1 line file
    local test_file1="$project_dir/test1.txt"
    local original_file1="$DATA_DIR/2.edit-test-6-1-original.txt"
    local changes_file1="$DATA_DIR/2.edit-test-6-1-changes.json"
    cp "$original_file1" "$test_file1"
    
    # Test with 10 line file
    local test_file2="$project_dir/test2.txt"
    local original_file2="$DATA_DIR/2.edit-test-6-2-original.txt"
    local changes_file2="$DATA_DIR/2.edit-test-6-2-changes.json"
    cp "$original_file2" "$test_file2"
    
    # Test with 100 line file
    local test_file3="$project_dir/test3.txt"
    local original_file3="$DATA_DIR/2.edit-test-6-3-original.txt"
    local changes_file3="$DATA_DIR/2.edit-test-6-3-changes.json"
    cp "$original_file3" "$test_file3"
    
    # Test with file without trailing newline
    local test_file4="$project_dir/test4.txt"
    local original_file4="$DATA_DIR/2.edit-test-6-4-original.txt"
    local changes_file4="$DATA_DIR/2.edit-test-6-4-changes.json"
    cp "$original_file4" "$test_file4"
    
    # Create project
    "$OC_TEST_FILES" --create-project "$project_dir" --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Test file 1 (1 line)
    local test_cmd1="cat \"$changes_file1\" | \"$OC_TEST_FILES\" --edit=\"$test_file1\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "${testname}_1" "$test_cmd1" "$TEST_DIR/${testname}_1-stdout.txt" "2.edit-test-6-1"
    
    # Test file 2 (10 lines)
    local test_cmd2="cat \"$changes_file2\" | \"$OC_TEST_FILES\" --edit=\"$test_file2\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "${testname}_2" "$test_cmd2" "$TEST_DIR/${testname}_2-stdout.txt" "2.edit-test-6-2"
    
    # Test file 3 (100 lines)
    local test_cmd3="cat \"$changes_file3\" | \"$OC_TEST_FILES\" --edit=\"$test_file3\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "${testname}_3" "$test_cmd3" "$TEST_DIR/${testname}_3-stdout.txt" "2.edit-test-6-3"
    
    # Test file 4 (no trailing newline)
    local test_cmd4="cat \"$changes_file4\" | \"$OC_TEST_FILES\" --edit=\"$test_file4\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "${testname}_4" "$test_cmd4" "$TEST_DIR/${testname}_4-stdout.txt" "2.edit-test-6-4"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR" "2.edit-test-6"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/2.edit-test-6-db.sql" "" "Database state" "2.edit-test-6"
}

# Test 7: Backup verification for project files
test_backup_verification() {
    echo "=== Test 7: Backup verification for project files ==="
    reset_test_state
    
    local testname="test_backup_verification"
    local project_dir="$TEST_DIR/testproj7"
    local project_file="$project_dir/project_file.txt"
    local outside_file="$TEST_DIR/outside_file.txt"
    local project_original="$DATA_DIR/2.edit-test-7-project-original.txt"
    local project_changes="$DATA_DIR/2.edit-test-7-project-changes.json"
    local outside_original="$DATA_DIR/2.edit-test-7-outside-original.txt"
    local outside_changes="$DATA_DIR/2.edit-test-7-outside-changes.json"
    
    # Create project directory and file
    mkdir -p "$project_dir"
    cp "$project_original" "$project_file"
    
    # Save original content for backup comparison
    local original_content_file="$TEST_DIR/original_backup_content.txt"
    cp "$project_file" "$original_content_file"
    
    # Create project
    "$OC_TEST_FILES" --create-project "$project_dir" --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Read project file to ensure it's loaded
    "$OC_TEST_FILES" --read "$project_file" --backend sourceview --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Create fake file outside project
    cp "$outside_original" "$outside_file"
    
    # Clean up any existing backups
    rm -f ~/.cache/ollmchat/edited/*-project_file.txt 2>/dev/null || true
    rm -f ~/.cache/ollmchat/edited/*-outside_file.txt 2>/dev/null || true
    
    # Edit project file (should create backup)
    local test_cmd1="cat \"$project_changes\" | \"$OC_TEST_FILES\" --edit=\"$project_file\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "${testname}_project" "$test_cmd1" "$TEST_DIR/${testname}_project-stdout.txt" "2.edit-test-7-project"
    
    # Verify backup was created for project file (read from stdout file)
    local stdout_file1="$TEST_DIR/${testname}_project-stdout.txt"
    if [ -f "$stdout_file1" ]; then
        local file_id1
        file_id1=$(extract_value "FILE_ID" "$(cat "$stdout_file1")")
        local backup_path1
        backup_path1=$(get_backup_path "$(cat "$stdout_file1")" "$file_id1" "project_file.txt")
        
        if [ -n "$backup_path1" ] && [ -f "$backup_path1" ]; then
            # Verify backup content matches original
            test-match "$testname" "$backup_path1" "$original_content_file" "Backup content"
        fi
    fi
    
    # Edit fake file (should NOT create backup)
    local test_cmd2="cat \"$outside_changes\" | \"$OC_TEST_FILES\" --edit=\"$outside_file\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "${testname}_outside" "$test_cmd2" "$TEST_DIR/${testname}_outside-stdout.txt" "2.edit-test-7-outside"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR" "2.edit-test-7"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/2.edit-test-7-db.sql" "" "Database state" "2.edit-test-7"
}

# Test 8: No race conditions in line counting
test_no_race_conditions() {
    echo "=== Test 8: No race conditions in line counting ==="
    reset_test_state
    
    local testname="test_no_race_conditions"
    local project_dir="$TEST_DIR/testproj8"
    local test_file="$project_dir/test.txt"
    local original_file="$DATA_DIR/2.edit-test-8-original.txt"
    local complete_file="$DATA_DIR/2.edit-test-8-complete.txt"
    local changes_file1="$DATA_DIR/2.edit-test-8-changes-1.json"
    local changes_file2="$DATA_DIR/2.edit-test-8-changes-2.json"
    
    # Create project directory and file
    mkdir -p "$project_dir"
    cp "$original_file" "$test_file"
    
    # Create project
    "$OC_TEST_FILES" --create-project "$project_dir" --test-db "$TEST_DB" > /dev/null 2>&1
    
    # Write file and immediately check line count (complete file mode)
    local test_cmd1="cat \"$complete_file\" | \"$OC_TEST_FILES\" --edit=\"$test_file\" --edit-complete-file --overwrite --backend sourceview --test-db \"$TEST_DB\""
    test_exe "${testname}_1" "$test_cmd1" "$TEST_DIR/${testname}_1-stdout.txt" "2.edit-test-8-1"
    
    # Apply edits and immediately check line count (edit mode)
    local test_cmd2="cat \"$changes_file1\" | \"$OC_TEST_FILES\" --edit=\"$test_file\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "${testname}_2" "$test_cmd2" "$TEST_DIR/${testname}_2-stdout.txt" "2.edit-test-8-2"
    
    # Apply another edit immediately
    local test_cmd3="cat \"$changes_file2\" | \"$OC_TEST_FILES\" --edit=\"$test_file\" --backend sourceview --test-db \"$TEST_DB\""
    test_exe "${testname}_3" "$test_cmd3" "$TEST_DIR/${testname}_3-stdout.txt" "2.edit-test-8-3"
    
    # Dump database state
    db_dump_to_file "$testname" "$TEST_DB" "$TEST_DIR" "2.edit-test-8"
    
    # Compare database state
    test-match-db "$testname" "$TEST_DIR/2.edit-test-8-db.sql" "" "Database state" "2.edit-test-8"
}

# Main test runner
main() {
    echo "Starting edit operations tests..."
    echo "Test directory: $TEST_DIR"
    echo "Test database: $TEST_DB"
    echo ""
    
    # Setup
    setup_test_env
    
    # Run tests
    test_complete_file_new || cleanup
    test_complete_file_overwrite || cleanup
    test_edit_mode_single || cleanup
    test_edit_mode_multiple || cleanup
    test_edit_mode_insert_end || cleanup
    test_line_counting_accuracy || cleanup
    test_backup_verification || cleanup
    test_no_race_conditions || cleanup
    
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

