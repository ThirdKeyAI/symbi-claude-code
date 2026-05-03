#!/bin/bash
# audit-log.sh should:
#   - write a JSONL line per tool call to .symbiont/audit/tool-usage.jsonl
#   - skip silently when SYMBIONT_MANAGED is set
#   - skip silently when .symbiont/disabled exists

set -u
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/audit-log.sh"
[ -x "$SCRIPT" ] || chmod +x "$SCRIPT"

pass=0; fail=0
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

run() {
    env CLAUDE_PROJECT_DIR="$WORKDIR" bash "$SCRIPT" <<<"$1" 2>/dev/null
}

# 1. Default: writes to local audit log.
run '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
if [ -f "$WORKDIR/.symbiont/audit/tool-usage.jsonl" ]; then
    line=$(tail -n 1 "$WORKDIR/.symbiont/audit/tool-usage.jsonl")
    if echo "$line" | grep -q '"tool":"Bash"'; then
        printf 'PASS  writes audit line\n'; pass=$((pass+1))
    else
        printf 'FAIL  audit line missing tool field: %s\n' "$line"; fail=$((fail+1))
    fi
else
    printf 'FAIL  audit log file not created\n'; fail=$((fail+1))
fi

# 2. Logs even without symbiont.toml (regression: old behavior gated on it).
rm -rf "$WORKDIR/.symbiont"
[ -f "$WORKDIR/symbiont.toml" ] && rm "$WORKDIR/symbiont.toml"
run '{"tool_name":"Write","tool_input":{"file_path":"/x"}}'
if [ -f "$WORKDIR/.symbiont/audit/tool-usage.jsonl" ]; then
    printf 'PASS  logs without symbiont.toml\n'; pass=$((pass+1))
else
    printf 'FAIL  no audit log when symbiont.toml absent\n'; fail=$((fail+1))
fi

# 3. SYMBIONT_MANAGED skips local logging.
rm -rf "$WORKDIR/.symbiont"
env SYMBIONT_MANAGED=true CLAUDE_PROJECT_DIR="$WORKDIR" bash "$SCRIPT" \
    <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}' 2>/dev/null
if [ ! -d "$WORKDIR/.symbiont/audit" ]; then
    printf 'PASS  Mode B skips local logging\n'; pass=$((pass+1))
else
    printf 'FAIL  Mode B wrote local audit log\n'; fail=$((fail+1))
fi

# 4. .symbiont/disabled marker silences logging.
mkdir -p "$WORKDIR/.symbiont"
touch "$WORKDIR/.symbiont/disabled"
run '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
if [ ! -f "$WORKDIR/.symbiont/audit/tool-usage.jsonl" ]; then
    printf 'PASS  disabled marker silences audit\n'; pass=$((pass+1))
else
    printf 'FAIL  disabled marker did not silence audit\n'; fail=$((fail+1))
fi

echo ""
echo "audit_log: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
