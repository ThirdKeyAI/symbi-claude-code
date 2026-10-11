---
name: symbi-dsl
description: Inspect and validate agent definitions against the installed Symbiont runtime.
allowed-tools: ["mcp__symbi__parse_dsl", "mcp__symbi__get_agent_dsl", "mcp__symbi__list_agents"]
---

# Agent definitions

Use the installed runtime's examples and generated profiles as the syntax source.
For managed CLI selection, metadata contains `executor = "claude_code"` and exact
registered tool names in `allowed_tools`. See
`examples/cli-executor/code-reviewer.symbi` for a minimal parseable example.

When the optional runtime MCP server is connected, `list_agents`, `get_agent_dsl`
and `parse_dsl` can inspect and validate definitions. Otherwise provide the CLI:

```sh
symbi dsl --check --file agents/dev.symbi
```

A successful parse proves syntax, not that the configured execution route runs
the DSL body or enforces an inline policy. Managed CLI execution uses metadata and
external runtime policies; source ceilings, approval state and sandbox setup are
separate controls. Avoid invented schema fields or unsupported executor blocks.
