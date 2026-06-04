---
name: symbi-audit
description: Query and analyze the Symbiont audit log of Claude Code tool usage. Works with no runtime — reads the always-on local JSONL log at .symbiont/audit/tool-usage.jsonl — and upgrades to the runtime's cryptographic audit trail when the symbi binary is installed. Use when reviewing tool activity, investigating an incident, or preparing a usage summary.
allowed-tools: ["Bash", "Read"]
---

# Audit Log Analysis

The plugin records **every** tool call by default — no runtime required. Each
PostToolUse event appends one JSON line to:

```
.symbiont/audit/tool-usage.jsonl
```

Line shape:

```json
{"timestamp":"2026-06-03T14:22:01Z","tool":"Bash","source":"claude-code"}
```

## Source selection

1. **Local log (default, no runtime).** Read `.symbiont/audit/tool-usage.jsonl`
   in the project root. This is the source for a plain plugin install.
2. **Runtime cryptographic trail (when `symbi` is on PATH).** The Symbiont
   runtime keeps a tamper-evident journal with richer detail (agent identity,
   policy decisions, SchemaPin events). Prefer it when available; query it via
   the `symbi` MCP server tools.

Always start by checking which sources exist:

```bash
test -f .symbiont/audit/tool-usage.jsonl && echo "local log present"
command -v symbi >/dev/null && echo "runtime available"
```

## Querying the local log

Use `jq` when present, with plain-text fallbacks. Examples:

```bash
# Total recorded calls
wc -l < .symbiont/audit/tool-usage.jsonl

# Most recent 20 calls
tail -n 20 .symbiont/audit/tool-usage.jsonl

# Count by tool
jq -r '.tool' .symbiont/audit/tool-usage.jsonl | sort | uniq -c | sort -rn
# (no jq) — coarse fallback:
grep -oE '"tool":"[^"]*"' .symbiont/audit/tool-usage.jsonl | sort | uniq -c | sort -rn

# Calls since a timestamp
jq -r 'select(.timestamp >= "2026-06-03T00:00:00Z") | "\(.timestamp) \(.tool)"' \
    .symbiont/audit/tool-usage.jsonl

# Just Bash invocations
jq -r 'select(.tool == "Bash") | .timestamp' .symbiont/audit/tool-usage.jsonl
```

The local log records tool *names* and timestamps, not arguments — it answers
"what kinds of actions ran, and how often," not "what exact command." For
argument-level detail, use the runtime trail.

## Querying the runtime trail (when installed)

When `symbi` is on PATH, use the `symbi` MCP server to investigate:

- Recent agent activity and what each agent did
- Policy decisions (which Cedar policies evaluated, allow/deny outcomes)
- MCP tool usage by agent
- Security events: failed SchemaPin verifications, policy denials, sandbox
  violations

## Workflow

1. Detect available sources (local log, runtime).
2. Ask what the user wants to investigate (recent activity, a specific tool,
   a time window, anomalies).
3. Run the appropriate query and present findings in a clear, chronological
   summary.
4. Flag anything notable — bursts of destructive-command attempts, blocked
   reads, unusual tool mixes.
5. If patterns suggest tightening policy, point to `/symbi-protect`
   (local rules) or `/symbi-policy` (Cedar, runtime).

If neither source exists yet, say so: a fresh project has no log until the
first tool call is recorded.
