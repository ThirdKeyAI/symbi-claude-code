#!/bin/bash
# Contract tests for scripts/core/decide.sh.
#
# test_policy_guard.sh already covers policy *semantics* end-to-end through
# the Claude adapter. This file covers the engine's output *contract* — the
# part every future adapter (Cursor, Codex, Gemini) depends on:
#   - one line on stdout: "allow" | "warn<TAB>reason" | "deny<TAB>reason"
#   - exit status is always 0, never the verdict
#   - a buffered warn loses to a later deny

set -u
CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/core/decide.sh"

pass=0; fail=0

# Sets globals LINE and RC.
run_core() {
    local workdir="$1"; shift
    LINE=$(env SYMBIONT_PROJECT_DIR="$workdir" bash "$CORE" "$@" 2>/dev/null)
    RC=$?
}

assert_verdict() {
    local desc="$1" want="$2" action="$3" target="$4" workdir="${5:-$WORKDIR}"
    run_core "$workdir" "$action" "$target"
    local got="${LINE%%$'\t'*}"
    if [ "$got" = "$want" ] && [ "$RC" = "0" ]; then
        printf 'PASS  %s\n' "$desc"; pass=$((pass+1))
    else
        printf 'FAIL  %s (want %s/rc0, got %s/rc%s)\n' "$desc" "$want" "$got" "$RC"; fail=$((fail+1))
    fi
}

assert_has_reason() {
    local desc="$1" action="$2" target="$3" workdir="${4:-$WORKDIR}"
    run_core "$workdir" "$action" "$target"
    # A tab must separate verdict from a non-empty reason.
    if [[ "$LINE" == *$'\t'* ]] && [ -n "${LINE#*$'\t'}" ]; then
        printf 'PASS  %s\n' "$desc"; pass=$((pass+1))
    else
        printf 'FAIL  %s (no tab-separated reason in [%s])\n' "$desc" "$LINE"; fail=$((fail+1))
    fi
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "--- verdict contract ---"
assert_verdict "allow: normal read"   allow read  "/proj/src/main.py"
assert_verdict "deny: read .env"      deny  read  "/foo/.env"
assert_verdict "deny: write workflow" deny  write "/proj/.github/workflows/ci.yml"
assert_verdict "deny: rm -rf /"       deny  exec  "rm -rf /"
assert_has_reason "deny carries a tab-separated reason" exec "rm -rf /"

echo ""
echo "--- exit status is never the verdict ---"
run_core "$WORKDIR" exec "rm -rf /"
if [ "$RC" = "0" ]; then
    printf 'PASS  deny still exits 0\n'; pass=$((pass+1))
else
    printf 'FAIL  deny exited %s, adapters rely on 0\n' "$RC"; fail=$((fail+1))
fi

echo ""
echo "--- empty target fails open ---"
assert_verdict "empty read target" allow read ""
assert_verdict "empty exec target" allow exec ""

echo ""
echo "--- sudo: warn in balanced, deny in strict ---"
assert_verdict "balanced sudo warns" warn exec "sudo apt update"
assert_has_reason "warn carries a reason" exec "sudo apt update"

mkdir -p "$WORKDIR/.symbiont"
cat > "$WORKDIR/.symbiont/local-policy.toml" <<'TOML'
[mode]
mode = "strict"
TOML
assert_verdict "strict sudo denies" deny exec "sudo apt update"

echo ""
echo "--- a buffered warn loses to a later deny ---"
cat > "$WORKDIR/.symbiont/local-policy.toml" <<'TOML'
[deny]
commands = ["apt"]
TOML
# balanced mode: sudo would warn, but the local deny must win.
assert_verdict "sudo warn overridden by local deny" deny exec "sudo apt update"

echo ""
echo "--- kill switch and Mode B allow everything ---"
rm -f "$WORKDIR/.symbiont/local-policy.toml"
touch "$WORKDIR/.symbiont/disabled"
assert_verdict "disabled marker" allow exec "rm -rf /"
rm -f "$WORKDIR/.symbiont/disabled"

LINE=$(env SYMBIONT_MANAGED=true SYMBIONT_PROJECT_DIR="$WORKDIR" bash "$CORE" exec "rm -rf /" 2>/dev/null)
if [ "$LINE" = "allow" ]; then
    printf 'PASS  Mode B defers\n'; pass=$((pass+1))
else
    printf 'FAIL  Mode B defers (got [%s])\n' "$LINE"; fail=$((fail+1))
fi

echo ""
echo "decide: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
