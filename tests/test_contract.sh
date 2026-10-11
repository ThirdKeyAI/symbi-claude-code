#!/bin/bash
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if python3 -I "$TESTS_DIR/test_contract.py"; then
    printf 'PASS  shared parser and runtime contract regression suite\n'
else
    printf 'FAIL  shared parser and runtime contract regression suite\n'
    exit 1
fi
