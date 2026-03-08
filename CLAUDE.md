# Symbiont Plugin Context

This project uses the Symbiont trust stack for AI agent governance.

## Key Concepts
- **ORGA Loop**: Observe -> Reason -> Gate -> Act. The Gate phase operates outside LLM influence and cannot be bypassed.
- **Cedar Policies**: Authorization rules that control what agents and tools can do. Files use `.cedar` extension.
- **SchemaPin**: Cryptographic verification of MCP tool schemas. Ensures tools haven't been tampered with.
- **AgentPin**: Domain-anchored cryptographic identity for AI agents.
- **DSL**: Symbiont's domain-specific language for defining agents declaratively. Files use `.dsl` extension.

## Available MCP Tools (via symbi server)
- `invoke_agent` — Run a Symbiont agent with a prompt
- `list_agents` — List available agents from .dsl files in agents/
- `parse_dsl` — Parse and validate DSL files
- `get_agent_dsl` — Read an agent's DSL definition
- `get_agents_md` — Get the project's AGENTS.md content
- `verify_schema` — Verify a tool schema with SchemaPin

## File Conventions
- Agent definitions: `agents/*.dsl`
- Cedar policies: `policies/*.cedar`
- Symbiont config: `symbiont.toml`
- Agent manifests: `AGENTS.md`

## Dual-Mode Operation

The plugin operates in two modes, detected automatically via environment variables:

### Mode A — Standalone (plugin-first)
Developer installs the plugin directly. Claude Code loads hooks/MCP/skills.
The plugin spawns its own `symbi mcp` server. Policy enforcement is advisory.

### Mode B — ORGA-managed (runtime-first)
Symbiont's CliExecutor spawns Claude Code as a governed subprocess.
The plugin detects `SYMBIONT_MANAGED=true` and connects back to the parent
runtime's MCP endpoint via `SYMBIONT_MCP_URL` instead of spawning a new server.
The outer ORGA Gate provides hard enforcement; the inner plugin provides awareness.

### Environment Variables (Mode B)
- `SYMBIONT_MANAGED=true` — Signals managed mode
- `SYMBIONT_MCP_URL` — Parent runtime's MCP endpoint
- `SYMBIONT_RUNTIME_SOCKET` — Unix socket for runtime communication
- `SYMBIONT_SESSION_ID` — Audit log correlation ID
- `SYMBIONT_BUDGET_TOKENS` — Token budget for execution
- `SYMBIONT_BUDGET_TIMEOUT` — Timeout for execution

## On Session Start
When a session begins, run `scripts/install-check.sh` to verify that `symbi` and `jq` are available. Report any missing dependencies to the user.

## When Governing Tool Use
Before executing tools that modify external state (file writes, API calls, deployments),
check if a Cedar policy applies. Use the symbi MCP server's verify capabilities
to validate tool schemas before first use.

## Implementation Plan
See `ROADMAP.md` for the full implementation plan and phase details.
