#!/bin/bash
# Shared test library for oc-test-files test scripts
# Provides common functions for database dumps, file comparisons, and test utilities

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track test results (shared across all tests)
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Track if current test has failed (for skipping subsequent checks)
CURRENT_TEST_FAILED=false

# Test helper functions
test_pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
    ((TESTS_PASSED++)) || true  # Always succeed - increment might fail with set -e if unset
}

test_fail() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    ((TESTS_FAILED++)) || true  # Always succeed - increment might fail with set -e if unset
    FAILED_TESTS+=("$1")
    CURRENT_TEST_FAILED=true
    if [ "${STOP_ON_FAIL:-0}" -ne 0 ]; then
        exit 1
    fi
}

# Extract value from oc-test-files output
extract_value() {
    local key="$1"
    local output="$2"
    # Match lines like "KEY: value" or "KEY: value with spaces"
    echo "$output" | grep -E "^${key}:" | sed "s/^${key}:[[:space:]]*//" | tr -d '\n' | tr -d '\r'
}

# Count lines in a file
count_lines() {
    local file="$1"
    if [ -f "$file" ]; then
        wc -l < "$file" | tr -d ' '
    else
        echo "0"
    fi
}

# Normalize timestamps in database to 0 (1970-01-01) for consistent comparisons
# Usage: normalize_db_timestamps db_path
normalize_db_timestamps() {
    local db_path="$1"
    
    if [ ! -f "$db_path" ]; then
        return 0
    fi
    
    # Update last_viewed and last_modified to 0 (1970-01-01) for all records
    sqlite3 "$db_path" "UPDATE filebase SET last_viewed = 0, last_modified = 0;" 2>/dev/null || true
}

# Dump SQLite database to file
# Usage: db_dump_to_file testname db_path output_dir [data_file_prefix]
#   testname: Test name (for logging)
#   db_path: Path to database
#   output_dir: Directory to save dump
#   data_file_prefix: Optional prefix for output file (e.g., "2.edit-test-1"). If not provided, uses testname
# Note: Timestamps are normalized to 0 before dumping for consistent comparisons
db_dump_to_file() {
    local testname="$1"
    local db_path="$2"
    local output_dir="$3"
    local data_file_prefix="${4:-$testname}"
    local output_file="$output_dir/${data_file_prefix}-db.sql"
    
    if [ ! -f "$db_path" ]; then
        # Database doesn't exist yet - create empty dump
        touch "$output_file"
        return 0
    fi
    
    # Normalize timestamps before dumping
    normalize_db_timestamps "$db_path"
    
    # Dump database to SQL file (INSERTs only for easy comparison)
    if sqlite3 "$db_path" .dump | grep "^INSERT" > "$output_file" 2>/dev/null; then
        return 0
    else
        echo -e "${YELLOW}Warning: Failed to dump database $db_path${NC}" >&2
        touch "$output_file"
        return 1
    fi
}

# Compare actual file against expected file
# Usage: test-match testname actual_file expected_file description
# Returns: 0 on pass, 1 on fail
test-match() {
    local testname="$1"
    local actual_file="$2"
    local expected_file="$3"
    local description="$4"
    
    # Skip if test already failed
    if [ "$CURRENT_TEST_FAILED" = true ]; then
        return 1
    fi
    
    local full_description="${testname}: ${description}"
    
    # Check if expected file exists
    if [ ! -f "$expected_file" ]; then
        test_fail "$full_description (expected file not found: $expected_file)"
        return 1
    fi
    
    # Check if actual file exists
    if [ ! -f "$actual_file" ]; then
        test_fail "$full_description (actual file not found: $actual_file)"
        echo "  Expected file: $expected_file"
        return 1
    fi
    
    # Normalize newlines and compare
    local actual_normalized=$(cat "$actual_file" | tr -d '\r')
    local expected_normalized=$(cat "$expected_file" | tr -d '\r')
    
    if [ "$actual_normalized" = "$expected_normalized" ]; then
        test_pass "$full_description"
        return 0
    else
        test_fail "$full_description"
        echo "  Actual file: $actual_file"
        echo "  Expected file: $expected_file"
        echo "  Diff (expected -> actual):"
        diff -u "$expected_file" "$actual_file" | sed 's/^/    /' || true
        return 1
    fi
}

