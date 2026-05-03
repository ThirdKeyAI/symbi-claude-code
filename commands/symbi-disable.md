---
name: symbi-disable
description: Drop a marker file that no-ops every Symbiont hook. Graceful opt-out without uninstalling.
allowed-tools: ["Bash"]
---

# Symbi Disable

Create `.symbiont/disabled` so all hooks (policy-guard, audit-log,
policy-log, install-check) early-return without blocking or logging.
The plugin stays installed; nothing is removed.

## Steps

1. Create `.symbiont/` if it doesn't exist.
2. Write a marker to `.symbiont/disabled` with a timestamp and a comment.
3. Tell the user: "Symbiont hooks disabled. Run /symbi-enable to restore."

```bash
mkdir -p .symbiont
date -u +"# disabled at %Y-%m-%dT%H:%M:%SZ" > .symbiont/disabled
echo "# delete this file or run /symbi-enable to re-activate" >> .symbiont/disabled
```

If the file already exists, just print: "Symbiont already disabled at <timestamp>."
