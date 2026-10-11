---
name: symbi-status
description: Check local hook prerequisites, policy configuration and optional runtime integration.
allowed-tools: ["Bash", "Read"]
---

# Installation status

Report each available observation without inferring isolation from plugin presence:

1. `python3 --version`: the engine requires 3.11+; no parser fallback exists.
2. Harness installation: Claude Code 2.1.295+ is required for failure/timeout
   blocking. Check `claude --version`. marketplace registration alone does not install a plugin.
   Cursor requires its project hook registration and an accessible checkout.
3. `.symbiont/disabled`: if present, local decisions and logging are disabled for
   valid calls. Give `/symbi:symbi-enable` instructions.
4. `.symbiont/local-policy.toml`: summarize the mode, deny rules and exceptions.
   Unknown sections/types are errors. An empty file uses balanced defaults.
5. `policies/`: its presence requires a functioning Cedar runtime and an effective
   policy set. Empty, invalid or unavailable evaluation blocks calls.
6. `symbi --version`: installation alone does not prove Cedar capability, MCP
   connectivity, worker isolation or signed journal creation. Exercise the policy
   contract if configured, and report its actual decision and reason.
7. Local log: show decision/completion counts separately if present. Missing records
   may reflect disabled hooks, no events or a write failure. Do not infer completion
   from an allow decision, or claim this mutable log is compliance evidence.

`SYMBIONT_MANAGED` does not bypass these checks. Governed managed CLI workers do
not load this plugin. Direct the operator to the runtime's `symbi doctor` for
sandbox readiness and to actual run evidence for containment verification.
