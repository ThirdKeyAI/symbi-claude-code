---
name: symbi-status
description: Check the health and status of the Symbiont runtime, MCP server, and installed components.
allowed-tools: ["Bash", "mcp__symbi__list_agents"]
---

Check the status of the Symbiont installation and runtime:

1. Run `symbi --version` to check if the binary is installed and get the version
2. Run `symbi mcp --health-check` if available, or verify the MCP server responds via `list_agents`
3. Check for `symbiont.toml` in the current directory
4. Check for agent definitions in `agents/` directory
5. Check for Cedar policies in `policies/` directory
6. Report the status of each component clearly

If symbi is not installed, provide installation instructions:
```bash
# From source
cargo install symbi

# Or via Docker
docker pull ghcr.io/thirdkeyai/symbi:latest
```
