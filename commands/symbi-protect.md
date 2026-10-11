---
name: symbi-protect
description: Explain active local checks and provide an operator-applied starter policy.
allowed-tools: ["Read"]
---

# Local policy setup

Summarize the current mode and any `.symbiont/local-policy.toml` additions.
Explain that direct file checks and shell heuristics are local guardrails, not
containment. A directory search can read descendants that the supplied-path check
does not inspect. Managed execution requires the separate runtime workflow.

Show `examples/local-policy.toml` from this plugin as a starter. Ask the operator
to apply it outside the agent session. Do not write policy, hook configuration or
disable markers through tools, or route a denied write through Bash.

Local deny rules override allow exceptions. Exceptions only relax built-ins;
control-path protection and configured Cedar checks remain active. Malformed or
unsupported TOML blocks calls. Python 3.11+ is required.

Point to `/symbi:symbi-disable` for opt-out instructions and
`/symbi:symbi-status` for checking readiness.
