#!/bin/bash
# PostToolUse hook: append every tool invocation to the local audit log.
#
# Modes:
#   Mode A (standalone): write to .symbiont/audit/tool-usage.jsonl
#   Mode B (SYMBIONT_MANAGED): the outer Symbiont runtime journals
#                              cryptographically; we skip to avoid duplication
#
# Kill switch: .symbiont/disabled disables logging too. We still exit 0.
#
# Per the plugin's acceptance criteria, every standalone install gets an
# audit trail by default — no symbiont.toml required.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-extract.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# Kill switch.
if [ -f "${PROJECT_ROOT}/.symbiont/disabled" ]; then
    exit 0
fi

# Mode B — outer runtime journals; we stay silent.
if [ -n "${SYMBIONT_MANAGED:-}" ]; then
    exit 0
fi

TOOL_INPUT=$(cat)
TOOL_NAME=$(json_field "$TOOL_INPUT" tool_name)
[ -z "$TOOL_NAME" ] && TOOL_NAME="unknown"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

LOG_DIR="${PROJECT_ROOT}/.symbiont/audit"
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

# JSON-escape tool name (it shouldn't contain quotes, but be defensive).
TOOL_ESC="${TOOL_NAME//\\/\\\\}"
TOOL_ESC="${TOOL_ESC//\"/\\\"}"

printf '{"timestamp":"%s","tool":"%s","source":"claude-code"}\n' \
    "$TIMESTAMP" "$TOOL_ESC" >> "${LOG_DIR}/tool-usage.jsonl"

exit 0