# Compare database dump files
# Usage: test-match-db testname actual_db_dump expected_db_dump description [data_file_prefix] [data_dir]
#   testname: Test name (for logging)
#   actual_db_dump: Path to actual database dump file
#   expected_db_dump: Path to expected database dump file (or will be constructed from data_file_prefix if not provided)
#   description: Description of what's being tested
#   data_file_prefix: Optional prefix for expected file (e.g., "2.edit-test-1"). If provided and expected_db_dump is empty, constructs path
#   data_dir: Directory containing expected files (defaults to DATA_DIR if set, or current dir)
# Returns: 0 on pass, 1 on fail
test-match-db() {
    local testname="$1"
    local actual_db_dump="$2"
    local expected_db_dump="$3"
    local description="$4"
    local data_file_prefix="${5:-}"
    local data_dir="${6:-${DATA_DIR:-.}}"
    
    # If expected_db_dump is empty and data_file_prefix is provided, construct it
    if [ -z "$expected_db_dump" ] && [ -n "$data_file_prefix" ]; then
        expected_db_dump="$data_dir/${data_file_prefix}-db.sql"
    fi
    
    # Skip if test already failed
    if [ "$CURRENT_TEST_FAILED" = true ]; then
        return 1
    fi
    
    local full_description="${testname}: ${description}"
    
    # Check if expected file exists
    if [ ! -f "$expected_db_dump" ]; then
        # Expected file doesn't exist - this is OK for new tests
        # Just log a warning and skip
        echo -e "${YELLOW}Note: Expected DB dump not found: $expected_db_dump (skipping DB comparison)${NC}"
        return 0
    fi
    
    # Check if actual file exists
    if [ ! -f "$actual_db_dump" ]; then
        test_fail "$full_description (actual DB dump not found: $actual_db_dump)"
        return 1
    fi
    
    # Normalize SQL dumps (normalize whitespace)
    # Dumps contain INSERT-only lines to avoid schema drift comparisons
    local actual_normalized=$(cat "$actual_db_dump" | tr -d '\r' | sed 's/[[:space:]]\+/ /g' | sort)
    local expected_normalized=$(cat "$expected_db_dump" | tr -d '\r' | sed 's/[[:space:]]\+/ /g' | sort)
    
    if [ "$actual_normalized" = "$expected_normalized" ]; then
        test_pass "$full_description"
        return 0
    else
        test_fail "$full_description"
        echo "  Actual DB dump: $actual_db_dump"
        echo "  Expected DB dump: $expected_db_dump"
        echo "  Diff (normalized):"
        # Show unified diff of normalized versions
        diff -u <(echo "$expected_normalized") <(echo "$actual_normalized") | sed 's/^/    /' || true
        return 1
    fi
}

# Reset test failure state for a new test
# Also resets the database if TEST_DB is set (for consistent FILE_IDs)
reset_test_state() {
    CURRENT_TEST_FAILED=false
    # Reset database before each test for consistent FILE_IDs
    if [ -n "${TEST_DB:-}" ] && [ -f "${TEST_DB}" ]; then
        rm -f "${TEST_DB}"
    fi
    # Clean up test directory if TEST_DIR is set (for test-edit-ops.sh)
    # This ensures each test starts with a clean slate unless we're generating fixtures
    if [ -z "${GENERATE_EXPECTED_MODE:-}" ]; then
        if [ -n "${TEST_DIR:-}" ] && [ -d "${TEST_DIR}" ]; then
            find "${TEST_DIR}" -mindepth 1 -delete 2>/dev/null || true
        fi
    fi
    # Clean up project directory if TEST_PROJECT_DIR is set (for test-bubble.sh)
    # This ensures each test starts with a clean project directory
    if [ -n "${TEST_PROJECT_DIR:-}" ] && [ -d "${TEST_PROJECT_DIR}" ]; then
        # Remove all contents (files, directories, hidden files) but keep the directory itself
        find "${TEST_PROJECT_DIR}" -mindepth 1 -delete 2>/dev/null || true
    fi
}

# Print test summary
print_test_summary() {
    echo ""
    echo "=== Test Summary ==="
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}Failed: NONE${NC}"
    else
        echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    fi
    
    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo ""
        echo "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗ $test${NC}"
        done
    fi
}

# Find backup file by pattern
# Usage: find_backup_file file_id basename
# Returns: backup path or empty string
find_backup_file() {
    local file_id="$1"
    local basename="$2"
    local backup_dir="${HOME}/.cache/ollmchat/edited"
    local today=$(date +%y-%m-%d)
    local backup_pattern="${file_id}-${today}-${basename}"
    find "$backup_dir" -name "$backup_pattern" 2>/dev/null | head -1
}

# Verify backup path format
# Usage: verify_backup_path_format backup_path
# Returns: 0 if valid, 1 if invalid
verify_backup_path_format() {
    local backup_path="$1"
    echo "$backup_path" | grep -qE '[0-9]+-[0-9]{2}-[0-9]{2}-[0-9]{2}-.*'
}

# Clean up backup files matching pattern
# Usage: cleanup_backups pattern
cleanup_backups() {
    local pattern="$1"
    rm -f ~/.cache/ollmchat/edited/${pattern} 2>/dev/null || true
}

