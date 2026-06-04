#!/bin/bash
# Output-contract tests for scripts/install-check.sh (SessionStart hook).
# Verifies notices land on STDOUT as a SessionStart JSON object (the channel
# the hook contract actually surfaces), not on the dropped stderr+exit0 path.

set -u
CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/install-check.sh"
[ -x "$CHECK" ] || chmod +x "$CHECK"

pass=0; fail=0

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "--- sensitive-file nudge ---"
# A project with a secret and no local-policy.toml should nudge the user via
# a stdout systemMessage and exit 0.
: > "$WORKDIR/.env"
STDOUT=$(env CLAUDE_PROJECT_DIR="$WORKDIR" SYMBIONT_MANAGED= bash "$CHECK" 2>/dev/null); rc=$?
if [ "$rc" = "0" ] \
   && printf '%s' "$STDOUT" | grep -q '"systemMessage"' \
   && printf '%s' "$STDOUT" | grep -q '/symbi-protect'; then
    printf 'PASS  nudge on stdout systemMessage\n'; pass=$((pass+1))
else
    printf 'FAIL  nudge channel (rc=%s stdout=[%s])\n' "$rc" "$STDOUT"; fail=$((fail+1))
fi
# Context details should ride on a SessionStart hookSpecificOutput block.
if printf '%s' "$STDOUT" | grep -q 'SessionStart'; then
    printf 'PASS  hookEventName SessionStart present\n'; pass=$((pass+1))
else
    printf 'FAIL  missing SessionStart hookEventName (stdout=[%s])\n' "$STDOUT"; fail=$((fail+1))
fi

echo ""
echo "--- nudge suppressed once customized ---"
mkdir -p "$WORKDIR/.symbiont"
: > "$WORKDIR/.symbiont/local-policy.toml"
STDOUT=$(env CLAUDE_PROJECT_DIR="$WORKDIR" SYMBIONT_MANAGED= bash "$CHECK" 2>/dev/null); rc=$?
if [ "$rc" = "0" ] && ! printf '%s' "$STDOUT" | grep -q '/symbi-protect'; then
    printf 'PASS  no nudge when local-policy.toml exists\n'; pass=$((pass+1))
else
    printf 'FAIL  nudge should be suppressed (rc=%s stdout=[%s])\n' "$rc" "$STDOUT"; fail=$((fail+1))
fi

echo ""
echo "--- disabled marker ---"
rm -f "$WORKDIR/.symbiont/local-policy.toml"
: > "$WORKDIR/.symbiont/disabled"
STDOUT=$(env CLAUDE_PROJECT_DIR="$WORKDIR" SYMBIONT_MANAGED= bash "$CHECK" 2>/dev/null); rc=$?
if [ "$rc" = "0" ] && printf '%s' "$STDOUT" | grep -q '/symbi-enable'; then
    printf 'PASS  disabled marker notice on stdout\n'; pass=$((pass+1))
else
    printf 'FAIL  disabled notice (rc=%s stdout=[%s])\n' "$rc" "$STDOUT"; fail=$((fail+1))
fi

echo ""
echo "install_check: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
