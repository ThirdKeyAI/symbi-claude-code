#!/bin/bash
# SessionStart hook.
#
# Responsibilities:
#   1. Detect the available JSON parser (jq / python3) for the other hooks
#      and warn if neither is present.
#   2. Detect sensitive files in the project; if found and the user has not
#      yet customized via .symbiont/local-policy.toml, nudge them toward
#      /symbi-protect.
#   3. (When the symbi runtime is installed) SchemaPin-verify any servers
#      declared in the project's .mcp.json.
#
# Output contract (Claude Code SessionStart hooks):
#   - This hook never blocks the session.
#   - User-facing notices go in a top-level "systemMessage".
#   - Context for the model goes in hookSpecificOutput.additionalContext.
#   - Both are emitted as a SINGLE JSON object on STDOUT with exit 0.
#     (stderr on exit 0 is dropped by the hook contract, which is why the
#     previous {"feedback":...}-on-stderr output never surfaced anywhere.)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-extract.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# Accumulators: SYSMSG -> user-visible one-liner(s); CONTEXT -> model context.
SYSMSG=""
CONTEXT=""

add_sysmsg() { if [ -z "$SYSMSG" ]; then SYSMSG="$1"; else SYSMSG="$SYSMSG | $1"; fi; }
add_context() { if [ -z "$CONTEXT" ]; then CONTEXT="$1"; else CONTEXT="$CONTEXT; $1"; fi; }

# Emit a single SessionStart hook JSON object (if we have anything to say)
# on stdout, then exit 0. Strings are JSON-escaped for backslash and quote;
# we keep all messages single-line so no newline escaping is needed.
emit_and_exit() {
    local parts=()
    if [ -n "$SYSMSG" ]; then
        local sm="${SYSMSG//\\/\\\\}"; sm="${sm//\"/\\\"}"
        parts+=("\"systemMessage\":\"$sm\"")
    fi
    if [ -n "$CONTEXT" ]; then
        local cx="${CONTEXT//\\/\\\\}"; cx="${cx//\"/\\\"}"
        parts+=("\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$cx\"}")
    fi
    if [ "${#parts[@]}" -gt 0 ]; then
        local IFS=','
        printf '{%s}\n' "${parts[*]}"
    fi
    exit 0
}

# Kill switch — one quiet line so the user remembers protection is off.
if [ -f "${PROJECT_ROOT}/.symbiont/disabled" ]; then
    add_sysmsg "Symbiont plugin disabled (.symbiont/disabled present). Run /symbi-enable to restore protection."
    emit_and_exit
fi

# Mode B — runtime is the parent process; just announce we're alive.
if [ -n "${SYMBIONT_MANAGED:-}" ]; then
    add_context "Symbiont ORGA-managed mode active: the outer runtime Gate enforces policy; plugin hooks defer."
    emit_and_exit
fi

# ---------------------------------------------------------------------------
# JSON backend availability
# ---------------------------------------------------------------------------
backend=$(json_backend)
if [ "$backend" = "bash" ]; then
    add_sysmsg "Symbiont: jq and python3 not found — hooks are using the limited bash JSON fallback. Install jq for best results (apt install jq / brew install jq)."
fi

# ---------------------------------------------------------------------------
# Sensitive-file nudge
#
# Only fires if (a) sensitive files exist at depth 1-2 and (b) the user has
# not yet created .symbiont/local-policy.toml. Once they've customized, we
# stop nagging.
# ---------------------------------------------------------------------------
nudge_for_secrets() {
    [ -f "${PROJECT_ROOT}/.symbiont/local-policy.toml" ] && return 0

    # find with -maxdepth 2 scans project root + 1 level deep. We avoid
    # recursive scans — fast and bounded.
    local matches
    matches=$(find "$PROJECT_ROOT" -maxdepth 2 \
        \( -name '.env' -o -name '.env.*' -o -name 'id_rsa' \
           -o -name 'id_ed25519' -o -name 'id_ecdsa' \
           -o -name '*.pem' -o -name '*.key' \
           -o -name '.ssh' -o -name '.aws' \) \
        -not -path '*/node_modules/*' -not -path '*/.git/*' \
        2>/dev/null \
        | grep -vE '\.env\.(example|sample|test)$' \
        | head -n 20)

    if [ -n "$matches" ]; then
        local n
        n=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
        add_sysmsg "Symbiont is blocking reads of ${n} sensitive path(s). Run /symbi-protect to customize or /symbi-disable to opt out."
        add_context "Symbiont built-in deny patterns are active (no config required): reads of .env/.env.*, .ssh/, .aws/, .gcp/, .npmrc, *.pem, *.key, id_rsa*, secrets/, credentials/ are blocked; writes additionally block .github/workflows/; dangerous bash commands (rm -rf /, git push --force, curl|sh, chmod 777, mkfs, dd if=, fork bombs) are blocked. Add a .symbiont/local-policy.toml to extend or relax these."
    fi
}
nudge_for_secrets

# ---------------------------------------------------------------------------
# Runtime-aware features (only when symbi binary is present)
# ---------------------------------------------------------------------------
if ! command -v symbi >/dev/null 2>&1; then
    # Runtime not installed — that's fine, plugin works without it.
    emit_and_exit
fi

VERSION=$(symbi --version 2>/dev/null || echo "unknown")
add_context "Symbiont runtime active (${VERSION})."
MCP_CONFIG="${PROJECT_ROOT}/.mcp.json"

if [ -f "$MCP_CONFIG" ]; then
    # Enumerate server names. jq is cleanest; python3 is the fallback; for
    # the bash-only path we skip (rare).
    SERVERS=""
    if command -v jq >/dev/null 2>&1; then
        SERVERS=$(jq -r '.mcpServers | keys[]?' "$MCP_CONFIG" 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
        SERVERS=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    for k in (data.get("mcpServers") or {}).keys():
        print(k)
except Exception:
    pass
' "$MCP_CONFIG" 2>/dev/null)
    fi

    if [ -n "$SERVERS" ]; then
        FAILED=()
        UNSIGNED=()
        while IFS= read -r server; do
            [ -z "$server" ] && continue
            if RESULT=$(symbi schemapin verify --mcp-server "$server" --config "$MCP_CONFIG" 2>&1); then
                continue
            else
                if echo "$RESULT" | grep -qi "no signature\|unsigned"; then
                    UNSIGNED+=("$server")
                else
                    FAILED+=("$server")
                fi
            fi
        done <<< "$SERVERS"

        if [ ${#FAILED[@]} -gt 0 ]; then
            add_sysmsg "SchemaPin verification FAILED for MCP server(s): ${FAILED[*]} — run /symbi-verify."
        fi
        if [ ${#UNSIGNED[@]} -gt 0 ]; then
            add_sysmsg "Unsigned MCP server(s): ${UNSIGNED[*]} — consider /symbi-pin."
        fi
    fi
fi

emit_and_exit
