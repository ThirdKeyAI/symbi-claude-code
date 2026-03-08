# Standalone Plugin Example (Mode A)

Use the symbi plugin directly in Claude Code without a Symbiont runtime wrapper.
The plugin provides governance awareness, Cedar policy checking via hooks,
and access to Symbiont MCP tools.

## Setup

1. Install the symbi binary:
   ```bash
   cargo install symbi
   ```

2. Start Claude Code with the plugin:
   ```bash
   claude --plugin-dir /path/to/symbi-claude-code
   ```

3. Initialize a governed project:
   ```
   /symbi-init
   ```

## What You Get

- Lightweight Cedar policy awareness via PreToolUse hooks
- SchemaPin verification of MCP tool schemas
- Local audit logging to `.symbiont/audit/`
- Skills for creating agents, policies, and DSL definitions
- MCP tools: invoke_agent, list_agents, parse_dsl, etc.

## Limitations

- Policy enforcement is advisory (hooks provide feedback, not hard blocks)
- No sandbox isolation around Claude Code itself
- Audit logs are local JSONL files, not cryptographic journals
- No token/cost/time budget enforcement

For full enforcement, use Mode B (CliExecutor-wrapped). See `examples/cli-executor/`.
