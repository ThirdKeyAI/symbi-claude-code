#!/bin/bash
# Claude Code adapter for the policy engine.
#
# All policy semantics live in scripts/core/decide.sh — this file only
# translates between Claude Code's PreToolUse contract and the engine's
# harness-free interface:
#
#   in   Claude PreToolUse JSON on stdin  ->  <action> <target>
#   out  allow                            ->  exit 0, no output
#        warn<TAB><reason>                ->  stdout {"systemMessage":...}, exit 0
#        deny<TAB><reason>                ->  stderr plain text, exit 2
#
# Exit code 2 + plain stderr is Claude's blocking contract, and it fails
# CLOSED: even if the message had a formatting bug, the non-zero exit still
# blocks the call. We deliberately do NOT emit permissionDecision="allow"
# on the warn path — that would auto-approve the tool and bypass the user's
# own permission settings.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-extract.sh"

CORE="${SCRIPT_DIR}/core/decide.sh"
export SYMBIONT_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

TOOL_INPUT=$(cat)
TOOL_NAME=$(json_field "$TOOL_INPUT" tool_name)

_file_path() {
    local p
    p=$(json_field "$TOOL_INPUT" tool_input.file_path)
    [ -z "$p" ] && p=$(json_field "$TOOL_INPUT" tool_input.path)
    printf '%s' "$p"
}

# Map Claude's tool vocabulary onto the engine's three actions.
case "$TOOL_NAME" in
    Read)
        ACTION="read"; TARGET=$(_file_path) ;;
    Glob|Grep|LS|View)
        # Metadata-only enumeration — never opens file contents. Allow.
        exit 0 ;;
    Write|Edit|MultiEdit)
        ACTION="write"; TARGET=$(_file_path) ;;
    Bash)
        ACTION="exec"; TARGET=$(json_field "$TOOL_INPUT" tool_input.command) ;;
    *)
        # Everything else (MCP tools, etc.) has no built-in rules, but still
        # reaches Cedar when the runtime is installed.
        ACTION="invoke"; TARGET="$TOOL_NAME" ;;
esac

VERDICT_LINE=$(bash "$CORE" "$ACTION" "$TARGET")
VERDICT="${VERDICT_LINE%%$'\t'*}"
REASON="${VERDICT_LINE#*$'\t'}"
[ "$REASON" = "$VERDICT_LINE" ] && REASON=""

case "$VERDICT" in
    deny)
        printf '%s\n' "$REASON" >&2
        exit 2
        ;;
    warn)
        msg="${REASON//\\/\\\\}"
        msg="${msg//\"/\\\"}"
        printf '{"systemMessage":"%s"}\n' "$msg"
        exit 0
        ;;
    *)
        # allow, or an unrecognized verdict. Fail open, consistent with the
        # engine's posture: never block on bytes we could not interpret.
        exit 0
        ;;
esac
