#!/bin/bash
# PostToolUse hook: Append tool usage to audit log
# Creates a structured log entry for each tool invocation
#
# Supports two modes:
#   Mode A (standalone): Logs to local .symbiont/audit/
#   Mode B (SYMBIONT_MANAGED): Outer runtime handles journaling; we skip local logging

TOOL_INPUT=$(cat)
TOOL_NAME=$(echo "$TOOL_INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Mode B: Inside CliExecutor — the outer Symbiont runtime handles
# cryptographic audit journaling. Skip local JSONL logging to avoid duplication.
if [ -n "$SYMBIONT_MANAGED" ]; then
    exit 0
fi

# Mode A: Standalone plugin — log locally
# Only log if symbiont.toml exists (project is governed)
if [ -f "symbiont.toml" ]; then
    LOG_DIR=".symbiont/audit"
    mkdir -p "$LOG_DIR"
    echo "{\"timestamp\": \"${TIMESTAMP}\", \"tool\": \"${TOOL_NAME}\", \"source\": \"claude-code\"}" >> "${LOG_DIR}/tool-usage.jsonl"
fi

exit 0
