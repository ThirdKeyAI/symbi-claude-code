# CliExecutor-Wrapped Example (Mode B)

Run Claude Code inside Symbiont's ORGA governance loop. Symbiont is the security
perimeter; Claude Code is the execution engine inside it. The plugin becomes the
bridge between the two layers.

## Architecture

```
Symbiont Runtime (ORGA: Observe -> Reason -> Gate -> Act)
  |
  +-> CliExecutor (Docker/gVisor sandbox, resource limits)
        |
        +-> Claude Code (with symbi plugin loaded)
              |
              +-> Plugin hooks detect SYMBIONT_MANAGED=true
              +-> MCP connects back to parent via SYMBIONT_MCP_URL
              +-> Inner plugin = awareness layer (not enforcement)
              +-> Outer ORGA Gate = enforcement layer (cannot bypass)
```

## Agent DSL

Define a Claude Code agent in Symbiont DSL:

```symbiont
metadata {
    version = "1.0.0"
    description = "Code reviewer that runs inside ORGA governance"
}

agent code_reviewer(input: PullRequest) -> ReviewResult {
    capabilities = ["read", "analyze"]

    executor {
        type = "claude_code"
        allowed_tools = ["Bash", "Read", "Grep", "mcp__symbi__*"]
        plugin = "symbi"
        model = "claude-sonnet-4-20250514"
    }

    policy review_policy {
        allow: read(any) if true
        deny: write(any) if not input.is_draft
        audit: all_operations
    }

    with sandbox = "tier1", timeout = "15m" {
        review = analyze(input)
        return review
    }
}
```

## Running

```bash
# Run the agent with a prompt
symbi run code_reviewer --prompt "Review PR #42 for security issues"

# Or programmatically from Rust
let result = orchestrator.execute_code(
    SecurityTier::Tier1,
    "claude -p 'Review PR #42' --allowedTools 'Bash,Read,Grep,mcp__symbi__*'",
    env_vars
).await?;
```

## Environment Variables

The CliExecutor automatically sets:

| Variable | Value | Purpose |
|----------|-------|---------|
| `SYMBIONT_MANAGED` | `true` | Plugin detects managed mode |
| `SYMBIONT_MCP_URL` | `http://localhost:<port>` | Connect to parent MCP |
| `SYMBIONT_RUNTIME_SOCKET` | `/tmp/symbi-<id>.sock` | Runtime communication |
| `SYMBIONT_SESSION_ID` | UUID | Audit log correlation |
| `SYMBIONT_BUDGET_TOKENS` | Integer | Token limit |
| `SYMBIONT_BUDGET_TIMEOUT` | Duration | Time limit |

## What You Get (beyond Mode A)

- ORGA Gate enforcement -- compile-time guaranteed, cannot bypass
- Sandbox isolation (Docker/gVisor/Firecracker) around Claude Code
- Cryptographic audit trail from Symbiont's journal
- Token/cost/time budget enforcement
- Circuit breakers on tool failures
- Single MCP server instance (plugin connects back to parent)
