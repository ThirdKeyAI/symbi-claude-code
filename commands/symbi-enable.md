---
name: symbi-enable
description: Re-enable Symbiont hooks after /symbi-disable.
allowed-tools: ["Bash"]
---

# Symbi Enable

Remove the `.symbiont/disabled` marker so hooks fire again.

## Steps

1. If `.symbiont/disabled` does not exist, print: "Symbiont is already active."
2. Otherwise, remove it:
   ```bash
   rm -f .symbiont/disabled
   ```
3. Print: "Symbiont hooks re-enabled."