# Create test project
# Usage: create_test_project project_dir [oc_test_files] [test_db]
create_test_project() {
    local project_dir="$1"
    local oc_test_files="${2:-${OC_TEST_FILES:-}}"
    local test_db="${3:-${TEST_DB:-}}"
    
    if [ -z "$oc_test_files" ] || [ -z "$test_db" ]; then
        echo -e "${RED}Error: OC_TEST_FILES and TEST_DB must be set${NC}" >&2
        return 1
    fi
    
    "$oc_test_files" --create-project "$project_dir" --test-db "$test_db" > /dev/null 2>&1
}

# Read test file (ensures it's loaded in database)
# Usage: read_test_file file_path [oc_test_files] [test_db]
read_test_file() {
    local file_path="$1"
    local oc_test_files="${2:-${OC_TEST_FILES:-}}"
    local test_db="${3:-${TEST_DB:-}}"
    
    if [ -z "$oc_test_files" ] || [ -z "$test_db" ]; then
        echo -e "${RED}Error: OC_TEST_FILES and TEST_DB must be set${NC}" >&2
        return 1
    fi
    
    "$oc_test_files" --read "$file_path" --backend sourceview --test-db "$test_db" > /dev/null 2>&1
}

# Get backup path from output, trying to find it if not in output
# Usage: get_backup_path output file_id basename
# Returns: backup path or empty string
get_backup_path() {
    local output="$1"
    local file_id="$2"
    local basename="$3"
    
    # First try to get from output
    local backup_path
    backup_path=$(extract_value "BACKUP" "$output")
    
    # If not found or invalid, try to find by pattern
    if [ -z "$backup_path" ] || [ "$backup_path" = "no_backup_created" ] || [ "$backup_path" = "fake_file" ]; then
        if [ -n "$file_id" ] && [ "$file_id" != "-1" ]; then
            backup_path=$(find_backup_file "$file_id" "$basename")
        fi
    fi
    
    echo "$backup_path"
}

# Verify backup was created and has correct format
# Usage: verify_backup_created testname backup_path
# Returns: 0 if valid, 1 if invalid
verify_backup_created() {
    local testname="$1"
    local backup_path="$2"
    
    if [ -z "$backup_path" ] || [ "$backup_path" = "no_backup_created" ] || [ "$backup_path" = "fake_file" ]; then
        test_fail "$testname: Backup not created"
        return 1
    fi
    
    if [ ! -f "$backup_path" ]; then
        test_fail "$testname: Backup file not found: $backup_path"
        return 1
    fi
    
    if ! verify_backup_path_format "$backup_path"; then
        test_fail "$testname: Backup path format incorrect: $backup_path"
        return 1
    fi
    
    return 0
}

# Cleanup function (shared)
# Usage: cleanup [test_dir]
# If test_dir is not provided, uses TEST_DIR variable
cleanup() {
    local test_dir="${1:-${TEST_DIR:-}}"
    
    if [ -z "$test_dir" ]; then
        echo -e "${YELLOW}Warning: TEST_DIR not set, cannot cleanup${NC}" >&2
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        # Test passed - clean up
        if [ -d "$test_dir" ]; then
            rm -rf "$test_dir"
            echo "Cleaned up test directory"
        fi
    else
        # Test failed - leave files for debugging
        echo -e "${YELLOW}Test failed - leaving files in $test_dir for debugging${NC}"
    fi
}

# Setup test environment (base function)
# Usage: setup_test_env_base oc_test_files test_dir test_db [data_dir] [extra_dirs...]
setup_test_env_base() {
    local oc_test_files="$1"
    local test_dir="$2"
    local test_db="$3"
    local data_dir="${4:-}"
    shift 4 || true
    local extra_dirs=("$@")
    
    # Verify binary exists
    if [ ! -f "$oc_test_files" ]; then
        echo -e "${RED}Error: oc-test-files binary not found at $oc_test_files${NC}"
        echo "Please build the project first: meson compile -C build"
        exit 1
    fi
    
    # Verify data directory exists (if provided)
    if [ -n "$data_dir" ] && [ ! -d "$data_dir" ]; then
        echo -e "${RED}Error: Test data directory not found at $data_dir${NC}"
        exit 1
    fi
    
    mkdir -p "$test_dir"
    
    # Create extra directories if provided
    for dir in "${extra_dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    # Remove old test database if it exists
    rm -f "$test_db"
}

