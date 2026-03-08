---
name: symbi-verify
description: Verify MCP tool schemas using SchemaPin cryptographic verification. Use when adding new MCP servers, auditing existing tool integrations, or checking tool integrity.
---

# SchemaPin Verification

Verify the cryptographic integrity of MCP tool schemas to ensure they haven't been tampered with.

## Verification Process

1. Identify the MCP server to verify (from .mcp.json or the user's request)
2. Use the `verify_schema` tool from the symbi MCP server to check the schema
3. Report the verification result:
   - **Verified**: Schema signature matches the publisher's key
   - **TOFU**: First-time use, key has been pinned for future verification
   - **Failed**: Schema has been modified since signing — DO NOT USE
   - **No signature**: Schema is unsigned — warn the user about risks

## When to Verify

- Before first use of any new MCP tool
- After updating MCP server configurations
- When security audit is requested
- When a tool returns unexpected results
