#!/bin/bash
# PreToolUse hook: advisory slot.
#
# This runs alongside policy-guard.sh. The guard handles all blocking and
# the PostToolUse audit-log.sh records every call to JSONL, so this hook
# intentionally produces NO user-facing output: a per-tool-call notice on
# every Write/Edit/Bash would be UI spam, and recording is already covered.
# It is retained as a wired advisory slot for future, value-adding signals.
#
# (Historically this emitted {"feedback":...} on stderr + exit 0, which the
# Claude Code hook contract drops silently — it never surfaced anywhere.)
#
# Modes:
#   Mode A (standalone): silent
#   Mode B (SYMBIONT_MANAGED): outer ORGA Gate enforces; we just defer
#
# Kill switch: .symbiont/disabled silences this hook.

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# Drain the payload off stdin so the caller never sees a broken pipe.
cat >/dev/null 2>&1 || true

# Kill switch.
if [ -f "${PROJECT_ROOT}/.symbiont/disabled" ]; then
    exit 0
fi

# Mode B: outer ORGA Gate is the single source of truth — stay silent.
# Mode A: no user-facing output by design (see header). policy-guard.sh
# enforces and audit-log.sh records; nothing more to surface here.
exit 0
