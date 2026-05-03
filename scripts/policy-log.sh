#!/bin/bash
# PreToolUse hook: advisory logging.
#
# This runs alongside policy-guard.sh. The guard handles blocking;
# this script provides telemetry/feedback on what's flowing through.
#
# Modes:
#   Mode A (standalone): note state-modifying tool calls
#   Mode B (SYMBIONT_MANAGED): outer ORGA Gate enforces; we just defer
#
# Kill switch: .symbiont/disabled silences this hook.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json-extract.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

if [ -f "${PROJECT_ROOT}/.symbiont/disabled" ]; then
    exit 0
fi

TOOL_INPUT=$(cat)
TOOL_NAME=$(json_field "$TOOL_INPUT" tool_name)

if [ -n "${SYMBIONT_MANAGED:-}" ]; then
    printf '{"feedback":"ORGA-managed: outer Gate enforcing (%s)"}\n' "$TOOL_NAME" >&2
    exit 0
fi

# Skip read-only tools — too noisy.
case "$TOOL_NAME" in
    Read|Glob|Grep|LS|View)
        exit 0
        ;;
esac

# Cedar evaluation only fires when the runtime is installed.
if ! command -v symbi >/dev/null 2>&1 || [ ! -d "${PROJECT_ROOT}/policies" ]; then
    exit 0
fi

# Action note (full Cedar decision happens in policy-guard.sh).
printf '{"feedback":"Action logged: %s"}\n' "$TOOL_NAME" >&2
exit 0