# Run test command and capture stdout/stderr, then compare with expected
# Usage: output=$(test_exe testname command output_file [data_file_prefix] [data_dir])
#   testname: Test name (for logging)
#   command: Command to run (can be a string with pipes, redirects, etc.)
#   output_file: File to save actual stdout/stderr
#   data_file_prefix: Optional prefix for expected file (e.g., "2.edit-test-1"). If not provided, uses testname
#   data_dir: Directory containing expected files (defaults to DATA_DIR if set, or current dir)
# Returns: Output content (stdout) - can be captured with $()
# Exit code: 0 on match, 1 on mismatch or command failure
# The command is executed with: eval "$command" 2>&1
# Note: Both stdout and stderr are captured and compared
# Comparison messages go to stderr so they don't interfere with output capture
test_exe() {
    local testname="$1"
    local command="$2"
    local output_file="$3"
    local data_file_prefix="${4:-$testname}"
    local data_dir="${5:-${DATA_DIR:-.}}"
    
    # Skip if test already failed
    if [ "$CURRENT_TEST_FAILED" = true ]; then
        return 1
    fi
    
    # Precursor info for debugging
    local precursor
    precursor="TEST: ${testname}\nCOMMAND: ${command}"

    # Print precursor to stderr for live visibility
    echo "TEST: ${testname}" >&2
    echo "COMMAND: ${command}" >&2

    # Run the command and capture output (both stdout and stderr)
    local output
    output=$(eval "$command" 2>&1)
    local cmd_exit=$?
    
    # Save output to file
    printf "%b\n%s\n" "$precursor" "$output" > "$output_file"
    
    # If command failed, that's a test failure
    if [ $cmd_exit -ne 0 ]; then
        test_fail "$testname: Command failed with exit code $cmd_exit" >&2
        echo "  Command: $command" >&2
        echo "  Output saved to: $output_file" >&2
        echo "$output"  # Return output even on failure (for debugging)
        return 1
    fi
    
    # Expected file path - use data_file_prefix with -stdout.txt suffix
    local expected_file="$data_dir/${data_file_prefix}-stdout.txt"
    
    # Compare output with expected (if expected file exists)
    if [ -f "$expected_file" ]; then
        # Do the comparison manually here to send messages to stderr
        local full_description="${testname}: Stdout/stderr output"
        
        # Check if actual file exists
        if [ ! -f "$output_file" ]; then
            test_fail "$full_description (actual file not found: $output_file)" >&2
            echo "$output"
            return 1
        fi
        
        # Normalize newlines and exclude BACKUP lines from comparison
        # BACKUP lines are verified separately by extracting paths from stdout
        # FILE_IDs should be consistent since database is recreated for each test
        local actual_normalized=$(cat "$output_file" | tr -d '\r' | \
            grep -v "^BACKUP:" | \
            grep -v "^TEST:" | \
            grep -v "^COMMAND:")
        local expected_normalized=$(cat "$expected_file" | tr -d '\r' | \
            grep -v "^BACKUP:" | \
            grep -v "^TEST:" | \
            grep -v "^COMMAND:")
        
        if [ "$actual_normalized" = "$expected_normalized" ]; then
            test_pass "$full_description" >&2
        else
            test_fail "$full_description" >&2
            echo "  Actual file: $output_file" >&2
            echo "  Expected file: $expected_file" >&2
            echo "  Diff:" >&2
            # Show unified diff
            diff -u "$expected_file" "$output_file" | sed 's/^/    /' >&2 || true
            echo "$output"  # Still return output
            return 1
        fi
    else
        # Expected file doesn't exist - only warn if there's actual command output
        # Filter out wrapper debug lines, BACKUP lines, and log messages to check for real output
        if [ -f "$output_file" ]; then
            # Remove wrapper debug lines, BACKUP lines, and log messages (timestamp patterns), then check if anything remains
            local actual_content=$(cat "$output_file" | tr -d '\r' | \
                grep -v "^BACKUP:" | \
                grep -v "^TEST:" | \
                grep -v "^COMMAND:" | \
                grep -v "^Executing command in sandbox:" | \
                grep -v "^Project:" | \
                grep -v "^Allow network:" | \
                grep -v "^--- Output ---" | \
                grep -v "^--- End Output ---" | \
                grep -v "^--- Debug Info ---" | \
                grep -v "^ret_str length:" | \
                grep -v "^fail_str length:" | \
                grep -vE "^[0-9]{1,2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?:" | \
                grep -vE "^\\*\\* .* \\*\\*:" | \
                grep -vE "G_LOG_LEVEL" | \
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$actual_content" ]; then
                # There's actual command output but no expected file - this might be a missing expected file
                echo -e "${YELLOW}Note: Expected stdout file not found: $expected_file (skipping stdout comparison)${NC}" >&2
            fi
            # If actual_content is empty after filtering, don't show any message - no command output is expected
        fi
    fi
    
    # Return the output content (to stdout, so it can be captured)
    echo "$output"
}

