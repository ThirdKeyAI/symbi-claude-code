---
name: symbi-audit
description: Query and analyze Symbiont's cryptographic audit logs. Use when reviewing agent activity, investigating incidents, or preparing compliance reports.
---

# Audit Log Analysis

Query Symbiont's tamper-evident audit logs to review agent activity.

## Available Queries

- Recent activity: What agents ran and what they did
- Policy decisions: Which policies were evaluated and their outcomes
- Tool usage: Which MCP tools were invoked and by which agents
- Security events: Failed verifications, policy denials, sandbox violations

## Workflow

1. Ask what the user wants to investigate
2. Use the symbi MCP server to query relevant logs
3. Present findings in a clear, chronological format
4. Flag any anomalies or security concerns
5. Suggest policy adjustments if patterns indicate issues
