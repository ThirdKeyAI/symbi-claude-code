---
name: symbi-status
description: Health check of the Symbiont plugin (default-on protection) and the optional runtime, MCP server, and governed components.
allowed-tools: ["Bash", "Read"]
---

Report the status of Symbiont in this project. Lead with the plugin's
default-on protection — that works with no runtime — then cover the optional
runtime layer.

## 1. Plugin protection (always present)

1. **Kill switch.** If `.symbiont/disabled` exists, report that protection is
   currently DISABLED and that `/symbi-enable` restores it. (When disabled,
   note the remaining checks below are informational only.)
2. **Mode.** Read `[mode]` from `.symbiont/local-policy.toml` if present:
   - `strict` — built-ins active, `sudo` hard-blocked
   - `balanced` — built-ins active, `sudo` warns (this is also the default
     when no `local-policy.toml` exists)
   - `permissive` — built-ins disabled, only the local TOML is enforced
   If there is no `local-policy.toml`, say "balanced (built-in defaults, no
   local policy file)."
3. **Local policy.** If `.symbiont/local-policy.toml` exists, summarize its
   `[deny]` / `[allow]` additions; otherwise note that only the built-in
   defaults are active.
4. **Audit log.** If `.symbiont/audit/tool-usage.jsonl` exists, report it is
   recording and show the line count (`wc -l`); otherwise note no calls have
   been logged yet. Point to `/symbi-audit` to query it.
5. **JSON backend.** Report which parser the hooks will use:
   `jq` if present, else `python3`/`python`, else the limited bash fallback.
6. **Managed mode.** If `SYMBIONT_MANAGED` is set, note ORGA-managed (Mode B):
   the outer runtime Gate enforces and plugin hooks defer.

Suggested checks:

```bash
test -f .symbiont/disabled && echo "DISABLED (.symbiont/disabled present)" || echo "protection active"
test -f .symbiont/local-policy.toml && grep -E '^\s*mode\s*=' .symbiont/local-policy.toml || echo "mode: balanced (defaults)"
test -f .symbiont/audit/tool-usage.jsonl && echo "audit entries: $(wc -l < .symbiont/audit/tool-usage.jsonl)" || echo "no audit log yet"
command -v jq >/dev/null && echo "json backend: jq" || { command -v python3 >/dev/null && echo "json backend: python3" || echo "json backend: bash (limited)"; }
```

## 2. Runtime (optional upgrade)

1. Run `symbi --version` to check whether the binary is installed.
2. If installed, verify the MCP server responds (e.g. via `list_agents`) and
   report connectivity.
3. Check for `symbiont.toml`, `agents/` (DSL), and `policies/` (Cedar) in the
   project and report which are present.
4. If `symbi` is **not** installed, that is expected for a plugin-only setup —
   say so plainly. To enable Tier 3 (Cedar) and MCP tools:

```bash
# From source
cargo install symbi

# Or via Docker
docker pull ghcr.io/thirdkeyai/symbi:latest
```

## Output

Present a short, clearly sectioned report (Plugin / Runtime) with a one-line
verdict at the top, e.g. "Protected (balanced mode, runtime not installed)."
