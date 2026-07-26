#!/bin/bash
# Cursor adapter for the policy engine.
#
# All policy semantics live in scripts/core/decide.sh — this file only
# translates between Cursor's hook contract and the engine's harness-free
# interface:
#
#   in   Cursor hook JSON on stdin  ->  <action> <target>
#   out  allow  ->  {"permission":"allow"}
#        warn   ->  {"permission":"ask", ...}    — Cursor prompts the user
#        deny   ->  {"permission":"deny", ...}
#
# Registered on `preToolUse`, which fires for Shell, Read, Write, MCP and
# Task calls. The payload readers below also accept the narrower
# `beforeShellExecution` / `beforeReadFile` shapes (command / file_path at
# the top level) so the adapter still enforces if it is wired to those
# events instead — silently no-opping is the one failure mode a security
# hook must not have.
#
# Note the deliberate divergence from the Claude adapter: Claude has no
# "ask" verdict, so a warn there proceeds with a systemMessage. Cursor does
# have one, so a warn becomes a user prompt. Same policy, stricter harness.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-extract.sh"

CORE="${SCRIPT_DIR}/core/decide.sh"

PAYLOAD=$(cat)

# Cursor reports the workspace on the payload; fall back to the process cwd.
CURSOR_CWD=$(json_field "$PAYLOAD" cwd)
export SYMBIONT_PROJECT_DIR="${CURSOR_CWD:-$PWD}"

TOOL_NAME=$(json_field "$PAYLOAD" tool_name)

# Accept both the preToolUse shape (nested under tool_input) and the
# per-event shapes (top level).
COMMAND=$(json_field "$PAYLOAD" tool_input.command)
[ -z "$COMMAND" ] && COMMAND=$(json_field "$PAYLOAD" command)

FILE_PATH=$(json_field "$PAYLOAD" tool_input.file_path)
[ -z "$FILE_PATH" ] && FILE_PATH=$(json_field "$PAYLOAD" tool_input.path)
[ -z "$FILE_PATH" ] && FILE_PATH=$(json_field "$PAYLOAD" file_path)

# Derive the action from the payload shape first and the tool name only as a
# read/write tie-break. Cursor's tool vocabulary is not contractual, so we
# never depend on an exact name table.
if [ -n "$COMMAND" ]; then
    ACTION="exec"; TARGET="$COMMAND"
elif [ -n "$FILE_PATH" ]; then
    case "$TOOL_NAME" in
        *[Ww]rite*|*[Ee]dit*|*[Aa]pply*|*[Cc]reate*|*[Dd]elete*) ACTION="write" ;;
        *) ACTION="read" ;;
    esac
    TARGET="$FILE_PATH"
else
    # No file and no command: nothing built-in applies, but Cedar still sees it.
    ACTION="invoke"; TARGET="$TOOL_NAME"
fi

VERDICT_LINE=$(bash "$CORE" "$ACTION" "$TARGET")
VERDICT="${VERDICT_LINE%%$'\t'*}"
REASON="${VERDICT_LINE#*$'\t'}"
[ "$REASON" = "$VERDICT_LINE" ] && REASON=""

# Cursor enforces on "permission" alone; the message fields are UX. If a
# Cursor build spells them differently the block still lands, it just loses
# the explanation — so permission is the only field we depend on.
emit() {
    local permission="$1" msg="$2"
    msg="${msg//\\/\\\\}"
    msg="${msg//\"/\\\"}"
    if [ -z "$msg" ]; then
        printf '{"permission":"%s"}\n' "$permission"
    else
        printf '{"permission":"%s","user_message":"%s","agent_message":"%s"}\n' \
            "$permission" "$msg" "$msg"
    fi
    exit 0
}

case "$VERDICT" in
    deny) emit deny "$REASON" ;;
    warn) emit ask  "$REASON" ;;
    # allow, or an unrecognized verdict. Fail open, consistent with the
    # engine's posture: never block on bytes we could not interpret.
    *)    emit allow "" ;;
esac
