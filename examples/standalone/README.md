# Optional local plugin

Install Python 3.11+ and the plugin using both commands in the root README, or
load this checkout in a standalone Claude Code session:

```sh
claude --plugin-dir /path/to/symbi-claude-code
```

Local hooks block matching supported requests and record mutable diagnostics.
They do not isolate the session, mediate arbitrary shell effects, verify every
search result, or create signed runtime journals. The plugin is optional and
can be disabled in the harness or through the operator-managed marker.

No runtime is needed for local rules. A `policies/` directory opts into required
Cedar evaluation and needs a working runtime with effective policies. Empty or
failed evaluation blocks calls.

To opt into runtime MCP tools, configure the sample `runtime-mcp.json` as a project
MCP entry outside the agent session after installing `symbi`. Review any existing
configuration before merging the sample; do not overwrite other servers.
A config pin checks this entry's hash, not remote schema signatures.

For contained execution, use the separate [managed CLI workflow](../cli-executor/README.md).
