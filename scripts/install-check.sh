#!/bin/bash
# Verify symbi and jq are available on PATH
# Supports two modes:
#   Mode A (standalone): Check for required binaries
#   Mode B (SYMBIONT_MANAGED): Already inside runtime, report managed mode

# Mode B: Inside CliExecutor -- symbi is the parent process
if [ -n "$SYMBIONT_MANAGED" ]; then
    echo "{\"feedback\": \"Symbiont ORGA-managed mode active\"}" >&2
    exit 0
fi

# Mode A: Standalone plugin

# Check for jq (required by hook scripts to parse JSON input)
if ! command -v jq &> /dev/null; then
    echo '{"feedback": "jq is not installed. Hook scripts require jq for JSON parsing. Install via: apt install jq / brew install jq"}' >&2
fi

if ! command -v symbi &> /dev/null; then
    echo '{"feedback": "Symbiont (symbi) is not installed or not on PATH. Some governance features will be unavailable. Run /symbi-status for installation instructions."}' >&2
    exit 0  # Non-blocking
fi

VERSION=$(symbi --version 2>/dev/null || echo "unknown")
echo "{\"feedback\": \"Symbiont governance active (${VERSION})\"}" >&2
exit 0
