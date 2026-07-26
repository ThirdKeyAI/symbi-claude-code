# Symbiont Plugin Context

This project is a Claude Code plugin that delivers default-on protection
against secret reads, sensitive writes, and destructive shell commands.
The runtime upgrade path (Cedar evaluation, MCP tools, governed agents)
is opt-in and only activates when the `symbi` binary is installed.

## Default Posture (Tier 2)

The plugin's default behavior **is** Tier 2 protection. No `local-policy.toml`
required. The built-in deny defaults block:

- **Reads**: `.env`, `.env.*` (except `.env.example`/`.sample`/`.test`),
  `.ssh/`, `.aws/`, `.gcp/`, `gcloud/`, `.npmrc`, `.pypirc`, `.netrc`,
  `*.pem`, `*.key`, `id_rsa`/`id_ed25519`/`id_ecdsa`, `secrets/`,
  `credentials/`, `config/database.yml`, `config/credentials.json`,
  `config/master.key`.
- **Writes**: all of the above plus `.github/workflows/`.
- **Bash**: `rm -rf /`, `rm -rf /*`, `rm -rf ~`, `git push --force`/`-f`,
  `curl ... | sh|bash`, `wget ... | sh|bash`, `chmod 777`, `mkfs*`,
  `dd if=`, fork bombs.
- `sudo` is warned (block in `[mode]=strict`).

`.symbiont/local-policy.toml` *extends* these defaults with project-specific
rules; it never replaces them unless `[mode]=permissive` is set.

## Modes

`[mode]` in `.symbiont/local-policy.toml`:

- `balanced` (default) — built-ins active, sudo warns
- `strict` — built-ins active, sudo hard-blocked
- `permissive` — built-ins disabled, only the local TOML enforces

## Kill switch

`.symbiont/disabled` makes every hook no-op (still exits 0). Use
`/symbi-disable` to drop it, `/symbi-enable` to remove it.

## Hooks (always loaded)

- `scripts/install-check.sh` — SessionStart. Detects JSON backend
  (jq → python3 → bash), nudges on sensitive files when no
  `local-policy.toml` exists, runs SchemaPin verification when `symbi` is
  on PATH.
- `scripts/policy-guard.sh` — PreToolUse. Claude adapter only: maps tool
  names to `read`/`write`/`exec`, calls the engine, translates the verdict
  (deny → plain-text stderr + exit 2; warn → stdout `systemMessage`).
- `scripts/policy-log.sh` — PreToolUse. Silent advisory slot (recording is
  handled by `audit-log.sh`; retained for future signals).
- `scripts/audit-log.sh` — PostToolUse. Appends JSONL to
  `.symbiont/audit/tool-usage.jsonl`. Always logs (no `symbiont.toml` gate).

All hooks check the `.symbiont/disabled` marker first and the
`SYMBIONT_MANAGED` env var second.

## Policy engine (harness-free)

`scripts/core/decide.sh` holds **all** policy semantics — built-in deny
defaults, mode handling, `local-policy.toml` parsing, Cedar. It knows
nothing about any harness: no JSON payload shapes, no tool names, no
exit-code contracts.

```
decide.sh <read|write|exec> <path-or-command>
  → stdout, one line:  allow | warn<TAB>reason | deny<TAB>reason
  → exit status always 0 (the verdict is the line, not the code)
  → project root from SYMBIONT_PROJECT_DIR (default $PWD)
```

Adapters own the translation both ways. Add a harness by adding an
adapter — never by editing the engine.

| Adapter | Harness contract | allow / warn / deny |
| ------- | ---------------- | ------------------- |
| `scripts/policy-guard.sh` | `PreToolUse` on stdin | exit 0 / stdout `systemMessage` / stderr + exit 2 |
| `scripts/cursor-guard.sh` | `preToolUse` on stdin | `permission` = `allow` / `ask` / `deny` |

