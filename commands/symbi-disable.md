---
name: symbi-disable
description: Show operator instructions for opting out of local hooks.
---

# Disable local hooks

Explain that the plugin is optional. The operator can disable/uninstall it through
the harness plugin controls, or run these commands in a separate terminal at the
project root:

```sh
mkdir -p .symbiont
touch .symbiont/disabled
```

Do not execute these commands or create the marker through agent tools. It is a
policy control. Do not claim hooks are disabled until the operator reports or a
read-only check confirms the change. The marker suppresses decisions and logging
for valid calls; malformed hook payloads still fail.

Use `/symbi:symbi-enable` for restoration instructions.
