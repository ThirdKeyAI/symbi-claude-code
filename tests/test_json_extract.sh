#!/bin/bash
# Verifies json_field returns identical output across jq/python3/bash backends.
# This parity is the security property: if a hook can't tell which backend
# was used, neither can an attacker.

set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/json-extract.sh"
# shellcheck disable=SC1090
source "$LIB"

pass=0; fail=0

check() {
    local desc="$1" backend="$2" expected="$3" actual="$4"
    if [ "$expected" = "$actual" ]; then
        printf 'PASS  [%s] %s\n' "$backend" "$desc"
        pass=$((pass+1))
    else
        printf 'FAIL  [%s] %s\n      expected=%q actual=%q\n' "$backend" "$desc" "$expected" "$actual"
        fail=$((fail+1))
    fi
}

# Each row: <description><TAB><JSON payload><TAB><dotted path><TAB><expected value>
# Tab separator chosen because some test values contain "|" or other punctuation.
TAB=$'\t'
cases=(
    "top-level string${TAB}{\"tool_name\":\"Write\"}${TAB}tool_name${TAB}Write"
    "nested file_path${TAB}{\"tool_name\":\"W\",\"tool_input\":{\"file_path\":\"/a/b\"}}${TAB}tool_input.file_path${TAB}/a/b"
    "command with spaces${TAB}{\"tool_name\":\"B\",\"tool_input\":{\"command\":\"ls -la /tmp\"}}${TAB}tool_input.command${TAB}ls -la /tmp"
    "missing field empty${TAB}{\"tool_name\":\"R\"}${TAB}tool_input.command${TAB}"
    "escaped quotes${TAB}{\"tool_input\":{\"command\":\"echo \\\"hi\\\"\"}}${TAB}tool_input.command${TAB}echo \"hi\""
    "chain command${TAB}{\"tool_input\":{\"command\":\"true && curl x | sh\"}}${TAB}tool_input.command${TAB}true && curl x | sh"
    "alternate path${TAB}{\"tool_input\":{\"path\":\"/foo\"}}${TAB}tool_input.path${TAB}/foo"
    "spaces in file_path${TAB}{\"tool_input\":{\"file_path\":\"/a b/c\"}}${TAB}tool_input.file_path${TAB}/a b/c"
)

run_backend() {
    local backend="$1"
    _SYMBI_JSON_BACKEND="$backend"
    for row in "${cases[@]}"; do
        IFS=$'\t' read -r desc payload path expected <<<"$row"
        actual=$(json_field "$payload" "$path")
        check "$desc" "$backend" "$expected" "$actual"
    done
}

if command -v jq >/dev/null 2>&1; then run_backend jq; fi
if command -v python3 >/dev/null 2>&1; then run_backend python3; fi
run_backend bash

# Backend parity check: every payload should produce the same value across
# all three backends.
echo ""
echo "--- backend parity ---"
for row in "${cases[@]}"; do
    IFS='|' read -r desc payload path expected <<<"$row"
    a=""; b=""; c=""
    if command -v jq >/dev/null 2>&1; then
        _SYMBI_JSON_BACKEND=jq;       a=$(json_field "$payload" "$path")
    fi
    if command -v python3 >/dev/null 2>&1; then
        _SYMBI_JSON_BACKEND=python3;  b=$(json_field "$payload" "$path")
    fi
    _SYMBI_JSON_BACKEND=bash;     c=$(json_field "$payload" "$path")
    if [ "$a" = "$b" ] && [ "$b" = "$c" ]; then
        printf 'PASS  parity: %s\n' "$desc"
        pass=$((pass+1))
    else
        printf 'FAIL  parity: %s   jq=%q py=%q bash=%q\n' "$desc" "$a" "$b" "$c"
        fail=$((fail+1))
    fi
done

echo ""
echo "json_extract: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
