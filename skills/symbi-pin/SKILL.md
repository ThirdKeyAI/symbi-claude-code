---
name: symbi-pin
description: Pin an MCP server's schema using SchemaPin so future sessions detect tampering. Use when adding a new MCP server to .mcp.json, after a trusted server update, or when the SessionStart hook warns about unsigned servers.
---

# SchemaPin Pinning

Establish trust-on-first-use (TOFU) for an MCP server by fetching its schema, recording the publisher's public key, and storing a signature the SessionStart hook can verify on every future launch.

## When to Pin

- A new MCP server was added to `.mcp.json`
- SessionStart reports "Unsigned MCP servers: ..."
- A trusted server update changed the schema (re-pin intentionally)
- Before relying on a server in production workflows

Do NOT pin a server you do not trust right now -- pinning only freezes the current schema, it does not judge provenance.

## Pinning Process

1. Identify the MCP server name from `.mcp.json` (or ask the user).
2. Confirm the user actually trusts this server in its current state -- pinning is a commitment.
3. Use the `pin_schema` tool from the symbi MCP server (or invoke `symbi schemapin pin --mcp-server <name>`).
4. Report the pinned fingerprint and key ID so the user can record it out-of-band.
5. Suggest re-running `/symbi-verify` to confirm the pin round-trips.

## After Pinning

- Future SessionStart runs will detect any schema mutation and surface a FAILED warning.
- To intentionally accept an upstream schema change, the user must re-run this skill -- tell them so.
- If `symbi` is not on PATH, fall back to explaining the pin workflow and point at `/symbi-status`.

## Failure Modes

- **Server unreachable**: cannot fetch schema -- ask the user to verify the server starts.
- **Conflicting pin exists**: a prior pin is present; do not silently overwrite. Show both fingerprints and ask the user to choose.
- **No publisher key**: server does not publish a SchemaPin key -- warn the user that only TOFU pinning is possible.
