# symbi-claude-code

<p align="center">
  <img src="symbi-claude-code.png" alt="symbi-claude-code" width="300">
</p>

A Claude Code plugin that brings [Symbiont](https://symbiont.dev)'s zero-trust AI agent governance to your development workflow. Enforce Cedar authorization policies, verify MCP tool integrity with SchemaPin, maintain cryptographic audit trails, and manage governed agents -- all from within Claude Code.

## Prerequisites

- [Claude Code](https://claude.ai/claude-code) installed
- `symbi` binary on PATH (optional -- plugin degrades gracefully without it)
- `jq` for JSON parsing in hook scripts (`apt install jq` / `brew install jq`)

Install `symbi`:
```bash
# From source
cargo install symbi

# Or via Docker
docker pull ghcr.io/thirdkeyai/symbi:latest
```

Or run the included install script:
```bash
./install.sh
```

## Installation

**From marketplace:**
```
/plugin marketplace add https://github.com/thirdkeyai/symbi-claude-code
```

**Local development:**
```bash
claude --plugin-dir ./symbi-claude-code
```

## Quick Start

1. Install the plugin (see above)
2. Run `/symbi-init` to scaffold a governed project
3. Define agents in `agents/*.dsl`
4. Create Cedar policies in `policies/*.cedar`
5. Use `/symbi-status` to verify everything is connected

## Skills

| Skill | Description |
|-------|-------------|
| `/symbi-init` | Scaffold a governed agent project with starter files |
| `/symbi-policy` | Create, edit, or validate Cedar authorization policies |
| `/symbi-verify` | Verify MCP tool schemas using SchemaPin |
| `/symbi-audit` | Query and analyze cryptographic audit logs |
| `/symbi-dsl` | Parse, validate, and create Symbiont DSL agent definitions |
| `/symbi-agent-sdk` | Generate boilerplate for Claude Agent SDK + ORGA governance |

## Commands

| Command | Description |
|---------|-------------|
| `/symbi-status` | Check health of the Symbiont runtime and installed components |

## Agents

| Agent | Description |
|-------|-------------|
| `symbi-governor` | Governance-aware coding agent (default). Enforces policies and maintains audit trails. |
| `symbi-dev` | DSL development specialist for writing agents and Cedar policies. |

## Hooks

The plugin installs hooks that run automatically:

- **PreToolUse** (`policy-log.sh`): Advisory logging of state-modifying tool calls (does not block)
- **PostToolUse** (`audit-log.sh`): Logs tool usage to `.symbiont/audit/tool-usage.jsonl`

Hooks apply to `Write`, `Edit`, `Bash`, and all `mcp__*` tools.

## MCP Tools

When `symbi` is on PATH, the plugin connects to the Symbiont MCP server exposing:

- `invoke_agent` -- Run a governed agent with a prompt
- `list_agents` -- List available agents from `agents/*.dsl`
- `parse_dsl` -- Parse and validate DSL files
- `get_agent_dsl` -- Read an agent's DSL definition
- `get_agents_md` -- Get the project's AGENTS.md content
- `verify_schema` -- Verify a tool schema with SchemaPin

## Dual-Mode Architecture

The plugin supports two integration patterns:

### Mode A -- Standalone (Plugin-First)

Developer installs the plugin directly into Claude Code. The plugin spawns its own `symbi mcp` server, provides advisory policy checking via hooks, and logs to local audit files.

```
Developer -> Claude Code + symbi plugin -> symbi mcp (stdio)
```

Best for: individual developers adding governance awareness to their workflow.

### Mode B -- ORGA-Managed (Runtime-First)

Symbiont's CliExecutor spawns Claude Code as a governed subprocess. The plugin detects `SYMBIONT_MANAGED=true` and connects back to the parent runtime instead of spawning a new server. The outer ORGA Gate provides hard enforcement that cannot be bypassed.

```
Symbiont Runtime (ORGA Loop)
  -> CliExecutor (sandbox + budget enforcement)
    -> Claude Code (with symbi plugin)
      -> Plugin connects back to parent MCP server
```

Best for: automated pipelines, dark factory deployments, enterprise governance.

See `examples/` for complete setups of each mode.

## Configuration

`settings.json` sets the default agent:
```json
{
  "agent": "symbi-governor"
}
```

Project-level configuration lives in `symbiont.toml` (created by `/symbi-init`).

## File Conventions

| Path | Purpose |
|------|---------|
| `agents/*.dsl` | Agent DSL definitions |
| `policies/*.cedar` | Cedar authorization policies |
| `symbiont.toml` | Symbiont runtime configuration |
| `AGENTS.md` | Agent manifest |
| `.symbiont/audit/` | Audit log output |

## Examples

| Directory | Description |
|-----------|-------------|
| `examples/standalone/` | Mode A setup for individual developers |
| `examples/cli-executor/` | Mode B setup with DSL + Cedar policy for ORGA-wrapped Claude Code |
| `examples/agent-sdk/` | Agent SDK wrapper pattern for headless/programmatic agents |

## License

Apache 2.0 -- see [LICENSE](LICENSE).

## Links

- [Symbiont Documentation](https://docs.symbiont.dev)
- [ThirdKey AI](https://thirdkey.ai)
- [Implementation Roadmap](ROADMAP.md)

## Disclaimer

This project is not affiliated with, endorsed by, or sponsored by Anthropic, PBC. "Claude" and "Claude Code" are trademarks of Anthropic, PBC. "Symbiont" and "ThirdKey" are trademarks of ThirdKey AI.
