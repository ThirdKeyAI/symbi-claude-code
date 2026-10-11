# Product roadmap

The current supported behavior and setup are documented in [README.md](README.md).
The plugin is an optional local integration; secure execution is owned by the
Symbiont runtime.

## Current release

- Shared strict Python policy engine for Claude Code and Cursor.
- Preserved runtime policy arguments and blocking behavior for failures.
- Operator-managed controls, focused regression coverage and real-runtime tests.
- Accurate configuration-pin, audit and managed-workflow documentation.

## Remaining work

- Qualify each supported harness version with installed-client smoke tests,
  including cancellation, hook timeouts and warning presentation.
- Coordinate a machine-readable capability/version contract with the runtime so
  the plugin need not recognize the current evaluator's positive reason format.
- Expand tool-specific input adapters only with fixtures from documented harness
  contracts and tests for every effect-bearing argument.
- Consider additional harness adapters after their blocking contracts are verified.
- Add optional Enterprise presentation of runtime evidence without treating local
  mutable plugin logs as signed runtime journals.

Automatic plugin loading inside managed workers and environment-based enforcement
bypasses are not part of the supported design. Any new authority or public
compatibility change should be reviewed before implementation.
