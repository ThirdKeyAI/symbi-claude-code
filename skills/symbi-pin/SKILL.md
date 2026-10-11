---
name: symbi-pin
description: Pin a local MCP server configuration for later change detection.
---

# MCP configuration pinning

This CLI workflow hashes an entry in `.mcp.json` and stores a local pin. It does
not contact the server, fetch schemas, record a publisher key, or establish
cryptographic provenance.

1. Identify the server name and configuration path. Review the command, arguments,
   URL and environment references without printing credential values.
2. Confirm that the operator trusts the configuration now. Pinning records a
   baseline, not a safety assessment.
3. Run `symbi schemapin pin --mcp-server NAME --config /absolute/path/.mcp.json`.
   There is no `pin_schema` MCP tool.
4. Verify with `symbi schemapin verify --mcp-server NAME --config /absolute/path/.mcp.json`.
5. Report the returned configuration fingerprint, not an invented publisher key.

An existing conflicting pin requires an intentional review before `--force`.
Do not auto-repin a failed check. Pin storage is local to the operator account;
use `symbi schemapin list` to inspect records. If the CLI is missing, provide these
instructions and report pinning as unavailable.

Schema-signature verification is separate; see `/symbi:symbi-verify`.
