#!/bin/bash
# PreToolUse hook: Advisory policy logging for tool execution
# Reads tool invocation from stdin, logs state-modifying actions
#
# NOTE: This is advisory only — it logs actions but does not block them.
# Hard enforcement requires Mode B (ORGA-managed) or Cedar policy evaluation.
#
# Supports two modes:
#   Mode A (standalone): Log state-modifying tool calls for awareness
#   Mode B (SYMBIONT_MANAGED): Outer ORGA Gate handles hard enforcement; we defer

# Read the tool input from stdin
TOOL_INPUT=$(cat)
TOOL_NAME=$(echo "$TOOL_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Mode B: Inside CliExecutor — the outer ORGA Gate handles hard enforcement.
# We just log and defer, avoiding redundant policy evaluation.
if [ -n "$SYMBIONT_MANAGED" ]; then
    echo "{\"feedback\": \"ORGA-managed: outer Gate enforcing (${TOOL_NAME})\"}" >&2
    exit 0
fi

# Mode A: Standalone plugin — do our own lightweight Cedar check

# Skip check if symbi is not installed or no policies directory exists
if ! command -v symbi &> /dev/null || [ ! -d "policies" ]; then
    exit 0
fi

# Skip check for read-only/safe tools
case "$TOOL_NAME" in
    Read|Glob|Grep|LS|View)
        exit 0
        ;;
esac

# For tools that modify state, log the action for audit
# Full Cedar evaluation would go here in a production implementation
# For now, we provide feedback noting the action is being tracked
echo "{\"feedback\": \"Action logged: ${TOOL_NAME}\"}" >&2
exit 0
