#!/bin/bash
# SessionStart hook.
#
# Two responsibilities:
#   1. Detect available JSON parser (jq / python3) for the other hooks
#      and print a one-line nudge if neither is present.
#   2. Detect sensitive files in the project; if found and the user has
#      not yet customized via .symbiont/local-policy.toml, print a single
#      line pointing them at /symbi-protect.
#   3. (When the symbi runtime is installed) SchemaPin-verify any servers
#      declared in the project's .mcp.json.
#
# The hook never blocks the session and never requires user action. All
# output is "feedback" channel and capped at one or two lines.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-extract.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# Kill switch — stay completely silent.
if [ -f "${PROJECT_ROOT}/.symbiont/disabled" ]; then
    echo '{"feedback":"Symbiont plugin disabled (.symbiont/disabled marker present). Run /symbi-enable to restore."}' >&2
    exit 0
fi

# Mode B — runtime is the parent process; just announce we're alive.
if [ -n "${SYMBIONT_MANAGED:-}" ]; then
    echo '{"feedback":"Symbiont ORGA-managed mode active"}' >&2
    exit 0
fi

# ---------------------------------------------------------------------------
# JSON backend availability
# ---------------------------------------------------------------------------
backend=$(json_backend)
if [ "$backend" = "bash" ]; then
    echo '{"feedback":"Symbiont: jq and python3 not found. Hook scripts using bash JSON fallback (limited). Install jq for best results: apt install jq / brew install jq"}' >&2
fi

# ---------------------------------------------------------------------------
# Sensitive-file nudge
#
# Only fires if (a) sensitive files exist at depth 1-2 and (b) the user
# has not yet created .symbiont/local-policy.toml. Once they've customized,
# we stop nagging.
# ---------------------------------------------------------------------------
nudge_for_secrets() {
    [ -f "${PROJECT_ROOT}/.symbiont/local-policy.toml" ] && return 0

    # Use find with -maxdepth 2 to scan project root + 1 level deep.
    # We intentionally avoid -name "*" recursive scans — fast and bounded.
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
        printf '{"feedback":"Symbiont is blocking reads of %s sensitive path(s). Run /symbi-protect to customize or /symbi-disable to opt out."}\n' "$n" >&2
    fi
}
nudge_for_secrets

# ---------------------------------------------------------------------------
# Runtime-aware features (only when symbi binary is present)
# ---------------------------------------------------------------------------
if ! command -v symbi >/dev/null 2>&1; then
    # Runtime not installed — that's fine, plugin works without it.
    exit 0
fi

VERSION=$(symbi --version 2>/dev/null || echo "unknown")
MCP_CONFIG="${PROJECT_ROOT}/.mcp.json"
MSG="Symbiont runtime active (${VERSION})"

if [ -f "$MCP_CONFIG" ]; then
    # Use a JSON helper to enumerate server names. Only jq supports this
    # cleanly; for python3 we shell out, for bash we skip (rare path).
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
            MSG="$MSG | SchemaPin FAILED: ${FAILED[*]} -- run /symbi-verify"
        fi
        if [ ${#UNSIGNED[@]} -gt 0 ]; then
            MSG="$MSG | Unsigned MCP servers: ${UNSIGNED[*]} -- consider /symbi-pin"
        fi
    fi
fi

printf '{"feedback":"%s"}\n' "$MSG" >&2
exit 0
