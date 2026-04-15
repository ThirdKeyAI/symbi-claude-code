#!/bin/bash
# SessionStart hook: verify environment and SchemaPin-verify pinned MCP servers.
# Supports two modes:
#   Mode A (standalone): Check for required binaries + verify pinned schemas
#   Mode B (SYMBIONT_MANAGED): Already inside runtime, report managed mode

# Mode B: Inside CliExecutor -- symbi is the parent process
if [ -n "${SYMBIONT_MANAGED:-}" ]; then
    echo '{"feedback": "Symbiont ORGA-managed mode active"}' >&2
    exit 0
fi

# Mode A: Standalone plugin

if ! command -v jq &> /dev/null; then
    echo '{"feedback": "jq is not installed. Hook scripts require jq for JSON parsing. Install via: apt install jq / brew install jq"}' >&2
fi

if ! command -v symbi &> /dev/null; then
    echo '{"feedback": "Symbiont (symbi) is not installed or not on PATH. Some governance features will be unavailable. Run /symbi-status for installation instructions."}' >&2
    exit 0
fi

VERSION=$(symbi --version 2>/dev/null || echo "unknown")

# Verify pinned MCP server schemas if a project .mcp.json is present.
# Non-blocking: warnings only -- users can investigate via /symbi-verify.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
MCP_CONFIG="$PROJECT_ROOT/.mcp.json"
MSG="Symbiont governance active (${VERSION})"

if [ -f "$MCP_CONFIG" ] && command -v jq &> /dev/null; then
    SERVERS=$(jq -r '.mcpServers | keys[]?' "$MCP_CONFIG" 2>/dev/null)
    if [ -n "$SERVERS" ]; then
        FAILED=()
        UNSIGNED=()
        while IFS= read -r server; do
            [ -z "$server" ] && continue
            # symbi verify exits non-zero on tamper; distinguishes unsigned via stderr.
            RESULT=$(symbi schemapin verify --mcp-server "$server" --config "$MCP_CONFIG" 2>&1)
            STATUS=$?
            if [ $STATUS -ne 0 ]; then
                if echo "$RESULT" | grep -qi "no signature\|unsigned"; then
                    UNSIGNED+=("$server")
                else
                    FAILED+=("$server")
                fi
            fi
        done <<< "$SERVERS"

        if [ ${#FAILED[@]} -gt 0 ]; then
            MSG="$MSG | SchemaPin FAILED: ${FAILED[*]} -- schemas modified since signing, run /symbi-verify"
        fi
        if [ ${#UNSIGNED[@]} -gt 0 ]; then
            MSG="$MSG | Unsigned MCP servers: ${UNSIGNED[*]} -- consider /symbi-pin"
        fi
    fi
fi

printf '{"feedback": "%s"}\n' "$MSG" >&2
exit 0
