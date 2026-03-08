---
name: symbi-agent-sdk
description: Generate boilerplate for wrapping Claude Agent SDK agents in ORGA governance. Use when building headless agents that run inside Symbiont's CliExecutor or when integrating the Claude Agent SDK with Symbiont's trust stack.
---

# Agent SDK + ORGA Integration

Help the user create Claude Agent SDK agents that are governed by Symbiont's ORGA loop.

## Architecture

In the runtime-first (Mode B) pattern, Symbiont's CliExecutor spawns Claude Code
as a governed subprocess. The Agent SDK can also be used programmatically:

```
Symbiont Runtime (ORGA Loop)
  -> CliExecutor (sandbox + budget)
    -> Claude Code / Agent SDK (execution)
      -> symbi plugin (awareness bridge)
        -> parent MCP server (governance tools)
```

## DSL Executor Block

When the user wants to define a Claude Code agent in DSL, use the `executor` block:

```symbiont
agent task_name(input: InputType) -> OutputType {
    capabilities = ["read", "analyze", "write"]

    executor {
        type = "claude_code"
        allowed_tools = ["Bash", "Read", "Write", "Edit", "mcp__symbi__*"]
        plugin = "symbi"
        model = "claude-sonnet-4-20250514"
    }

    policy access_policy {
        allow: read(any) if true
        deny: write(any) if not input.approved
        audit: all_operations
    }

    with sandbox = "tier1", timeout = "30m" {
        result = execute(input)
        return result
    }
}
```

## CliExecutor Environment Variables

When Symbiont spawns Claude Code, these environment variables are set:

| Variable | Purpose |
|----------|---------|
| `SYMBIONT_MANAGED=true` | Signals the plugin is inside a managed runtime |
| `SYMBIONT_MCP_URL` | HTTP endpoint to connect back to parent MCP server |
| `SYMBIONT_RUNTIME_SOCKET` | Unix socket for runtime communication |
| `SYMBIONT_SESSION_ID` | Unique session ID for audit correlation |
| `SYMBIONT_BUDGET_TOKENS` | Token budget for this execution |
| `SYMBIONT_BUDGET_TIMEOUT` | Timeout for this execution |

## Workflow

1. Ask what the agent should do and its security requirements
2. Create the DSL definition with an `executor` block for `claude_code`
3. Define Cedar policies for the agent's capabilities
4. Generate the `symbiont.toml` configuration if needed
5. Validate with `parse_dsl`
6. Explain how to run: `symbi run <agent_name> --prompt "..."`

## Scaffolding

When asked to scaffold an Agent SDK project, create:

1. `agents/<name>.dsl` -- Agent definition with executor block
2. `policies/<name>.cedar` -- Cedar policies for the agent
3. `symbiont.toml` -- Runtime configuration with appropriate sandbox tier
4. Instructions for running with `symbi run` or programmatically via CliExecutor
