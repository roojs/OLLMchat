#!/bin/bash
# Bubble tests part 5: seccomp evidence regressions (no false positives on benign commands)

set -e

STOP_ON_FAILURE=false
if [ "${1:-}" = "--stop-on-failure" ] || [ "${1:-}" = "-x" ]; then
    STOP_ON_FAILURE=true
    shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${1:-$PROJECT_ROOT/build}"
BUILD_DIR="$(cd "$SCRIPT_DIR" && cd "$BUILD_DIR" && pwd)"
source "$SCRIPT_DIR/test-common.sh"

OC_TEST_BUBBLE="$BUILD_DIR/oc-test-bubble"
TEST_DIR="$BUILD_DIR/ollmchat-testing"
TEST_PROJECT_DIR="$TEST_DIR/project"
TEST_DB="$BUILD_DIR/test-bubble.db"
DATA_DIR="$SCRIPT_DIR/data"
export TEST_DB
export TEST_PROJECT_DIR

bubble_expect_no_fs () {
    local testname="$1"
    local command="$2"
    local output
    output=$("$OC_TEST_BUBBLE" --project="$TEST_PROJECT_DIR" --allow-write=project --expect=no-fs "$command" 2>&1)
    test_pass "$testname: no seccomp fs appendix"
}

bubble_expect_fs () {
    local testname="$1"
    local command="$2"
    if "$OC_TEST_BUBBLE" --project="$TEST_PROJECT_DIR" --allow-write=project --expect=fs "$command" >/dev/null 2>&1; then
        test_pass "$testname: seccomp fs appendix present"
    else
        test_fail "$testname: expected seccomp fs appendix"
    fi
}

test_seccomp_ls_redirect_dev_null () {
    echo "=== Test 7.1: ls redirect to /dev/null (no fs false positive) ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    bubble_expect_no_fs "test_seccomp_ls_redirect_dev_null" "ls > /dev/null"
}

test_seccomp_bash_ls_redirect_dev_null () {
    echo "=== Test 7.2: bash ls redirect to /dev/null (no /dev/tty false positive) ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    bubble_expect_no_fs "test_seccomp_bash_ls_redirect_dev_null" "/bin/bash -c 'ls > /dev/null'"
}

test_seccomp_failed_command_no_spurious_socket () {
    echo "=== Test 7.3: failed command (no spurious network appendix) ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    local testname="test_seccomp_failed_command_no_spurious_socket"
    local output
    output=$("$OC_TEST_BUBBLE" --project="$TEST_PROJECT_DIR" --allow-write=project --expect=no-net "false" 2>&1)
    if echo "$output" | grep -q "networking was disabled"; then
        test_fail "$testname: unexpected network appendix for false"
    else
        test_pass "$testname: no network appendix for false"
    fi
}

test_seccomp_real_write_still_reported () {
    echo "=== Test 7.4: write outside sandbox still reported ==="
    reset_test_state
    mkdir -p "$TEST_PROJECT_DIR"
    bubble_expect_fs "test_seccomp_real_write_still_reported" "touch /etc/.oc-test-bubble-deleteme"
    rm -f /etc/.oc-test-bubble-deleteme
}

run_part_5 () {
    run_test test_seccomp_ls_redirect_dev_null
    run_test test_seccomp_bash_ls_redirect_dev_null
    run_test test_seccomp_failed_command_no_spurious_socket
    run_test test_seccomp_real_write_still_reported
}

main () {
    echo "Starting bubblewrap seccomp regression tests (part 5)..."
    echo "Test directory: $TEST_DIR"
    echo "Project directory: $TEST_PROJECT_DIR"
    echo ""
    setup_test_env
    run_part_5
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
