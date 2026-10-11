---
name: symbi-enable
description: Show operator instructions for restoring local hooks.
---

# Enable local hooks

If `.symbiont/disabled` exists, ask the operator to remove it in a separate terminal
at the project root:

```sh
rm .symbiont/disabled
```

Do not change policy controls through agent tools. If the plugin was disabled or
uninstalled in the harness, re-enable/install it there as well. Check readiness
with `/symbi:symbi-status`; do not claim protection was restored merely because
instructions were shown.
