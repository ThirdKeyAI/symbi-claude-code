# Governed managed CLI on Linux

Use the current Symbiont runtime for isolation without Docker or a VM. The local
plugin is not loaded in a managed worker. Built-in tools, automatic plugins and
arbitrary MCP discovery are disabled; exact registered ToolClad tools are
available through the broker.

## Scaffold a read-only review

Install the runtime and the supported managed CLI executable. Keep the new,
empty control directory separate from the source repository:

```sh
symbi init --sandbox landlock --profile dev-agent --dir ./control \
  --source /home/developer/project \
  --managed-executable /home/developer/.local/bin/claude \
  --inference-url http://127.0.0.1:8000 \
  --inference-model your-configured-model \
  --inference-key-env REVIEW_PROVIDER_KEY
cd control
symbi doctor
symbi run dev --target /home/developer/project \
  --input 'Review this repository using the source tools. Report findings without changing files.'
```

Set `REVIEW_PROVIDER_KEY` in the operator environment or the control project's
private environment configuration. The initialization flag takes its variable
name, not a secret. The endpoint must support the Messages API expected by the
managed CLI. Initialization and `doctor` do not validate model access.

Landlock requires supported Linux kernel features, seccomp, delegated cgroup v2,
a systemd user manager, and permitted unprivileged namespaces. Managed workers use
a private loopback network namespace and inherited broker connections. Missing
prerequisites fail the operation; there is no unrestricted fallback. This example
does not implement native macOS or Windows isolation.

## What the scaffold provides

The generated agent's metadata selects `executor = "claude_code"` and the exact
`allowed_tools = "read_file,list_files,grep_files"` list. The generated control
project contains matching tool manifests, managed admission/tool policies,
read-only source roots, and no output roots or shell tools.

[code-reviewer.symbi](code-reviewer.symbi) and
[review-policy.cedar](review-policy.cedar) illustrate that contract. Prefer the
scaffold's complete generated project over copying these two files alone.
The managed policies use `Action::"tool_call::..."`; they are a different request
schema from standalone plugin policies using `Symbi::Action`.

Do not add built-in names such as Bash/Read or wildcard tool names to the managed
allowlist. Do not pass `--plugin-dir` or install this plugin as a parent-runtime
bridge. Environment flags do not establish containment.

Source content reaches the worker only through authorized broker results.
Credentials, policy controls, approval state and signed journals remain outside
its authority. Inspect the actual run's journal with `symbi audit inspect`, using
the public key and run ID retained through a trusted channel.

For custom writes or command outputs, consult the runtime's filesystem-grant and
approval contracts. A broader allowlist alone does not authorize source writes.
See the runtime's `docs/landlock-development.md` and
`docs/managed-cli-containment.md` for deployment and qualification requirements.
