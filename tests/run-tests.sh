#!/bin/bash
# tests/run-tests.sh - Minimal test framework for bash scripts
# Usage: bash tests/run-tests.sh [test_file...]

set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: ${msg:-assertion}\n    expected: '${expected}'\n    actual:   '${actual}'"
    fi
}

assert_file_exists() {
    local path="$1" msg="${2:-file exists: $1}"
    if [ -f "$path" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: ${msg}\n    file not found: ${path}"
    fi
}

assert_exit_code() {
    local expected="$1" msg="${2:-}"
    shift 2
    local actual
    set +e
    "$@" >/dev/null 2>&1
    actual=$?
    set -e
    if [ "$expected" -eq "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: ${msg:-exit code}\n    expected exit: ${expected}\n    actual exit:   ${actual}"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if echo "$haystack" | grep -q "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: ${msg:-contains}\n    expected to contain: '${needle}'\n    in: '${haystack}'"
    fi
}

assert_dir_exists() {
    local path="$1" msg="${2:-dir exists: $1}"
    if [ -d "$path" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: ${msg}\n    directory not found: ${path}"
    fi
}

# Run all test files
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

if [ $# -gt 0 ]; then
    TEST_FILES=("$@")
else
    TEST_FILES=(tests/test_*.sh)
fi

for test_file in "${TEST_FILES[@]}"; do
    if [ ! -f "$test_file" ]; then
        echo "SKIP: $test_file not found"
        continue
    fi
    echo "Running: $test_file"
    source "$test_file"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
    echo -e "\nFailures:$ERRORS"
    exit 1
fi