Cursor is wired by `adapters/cursor/install.sh`, which renders
`adapters/cursor/hooks.json` with an absolute path to this checkout and
merges it into any existing `.cursor/hooks.json` via jq (backing the
original up first). Cursor's `ask` verdict has no Claude equivalent, so a
warn prompts the user there and merely notifies here — same policy,
stricter harness.

`tests/test_decide.sh` pins the output contract; `tests/test_policy_guard.sh`
covers semantics end-to-end through the Claude adapter.

## JSON parsing in hooks

`scripts/lib/json-extract.sh` exposes `json_field <payload> <dotted.path>`.
Backend selection on first use:

1. `jq` if present
2. `python3` (or `python`) if present
3. Pure-bash awk extractor — narrow, refuses payloads with `\u` escapes

The bash fallback only handles the field shapes Claude Code emits
(`tool_name`, `tool_input.file_path`, `tool_input.path`,
`tool_input.command`). Refusing exotic payloads is fail-safe: an empty
return means "no match" so the policy guard does not block what it cannot
parse, and never blocks based on misinterpreted bytes.

## Slash commands

Plugin-only (no runtime needed):

- `/symbi-protect` — print active defaults, drop a starter policy file
- `/symbi-disable` / `/symbi-enable` — kill-switch toggle
- `/symbi-status` — health check
- `/symbi-audit` — query the audit log

Runtime-required (need `symbi` binary):

- `/symbi-init` — scaffold a runtime-managed project
- `/symbi-policy`, `/symbi-verify`, `/symbi-pin`, `/symbi-dsl`,
  `/symbi-agent-sdk`

## Tests

`tests/run-tests.sh` covers built-in deny patterns, JSON backend parity,
chain-bypass resistance, allowlist exemptions, mode switching, and the
kill-switch marker. Run before committing changes to hooks.

## Runtime upgrade path (opt-in)

When the `symbi` binary is installed, additional features light up
automatically — no plugin changes required:

- **Tier 3 (Cedar evaluation)**: `core/decide.sh` runs `symbi policy
  evaluate --stdin --policies ./policies/` after the built-in checks pass,
  piping the normalized `{"action":…,"target":…}` envelope. One Cedar
  policy set therefore covers every harness adapter.
- **MCP tools**: the plugin connects to a `symbi mcp` server exposing
  `invoke_agent`, `list_agents`, `parse_dsl`, `get_agent_dsl`,
  `get_agents_md`, `verify_schema`.
- **SchemaPin**: `install-check.sh` verifies pinned MCP servers on session
  start.

## Mode B (ORGA-managed)

When Symbiont's CliExecutor spawns Claude Code as a governed subprocess,
it sets `SYMBIONT_MANAGED=true`. All hooks early-return so the outer ORGA
Gate is the single source of truth for hard enforcement.

Override `.mcp.json` at the project or user level to point at the parent
runtime:

```json
{
  "mcpServers": {
    "symbi": { "type": "http", "url": "${SYMBIONT_MCP_URL}" }
  }
}
```

Mode B environment variables:

- `SYMBIONT_MANAGED=true`
- `SYMBIONT_MCP_URL`
- `SYMBIONT_RUNTIME_SOCKET`
- `SYMBIONT_SESSION_ID`
- `SYMBIONT_BUDGET_TOKENS`
- `SYMBIONT_BUDGET_TIMEOUT`

## File conventions

| Path                            | Purpose |
| ------------------------------- | ------- |
| `.symbiont/local-policy.toml`   | Project deny/allow rules + mode |
| `.symbiont/disabled`            | Kill-switch marker |
| `.symbiont/audit/`              | Local audit log |
| `agents/*.dsl`                  | (runtime) Agent DSL definitions |
| `policies/*.cedar`              | (runtime) Cedar policies |
| `symbiont.toml`                 | (runtime) Runtime configuration |
| `AGENTS.md`                     | (runtime) Agent manifest |

## On Session Start

`scripts/install-check.sh` detects the JSON backend and prints a one-line
nudge if sensitive files exist with no `local-policy.toml` yet. It does
not require any user action and never blocks.

## Implementation Plan

See `ROADMAP.md` for the full implementation history and phase details.
