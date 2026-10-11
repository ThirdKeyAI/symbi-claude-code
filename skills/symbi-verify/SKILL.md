---
name: symbi-verify
description: Check local MCP configuration pins or separately verify a supplied schema signature.
---

# Verification

First identify which evidence the user wants to verify.

## Configuration consistency

For a server in `.mcp.json`, run:

```sh
symbi schemapin verify --mcp-server NAME --config /absolute/path/.mcp.json
```

A match only means the local server entry matches its recorded hash. It does not
verify remote schemas, publisher identity or server behavior. Report missing pins
and changed configurations separately using the CLI result. Do not silently pin
or overwrite a mismatch. SessionStart checks are advisory and bounded; explicitly
check additional servers if needed.

## Schema signature

The `verify_schema` MCP tool accepts `schema` (the supplied schema document as a
string) and `public_key_url` (the publisher's key URL). Obtain the schema and key
location from a trusted source; a server name alone is insufficient. Call the tool
only when connected to the runtime MCP server. Inspect its `verified`, `message`,
`schema_hash` and signature details, including `valid` when present.

Report success only from successful verification. Missing signature material,
network errors, untrusted key provenance and failed signatures remain unresolved;
a matching configuration pin does not cure them. Never invent TOFU or publisher
verification from a successful local configuration check.
