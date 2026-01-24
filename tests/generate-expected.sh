#!/bin/bash
# Helper script to generate expected files from test run output
# Usage: ./generate-expected.sh [test-script]
#   If test-script is provided, runs that test first
#   Otherwise, uses existing output files in TEST_DIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
TEST_DIR="$HOME/.cache/ollmchat/testing"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Generating Expected Test Files ==="
echo ""

# If test script provided, run it first
if [ $# -gt 0 ]; then
    TEST_SCRIPT="$1"
    if [ ! -f "$TEST_SCRIPT" ]; then
        echo "Error: Test script not found: $TEST_SCRIPT"
        exit 1
    fi
    
    echo "Running test script: $TEST_SCRIPT"
    echo "Note: Tests may fail, but we need the output files..."
    echo ""
    
    # Set environment variable to prevent cleanup
    export GENERATE_EXPECTED_MODE=1
    
    # Run test script (don't exit on failure - we want the output files)
    set +e
    bash "$TEST_SCRIPT" || true
    set -e
    
    # Copy files immediately after test run (before potential cleanup)
    if [ -d "$TEST_DIR" ]; then
        echo ""
        echo "Copying files from test run..."
        STDOUT_GENERATED=0
        DB_GENERATED=0
        # Find and copy stdout files
        # Map test names to data file prefixes
        while IFS= read -r stdout_file; do
            basename=$(basename "$stdout_file" -stdout.txt)
            # Map test names to 2.edit-test-XX format
            data_prefix=""
            case "$basename" in
                test_complete_file_new) data_prefix="2.edit-test-1" ;;
                test_complete_file_overwrite) data_prefix="2.edit-test-2" ;;
                test_edit_mode_single) data_prefix="2.edit-test-3" ;;
                test_edit_mode_multiple) data_prefix="2.edit-test-4" ;;
                test_edit_mode_insert_end) data_prefix="2.edit-test-5" ;;
                test_line_counting_accuracy_1) data_prefix="2.edit-test-6-1" ;;
                test_line_counting_accuracy_2) data_prefix="2.edit-test-6-2" ;;
                test_line_counting_accuracy_3) data_prefix="2.edit-test-6-3" ;;
                test_line_counting_accuracy_4) data_prefix="2.edit-test-6-4" ;;
                test_backup_verification_project) data_prefix="2.edit-test-7-project" ;;
                test_backup_verification_outside) data_prefix="2.edit-test-7-outside" ;;
                test_no_race_conditions_1) data_prefix="2.edit-test-8-1" ;;
                test_no_race_conditions_2) data_prefix="2.edit-test-8-2" ;;
                test_no_race_conditions_3) data_prefix="2.edit-test-8-3" ;;
                *) data_prefix="$basename" ;;  # Use testname as fallback
            esac
            expected_file="$DATA_DIR/${data_prefix}-stdout.txt"
            if [ -f "$stdout_file" ]; then
                cp "$stdout_file" "$expected_file"
                echo -e "${GREEN}Generated:${NC} $(basename "$expected_file")"
                ((STDOUT_GENERATED++)) || true
            fi
        done < <(find "$TEST_DIR" -name "*-stdout.txt" -type f 2>/dev/null)
        
        # Find and copy db files (INSERT-only dumps)
        while IFS= read -r db_file; do
            basename=$(basename "$db_file" -db.sql)
            # Map test names to 2.edit-test-XX format
            data_prefix=""
            case "$basename" in
                test_complete_file_new) data_prefix="2.edit-test-1" ;;
                test_complete_file_overwrite) data_prefix="2.edit-test-2" ;;
                test_edit_mode_single) data_prefix="2.edit-test-3" ;;
                test_edit_mode_multiple) data_prefix="2.edit-test-4" ;;
                test_edit_mode_insert_end) data_prefix="2.edit-test-5" ;;
                test_line_counting_accuracy) data_prefix="2.edit-test-6" ;;
                test_backup_verification) data_prefix="2.edit-test-7" ;;
                test_no_race_conditions) data_prefix="2.edit-test-8" ;;
                *) data_prefix="$basename" ;;  # Use testname as fallback
            esac
            expected_file="$DATA_DIR/${data_prefix}-db.sql"
            if [ -f "$db_file" ]; then
                cp "$db_file" "$expected_file"
                echo -e "${GREEN}Generated:${NC} $(basename "$expected_file")"
                ((DB_GENERATED++)) || true
            fi
        done < <(find "$TEST_DIR" -name "*-db.sql" -type f 2>/dev/null)
    fi
    echo ""
