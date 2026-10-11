---
name: symbi-agent-sdk
description: Explain the supported headless managed CLI workflow and the limits of direct SDK integrations.
---

# Headless governance

Use the shipping runtime route described in `examples/cli-executor/README.md`.
A standalone SDK call is not automatically governed by Symbiont.

1. Establish the task, permitted data/effects and deployment prerequisites.
2. Scaffold a separate, empty control project with
   `symbi init --sandbox landlock --profile dev-agent` for a Linux read-only review.
3. Supply the source path, managed executable and inference settings. Credentials
   remain with the operator/runtime.
4. Validate with `symbi doctor`, then run `symbi run dev --target SOURCE --input TASK`.
5. Inspect actual run evidence; an installed binary or successful DSL parse alone
   does not prove containment or provider connectivity.

Managed selection belongs in `metadata`: `executor = "claude_code"` and an exact
registered ToolClad `allowed_tools` list. There is no plugin-loading executor
block. Built-in tools and automatic plugin discovery are disabled. Do not use a
wildcard allowlist, environment bypass, `--plugin-dir`, or a plugin MCP bridge.

Use the runtime's generated agent and policy examples. For SDK integrations beyond
this CLI route, explain that a separate reviewed design and qualification are
needed instead of generating an unverified orchestration API.
