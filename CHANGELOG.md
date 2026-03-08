# Changelog

## [0.2.0] - 2026-03-07

### Added

- Dual-mode architecture: Mode A (standalone) and Mode B (ORGA-managed)
- Environment detection in all hook scripts (`SYMBIONT_MANAGED`, `SYMBIONT_MCP_URL`)
- MCP transport wrapper script (`mcp-wrapper.sh`) for HTTP/stdio switching
- `/symbi-agent-sdk` skill for Claude Agent SDK + ORGA boilerplate
- Examples:
  - `examples/standalone/` -- plugin-only setup
  - `examples/cli-executor/` -- CliExecutor-wrapped Claude Code with DSL + Cedar
  - `examples/agent-sdk/` -- headless Agent SDK wrapper pattern
- `claude_code` executor type documentation for DSL agent definitions
- Dual-mode documentation in README and CLAUDE.md

## [0.1.0] - 2026-03-07

### Added

- Plugin manifest (`.claude-plugin/plugin.json`) and marketplace catalog
- MCP server configuration connecting to `symbi mcp`
- Default settings activating `symbi-governor` agent
- Skills:
  - `/symbi-init` -- scaffold a governed agent project
  - `/symbi-policy` -- create/edit Cedar authorization policies
  - `/symbi-verify` -- SchemaPin MCP tool verification
  - `/symbi-audit` -- query cryptographic audit logs
  - `/symbi-dsl` -- parse/validate DSL agent definitions
- Commands:
  - `/symbi-status` -- runtime health check
- Hooks:
  - `cedar-gate.sh` -- PreToolUse Cedar policy check
  - `audit-log.sh` -- PostToolUse audit logging
  - `install-check.sh` -- session start symbi verification
- Agents:
  - `symbi-governor` -- governance-aware coding agent (default)
  - `symbi-dev` -- DSL development specialist
- Documentation: README, ROADMAP, CHANGELOG
- Install script for symbi binary