fi

# Check if test directory exists (for case where script wasn't provided)
if [ $# -eq 0 ] && [ ! -d "$TEST_DIR" ]; then
    echo "Error: Test directory not found: $TEST_DIR"
    echo "Please run the tests first, or provide a test script to run"
    exit 1
fi

# If we already copied files above, skip this section
if [ $# -eq 0 ] || [ -z "${STDOUT_GENERATED:-}" ]; then
    echo "Scanning for output files in: $TEST_DIR"
    echo ""
    
    # Find all stdout files and copy to expected
    STDOUT_GENERATED=0
    while IFS= read -r stdout_file; do
        basename=$(basename "$stdout_file" -stdout.txt)
        # Map test names to 2.edit-test-XX format
        data_prefix=""
        case "$basename" in
            test_complete_file_new) data_prefix="2.edit-test-1" ;;
            test_complete_file_overwrite) data_prefix="2.edit-test-2" ;;
            test_edit_mode_single) data_prefix="2.edit-test-3" ;;
            test_edit_mode_multiple) data_prefix="2.edit-test-4" ;;
            test_edit_mode_insert_end) data_prefix="2.edit-test-5" ;;
            test_line_counting_accuracy_1) data_prefix="2.edit-test-6-1" ;;
            test_line_counting_accuracy_2) data_prefix="2.edit-test-6-2" ;;
            test_line_counting_accuracy_3) data_prefix="2.edit-test-6-3" ;;
            test_line_counting_accuracy_4) data_prefix="2.edit-test-6-4" ;;
            test_backup_verification_project) data_prefix="2.edit-test-7-project" ;;
            test_backup_verification_outside) data_prefix="2.edit-test-7-outside" ;;
            test_no_race_conditions_1) data_prefix="2.edit-test-8-1" ;;
            test_no_race_conditions_2) data_prefix="2.edit-test-8-2" ;;
            test_no_race_conditions_3) data_prefix="2.edit-test-8-3" ;;
            *) data_prefix="$basename" ;;  # Use testname as fallback
        esac
        expected_file="$DATA_DIR/${data_prefix}-stdout.txt"
        
        if [ -f "$stdout_file" ]; then
            cp "$stdout_file" "$expected_file"
            echo -e "${GREEN}Generated:${NC} $(basename "$expected_file")"
            ((STDOUT_GENERATED++)) || true
        fi
    done < <(find "$TEST_DIR" -name "*-stdout.txt" -type f 2>/dev/null)
    
    # Find all db dump files and copy to expected (INSERT-only dumps)
    DB_GENERATED=0
    while IFS= read -r db_file; do
        basename=$(basename "$db_file" -db.sql)
        # Map test names to 2.edit-test-XX format
        data_prefix=""
        case "$basename" in
            test_complete_file_new) data_prefix="2.edit-test-1" ;;
            test_complete_file_overwrite) data_prefix="2.edit-test-2" ;;
            test_edit_mode_single) data_prefix="2.edit-test-3" ;;
            test_edit_mode_multiple) data_prefix="2.edit-test-4" ;;
            test_edit_mode_insert_end) data_prefix="2.edit-test-5" ;;
            test_line_counting_accuracy) data_prefix="2.edit-test-6" ;;
            test_backup_verification) data_prefix="2.edit-test-7" ;;
            test_no_race_conditions) data_prefix="2.edit-test-8" ;;
            *) data_prefix="$basename" ;;  # Use testname as fallback
        esac
        expected_file="$DATA_DIR/${data_prefix}-db.sql"
        
        if [ -f "$db_file" ]; then
            cp "$db_file" "$expected_file"
            echo -e "${GREEN}Generated:${NC} $(basename "$expected_file")"
            ((DB_GENERATED++)) || true
        fi
    done < <(find "$TEST_DIR" -name "*-db.sql" -type f 2>/dev/null)
fi

echo ""
echo "=== Summary ==="
echo -e "${GREEN}Generated $STDOUT_GENERATED stdout expected files${NC}"
echo -e "${GREEN}Generated $DB_GENERATED database expected files${NC}"
echo ""
echo "Files are in: $DATA_DIR"
echo ""
echo -e "${YELLOW}Note: Please review the generated files before committing!${NC}"
echo "Some values (like file IDs, timestamps, dates) may need to be normalized."

