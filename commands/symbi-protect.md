---
name: symbi-protect
description: Show what's blocked by default and drop a starter local-policy.toml the user can edit.
allowed-tools: ["Bash", "Write", "Read"]
---

# Symbi Protect

The plugin already protects this project. This command surfaces what's
active and offers to drop a `.symbiont/local-policy.toml` so the user can
customize.

## Steps

1. Print a single paragraph summary of what's currently active. Mention:
   - Built-in deny patterns are active (no config required).
   - Reads of `.env`, `.ssh/`, `.aws/`, `*.pem`, `*.key`, `id_rsa`,
     `secrets/`, `credentials/`, etc. are blocked.
   - Writes additionally block `.github/workflows/`.
   - Bash patterns `rm -rf /`, `git push --force`, `curl | sh`, `chmod 777`
     are blocked. `sudo` is warned (block in strict mode).
   - Every tool call is logged to `.symbiont/audit/tool-usage.jsonl`.
   - Mode B (ORGA-managed) is automatic when `SYMBIONT_MANAGED=true` is set.

2. If `.symbiont/local-policy.toml` already exists, ask whether to overwrite.
   Default to "no" — show the existing file with `cat` and stop.

3. Otherwise, create `.symbiont/` and write the starter policy below to
   `.symbiont/local-policy.toml`. The starter is heavily commented to
   document the inherited defaults inline.

4. Print: "Wrote .symbiont/local-policy.toml. Edit it to customize.
   Run /symbi-disable for a graceful opt-out."

## Starter `.symbiont/local-policy.toml`

```toml
# Symbiont local policy
# ---------------------
# This file EXTENDS the plugin's built-in deny defaults. You don't need
# to repeat the built-ins here — they're always active in balanced mode.
#
# Modes:
#   strict     — built-ins + sudo is hard-blocked
#   balanced   — built-ins active, sudo warns (default)
#   permissive — built-ins disabled; only this file is enforced

[mode]
mode = "balanced"

# ----------------------------------------------------------------------
# Built-in deny defaults (active without any config)
# ----------------------------------------------------------------------
# Read-blocked:
#   .env, .env.* (except .env.example, .env.sample, .env.test)
#   .ssh/, .aws/, .gcp/, gcloud/
#   .npmrc, .pypirc, .netrc
#   *.pem, *.key, id_rsa, id_ed25519, id_ecdsa
#   secrets/, credentials/
#   config/database.yml, config/credentials.json, config/master.key
#
# Write-blocked: all of the above plus
#   .github/workflows/
#
# Bash-blocked:
#   rm -rf /, rm -rf /*, rm -rf ~
#   git push --force, git push -f, git push --force-with-lease
#   curl ... | sh|bash, wget ... | sh|bash
#   chmod 777, mkfs*, dd if=, fork bombs
#   sudo (warn-only — set [mode]=strict to block)

# ----------------------------------------------------------------------
# Add your own deny rules below.
# Patterns are substring-matched against paths or full command strings.
# Use forward slashes; bash globs work (e.g. "config/*.yml").
# ----------------------------------------------------------------------

[deny]
# paths    = ["my-secret-dir/", "private/", "*.backup"]
# commands = ["custom-dangerous-cmd", "rm -rf /opt/data"]
# branches = ["main", "master", "production"]

# ----------------------------------------------------------------------
# Allowlist exceptions to built-ins.
# If a built-in pattern is blocking something legitimate, list it here.
# ----------------------------------------------------------------------

[allow]
# paths    = [".env.template", "fixtures/.env.fake"]
# commands = ["sudo systemctl restart myapp"]
```
