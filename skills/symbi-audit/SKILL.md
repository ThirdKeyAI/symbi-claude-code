---
name: symbi-audit
description: Inspect local hook diagnostics or an actual governed run's signed journal.
allowed-tools: ["Bash", "Read"]
---

# Inspect execution evidence

Select the actual evidence source before drawing conclusions.

## Local plugin diagnostics

`.symbiont/audit/tool-usage.jsonl` contains timestamp, tool, source, phase,
input digest and an optional tool-use ID. Decision records include allow/warn/deny;
Claude Code's post hook adds completion records. Cursor currently logs decisions
only. Raw arguments are omitted.

```sh
# Recent recorded events, not a count of completed calls
tail -n 20 .symbiont/audit/tool-usage.jsonl
# Optional jq queries
jq 'select(.phase == "decision" and .decision == "deny")' .symbiont/audit/tool-usage.jsonl
jq 'select(.phase == "completed")' .symbiont/audit/tool-usage.jsonl
```

An allow is not proof that a tool ran. Hooks can be disabled or skipped by the
harness, writes can fail, and local files can be changed. These are diagnostic
records, not a tamper-evident compliance ledger. Do not infer the exact command
from its digest or claim complete coverage.

## Governed runtime journals

A runtime installation does not create a signed record for standalone plugin
activity. For an actual governed run, obtain the journal path, expected run ID
and public audit key through a trusted channel. Use:

```sh
symbi audit inspect /path/to/journal --public-key HEX --run-id UUID
```

Report validation errors, incomplete or unknown outcomes as such. Do not replay
operations to fill gaps. No audit-query MCP tool is implied by `symbi mcp`.

Present a concise timeline and separate decisions from execution evidence.
Suggest policy changes for operator review; do not alter policy controls.
