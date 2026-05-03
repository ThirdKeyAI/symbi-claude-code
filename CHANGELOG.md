# Changelog

## [0.5.0] - 2026-05-02

### Added
- **Built-in Tier 2 protection by default.** `policy-guard.sh` ships with
  always-active deny patterns for sensitive reads (`.env`, `.ssh/`, `.aws/`,
  `*.pem`, `*.key`, `id_rsa*`, `secrets/`, `credentials/`,
  `config/database.yml`, `config/credentials.json`, `config/master.key`,
  `.npmrc`/`.pypirc`/`.netrc`, `.gcp/`, `gcloud/`), sensitive writes (all
  read-deny + `.github/workflows/`), and dangerous bash commands (`rm -rf /`,
  `rm -rf /*`, `rm -rf ~`, `git push --force`/`-f`, `curl|sh`, `wget|bash`,
  `chmod 777`, `mkfs*`, `dd if=`, fork bombs). `sudo` warns by default.
  No `local-policy.toml` required.
- `[mode]` key in `.symbiont/local-policy.toml`: `strict` (sudo blocks),
  `balanced` (default, sudo warns), `permissive` (built-ins disabled).
- `[allow]` section in `.symbiont/local-policy.toml` to whitelist exceptions
  to the built-in deny patterns.
- `/symbi-protect` slash command — prints active defaults and drops a
  heavily-commented starter `.symbiont/local-policy.toml`.
- `/symbi-disable` and `/symbi-enable` slash commands — graceful kill switch
  via `.symbiont/disabled` marker; every hook no-ops while present.
- `scripts/lib/json-extract.sh` — shared JSON field extractor with three
  backends (jq → python3 → narrow bash awk fallback). Removes hard `jq`
  dependency.
- Sensitive-file nudge in `install-check.sh`: scans project root + 1 level
  for `.env`, `id_rsa`, `*.pem`, `.ssh/`, `.aws/` and prints a one-line
  `/symbi-protect` pointer when no `local-policy.toml` exists yet.
- `tests/` directory with bash test runner: 78 tests covering built-in
  defaults, JSON backend parity, chain-bypass resistance, allowlist
  exemptions, mode switching, and the kill-switch marker.

### Changed
- `policy-guard.sh` evaluates the **full** command string (not just the
  first token) for bash deny patterns. Defeats Adversa-style chain bypasses
  like `true && true && rm -rf /` — the dangerous substring still matches.
- Hook matchers now include `Read` and `MultiEdit` so sensitive-path reads
  and multi-edits are inspected.
- `audit-log.sh` always logs to `.symbiont/audit/tool-usage.jsonl` (no
  longer gated on the existence of `symbiont.toml`). Every standalone
  install gets an audit trail by default.
- `install-check.sh` no longer requires `jq`. Reports backend selection
  and only warns when neither `jq` nor `python3` is available.
- README rewrites the lead with the plugin-only value proposition. Runtime
  sections (Cedar, ORGA, Mode B, dual-mode architecture) move below a
  "Going further" heading.
- CLAUDE.md updated to reflect Tier 2 as the default behavior.

### Removed
- `jq` from the prerequisites section of the README. The hooks now prefer
  `jq` when available but fall back gracefully.

## [0.4.0] - 2026-04-22

### Added
- `SessionStart` hook registered in `hooks/hooks.json`, running `install-check.sh` on every session
- `install-check.sh` now SchemaPin-verifies every server in the project's `.mcp.json` at session start, surfacing tampered and unsigned servers as non-blocking warnings
- `/symbi-pin` skill for pinning MCP server schemas (TOFU) with explicit trust, re-pin, and conflict guidance

### Changed
- `policy-guard.sh` Layer 3 (Cedar evaluation) is now a real enforcement path: `symbi policy evaluate --stdin --policies ./policies/` is implemented in Symbiont core (1.11.0+) and emits the bare verdict (`allow`/`deny`) on stdout with structured JSON detail on stderr. Hook tests `[ "$DECISION" = "deny" ]` against the bare stdout — no behaviour change required in the script.
- `install-check.sh` now relies on the real `symbi schemapin verify` subcommand: exit 1 with "no signature" in stderr means the MCP server is unpinned, exit 1 with "verification failed" means the server config drifted since pinning. Pin records live at `~/.symbiont/schemapin/mcp/<name>.pin` (managed via `symbi schemapin pin / list / unpin`).
- `skills/symbi-policy/SKILL.md` and `ROADMAP.md`: replaced the non-existent `symbi dsl parse` invocation with the actual CLI surface (`symbi dsl --file <path>` for DSL files, `symbi policy evaluate` for Cedar parse-checking).

### Removed
- `scripts/mcp-wrapper.sh` -- orphaned (never referenced from `.mcp.json`) and superseded by native HTTP MCP transport in `.mcp.json`, which avoids the `npx @anthropic-ai/mcp-proxy` dependency

### Notes
- All previously-stubbed CLI integrations are now wired to real implementations in Symbiont core. The plugin still degrades gracefully when `symbi` is absent: Layer 1 (built-in pattern blocking) and Layer 2 (local deny list) continue to enforce, and advisory logging still records all tool calls.

## [0.3.0] - 2026-03-08

### Added
- **Three-tier governance model**: Awareness (default), Protection (local deny list), Governance (Cedar)
- `policy-guard.sh` blocking hook — blocks destructive commands, force pushes, writes to sensitive files
- `.symbiont/local-policy.toml` deny list support — developer-configurable path, command, and branch blocking
- Cedar policy evaluation in hooks when `symbi` is on PATH
- `/symbi-init` now scaffolds `.symbiont/local-policy.toml` with safe defaults

### Changed
- Hooks now run `policy-guard.sh` (blocking) before `policy-log.sh` (advisory)
- Updated CLAUDE.md and README.md to document governance tiers

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
  - `policy-log.sh` -- PreToolUse advisory policy logging
  - `audit-log.sh` -- PostToolUse audit logging
  - `install-check.sh` -- session start symbi verification
- Agents:
  - `symbi-governor` -- governance-aware coding agent (default)
  - `symbi-dev` -- DSL development specialist
- Documentation: README, ROADMAP, CHANGELOG
- Install script for symbi binary
