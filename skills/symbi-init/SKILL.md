---
name: symbi-init
description: Guide optional project scaffolding through the installed Symbiont CLI.
---

# Initialize a governed project

Distinguish local plugin configuration from a runtime control project. Neither is
required merely to install the plugin.

For Linux native read-only development, use the complete command and prerequisites
in `examples/cli-executor/README.md`. The runtime's `dev-agent` profile generates
its supported configuration, agent, registered tools and Cedar policies.
Keep the control directory empty and separate from the source repository.

For other runtime profiles, check the installed `symbi init --help` and use the
appropriate shipping profile. Do not invent configuration sections, executor
blocks, entity schemas or security-tier guarantees.

Show the intended target, source scope, tool permissions and inference endpoint
before making a new project. Existing plugin policy controls are operator-managed:
provide commands for the operator rather than routing blocked writes through
another tool. Never overwrite an existing control project to resolve a validation
error.

After initialization, run `symbi doctor` where available and report which checks
were actually performed. A valid configuration is not evidence of a successful
contained model run. Use `/symbi:symbi-audit` to inspect that run's actual journal.
