#!/bin/bash
# Top-level test runner. Calls each test_*.sh in this directory.
# Each test file should print PASS/FAIL lines and exit non-zero on failure.

set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
total_pass=0
total_fail=0

for tf in "$TESTS_DIR"/test_*.sh; do
    [ -f "$tf" ] || continue
    echo ""
    echo "==> $(basename "$tf")"
    out=$(bash "$tf" 2>&1)
    rc=$?
    echo "$out"
    p=$(printf '%s\n' "$out" | grep -cE '^PASS' || true)
    f=$(printf '%s\n' "$out" | grep -cE '^FAIL' || true)
    total_pass=$((total_pass + p))
    total_fail=$((total_fail + f))
    if [ $rc -ne 0 ] && [ "$f" -eq 0 ]; then
        # Test runner exited non-zero with no FAIL line — count as failure.
        total_fail=$((total_fail + 1))
    fi
done

echo ""
echo "================================================"
echo "Total: $total_pass passed, $total_fail failed"
echo "================================================"
[ "$total_fail" -eq 0 ]
