# Headless callers and the governed runtime

A direct Agent SDK call does not inherit Symbiont's isolation, policies or signed
journals. Loading this plugin or setting an environment variable does not create
that boundary.

For a supported headless workflow, scaffold the separate control project in the
[managed CLI example](../cli-executor/README.md), run `symbi doctor`, then invoke
`symbi run dev --target /absolute/source --input 'Review this repository'` from
that control directory. An application can launch this CLI with an argument
array, check its exit status, and inspect the resulting signed journal.

The runtime owns admission, sandboxing, brokered tools and inference, approvals
and cleanup. The contained CLI receives no unrestricted built-in tools or loaded
plugins. Use only exact registered ToolClad names in metadata.

There is no supported example here that wraps arbitrary SDK shell execution with
an invented orchestrator API. Additional SDK transports require their own
reviewed trust boundary and end-to-end qualification. Code generation or mutation
also needs explicit output grants and approval contracts; the provided native
scaffold is deliberately read-only.
