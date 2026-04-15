
# ROADMAP — symbi-claude-code Plugin Implementation Plan

## Project Overview

Build a Claude Code plugin that brings Symbiont's trust stack (ORGA, Cedar policies, SchemaPin, sandboxing) to Claude Code users. The plugin exposes Symbiont agents as MCP tools, enforces Cedar policies via hooks, and provides skills for agent development and governance.

**Repo**: `thirdkeyai/symbi-claude-code` (separate from the Symbiont monorepo)
**License**: Apache 2.0

---

## Directory Structure

```
symbi-claude-code/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest (required)
│   └── marketplace.json         # Self-contained marketplace catalog
├── .mcp.json                    # MCP server config pointing to symbi binary
├── settings.json                # Default settings (activates symbi agent)
├── hooks/
│   └── hooks.json               # Hook config for Cedar policy enforcement
├── scripts/
│   ├── policy-log.sh            # PreToolUse hook: advisory policy logging
│   ├── audit-log.sh             # PostToolUse hook: cryptographic audit trail
│   └── install-check.sh         # SessionStart hook: verify symbi is installed + SchemaPin-verify pinned MCP servers
├── agents/
│   ├── symbi-governor.md        # Main governance agent
│   └── symbi-dev.md             # DSL development agent
├── skills/
│   ├── symbi-init/
│   │   └── SKILL.md             # /symbi-init — scaffold a governed agent project
│   ├── symbi-policy/
│   │   └── SKILL.md             # /symbi-policy — create/edit Cedar policies
│   ├── symbi-verify/
│   │   └── SKILL.md             # /symbi-verify — SchemaPin verify MCP tools
│   ├── symbi-audit/
│   │   └── SKILL.md             # /symbi-audit — query audit logs
│   └── symbi-dsl/
│       └── SKILL.md             # /symbi-dsl — parse/validate DSL files
├── commands/
│   └── symbi-status.md          # /symbi-status — runtime health check
├── examples/
│   ├── standalone/              # Mode A: plugin-only setup
│   ├── cli-executor/            # Mode B: ORGA-wrapped Claude Code
│   └── agent-sdk/               # Agent SDK wrapper pattern
├── CLAUDE.md                    # Plugin-level instructions for Claude Code
├── README.md                    # Documentation
├── LICENSE                      # Apache 2.0
├── CHANGELOG.md
├── ROADMAP.md                   # Implementation plan
└── install.sh                   # Optional: install symbi binary if not present
```

---

## Implementation Tasks

### Phase 1: Scaffold and MCP Server Integration

**Goal**: Get the plugin installable and the MCP server connected.

#### Task 1.1: Create plugin manifest

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "symbi",
  "description": "Zero-trust AI agent governance for Claude Code. Adds ORGA runtime, Cedar policy enforcement, SchemaPin tool verification, and cryptographic audit trails to your development workflow.",
  "version": "0.2.0",
  "author": {
    "name": "ThirdKey AI",
    "email": "hello@thirdkey.ai",
    "url": "https://thirdkey.ai"
  },
  "homepage": "https://symbiont.dev",
  "repository": "https://github.com/thirdkeyai/symbi-claude-code",
  "license": "Apache-2.0",
  "keywords": [
    "security",
    "governance",
    "zero-trust",
    "cedar",
    "mcp",
    "agent-runtime",
    "policy-enforcement",
    "audit",
    "schemapin",
    "enterprise"
  ],
  "skills": "./skills/",
  "agents": "./agents/",
  "commands": "./commands/",
  "hooks": "./hooks/hooks.json",
  "mcpServers": "./.mcp.json"
}
```

#### Task 1.2: Create marketplace catalog

Create `.claude-plugin/marketplace.json`:

```json
{
  "name": "symbi-marketplace",
  "metadata": {
    "description": "ThirdKey AI agent governance plugins for Claude Code",
    "url": "https://thirdkey.ai"
  },
  "owner": {
    "name": "ThirdKey AI",
    "url": "https://github.com/thirdkeyai"
  },
  "plugins": [
    {
      "name": "symbi",
      "source": ".",
      "version": "0.2.0",
      "description": "Zero-trust AI agent governance — ORGA runtime, Cedar policies, SchemaPin verification, and cryptographic audit trails for Claude Code."
    }
  ]
}
```

#### Task 1.3: Create MCP server configuration

Create `.mcp.json`. This connects Claude Code to Symbiont's existing MCP server (`src/mcp_server/mod.rs`), which already exposes `invoke_agent`, `list_agents`, `parse_dsl`, `get_agent_dsl`, `get_agents_md`, and `verify_schema` tools.

```json
{
  "mcpServers": {
    "symbi": {
      "command": "symbi",
      "args": ["mcp"],
      "env": {
        "SYMBIONT_LOG_LEVEL": "warn",
        "RUST_LOG": "warn"
      }
    }
  }
}
```

**Important**: The `symbi` binary must be on PATH. The install-check hook (Task 3.1) will verify this and guide the user if it's missing.

#### Task 1.4: Create plugin-level CLAUDE.md

This file provides Claude Code with context about Symbiont when the plugin is active.

#### Task 1.5: Create default settings

Create `settings.json` to activate the governance agent by default:

```json
{
  "agent": "symbi-governor"
}
```

---

### Phase 2: Skills and Commands

**Goal**: Provide useful slash commands that showcase Symbiont's capabilities.

#### Task 2.1: /symbi-init skill

Create `skills/symbi-init/SKILL.md`:

```markdown
---
name: symbi-init
description: Initialize a Symbiont-governed project. Creates agent definitions, Cedar policies, and configuration files. Use when setting up a new project with AI agent governance or adding Symbiont to an existing project.
---

# Initialize Symbiont Project

Set up a governed agent project in the current directory.

## Steps

1. Check if `symbiont.toml` already exists. If so, ask before overwriting.

2. Create the directory structure:
   ```
   agents/          # Agent DSL definitions
   policies/        # Cedar policy files
   ```

3. Create `symbiont.toml` with sensible defaults:
   ```toml
   [runtime]
   security_tier = "tier1"   # Docker isolation
   log_level = "info"

   [policy]
   engine = "cedar"
   enforcement = "strict"

   [schemapin]
   mode = "tofu"  # Trust-On-First-Use
   ```

4. Create a starter agent at `agents/assistant.dsl`:
   ```symbiont
   metadata {
       version = "1.0.0"
       description = "Default governed assistant"
   }

   agent assistant(input: Query) -> Response {
       capabilities = ["read", "analyze"]

       policy default_access {
           allow: read(input) if true
           deny: write(any) if not approved
           audit: all_operations
       }

       with memory = "session" {
           result = process(input)
           return result
       }
   }
   ```

5. Create a starter Cedar policy at `policies/default.cedar`:
   ```cedar
   // Default: allow read operations, require approval for writes
   permit(
       principal,
       action == Action::"read",
       resource
   );

   forbid(
       principal,
       action == Action::"write",
       resource
   ) unless {
       principal.approved == true
   };
   ```

6. Create `AGENTS.md` manifest for the project.

7. Report what was created and suggest next steps.
```

#### Task 2.2: /symbi-policy skill

Create `skills/symbi-policy/SKILL.md`:

```markdown
---
name: symbi-policy
description: Create, edit, or validate Cedar authorization policies for Symbiont agents. Use when defining access control rules, setting up security policies, or debugging policy evaluation.
---

# Cedar Policy Management

Help the user create or modify Cedar policies for their Symbiont agents.

## Cedar Policy Syntax Reference

Cedar policies use `permit` and `forbid` to control access:

```cedar
// Allow an agent to read from a specific resource
permit(
    principal == Agent::"data-analyzer",
    action == Action::"read",
    resource in ResourceGroup::"public-datasets"
);

// Forbid writing PII unless the agent has HIPAA compliance
forbid(
    principal,
    action == Action::"write",
    resource
) when {
    resource.contains_pii == true
} unless {
    principal.compliance_level == "hipaa"
};
```

## Common Policy Patterns

When asked to create a policy, identify the pattern:
- **Role-based**: Different agent roles get different permissions
- **Resource-scoped**: Permissions vary by resource type/sensitivity
- **Time-bounded**: Permissions that expire or are scheduled
- **Approval-gated**: Actions requiring human approval
- **Audit-all**: Log everything, permit/deny selectively

## Workflow

1. Ask what the policy should govern (which agents, which actions, which resources)
2. Identify the pattern from the list above
3. Write the Cedar policy
4. Save to `policies/` directory
5. If symbi is available, validate with `symbi dsl parse` to check syntax
```

#### Task 2.3: /symbi-verify skill

Create `skills/symbi-verify/SKILL.md`:

```markdown
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
```

#### Task 2.4: /symbi-audit skill

Create `skills/symbi-audit/SKILL.md`:

```markdown
---
name: symbi-audit
description: Query and analyze Symbiont's cryptographic audit logs. Use when reviewing agent activity, investigating incidents, or preparing compliance reports.
---

# Audit Log Analysis

Query Symbiont's tamper-evident audit logs to review agent activity.

## Available Queries

- Recent activity: What agents ran and what they did
- Policy decisions: Which policies were evaluated and their outcomes
- Tool usage: Which MCP tools were invoked and by which agents
- Security events: Failed verifications, policy denials, sandbox violations

## Workflow

1. Ask what the user wants to investigate
2. Use the symbi MCP server to query relevant logs
3. Present findings in a clear, chronological format
4. Flag any anomalies or security concerns
5. Suggest policy adjustments if patterns indicate issues
```

#### Task 2.5: /symbi-dsl skill

Create `skills/symbi-dsl/SKILL.md`:

```markdown
---
name: symbi-dsl
description: Parse, validate, and create Symbiont DSL agent definitions. Use when writing new agents, debugging DSL syntax errors, or understanding existing agent definitions.
allowed-tools: ["mcp__symbi__parse_dsl", "mcp__symbi__get_agent_dsl", "mcp__symbi__list_agents"]
---

# Symbiont DSL Development

Help the user write and debug Symbiont agent definitions.

## DSL Structure

```symbiont
metadata {
    version = "1.0.0"
    author = "developer"
    description = "Agent purpose"
}

agent name(input: Type) -> ReturnType {
    capabilities = ["list", "of", "caps"]

    policy policy_name {
        allow: action(resource) if condition
        deny: action(resource) if condition
        audit: all_operations
    }

    schedule cron_task {
        cron = "0 9 * * MON-FRI"
        agent = "name"
    }

    webhook incoming_hook {
        path = "/hooks/trigger"
        method = "POST"
    }

    channel slack_notify {
        type = "slack"
        webhook_url = env("SLACK_WEBHOOK")
    }

    with memory = "persistent", requires = "approval" {
        // agent logic
    }
}
```

## Workflow

1. Use `list_agents` to see what agents exist
2. Use `get_agent_dsl` to read an agent's definition
3. Use `parse_dsl` to validate syntax after edits
4. Help the user iterate on their agent definitions
```

#### Task 2.6: /symbi-status command

Create `commands/symbi-status.md`:

```markdown
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
```

---

### Phase 3: Hooks for Policy Enforcement

**Goal**: Use Claude Code hooks to enforce Cedar policies and SchemaPin verification at the point of tool execution.

#### Task 3.1: Install check hook (SessionStart)

Create `scripts/install-check.sh`:

```bash
#!/bin/bash
# Verify symbi binary is available on PATH
if ! command -v symbi &> /dev/null; then
    echo '{"feedback": "Symbiont (symbi) is not installed or not on PATH. Some governance features will be unavailable. Run /symbi-status for installation instructions."}' >&2
    exit 0  # Non-blocking — don't prevent session start
fi

VERSION=$(symbi --version 2>/dev/null || echo "unknown")
echo "{\"feedback\": \"Symbiont governance active (${VERSION})\"}" >&2
exit 0
```

#### Task 3.2: Policy logging hook (PreToolUse)

Create `scripts/policy-log.sh`:

```bash
#!/bin/bash
# PreToolUse hook: Check Cedar policies before tool execution
# Reads tool invocation from stdin, evaluates against Cedar policies
#
# This is a lightweight check — full ORGA Gate enforcement happens
# inside the Symbiont runtime for invoke_agent calls.

# Read the tool input from stdin
TOOL_INPUT=$(cat)
TOOL_NAME=$(echo "$TOOL_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Skip check if symbi is not installed or no policies directory exists
if ! command -v symbi &> /dev/null || [ ! -d "policies" ]; then
    exit 0
fi

# Skip check for read-only/safe tools
case "$TOOL_NAME" in
    Read|Glob|Grep|LS|View)
        exit 0
        ;;
esac

# For tools that modify state, log the action for audit
# Full Cedar evaluation would go here in a production implementation
# For now, we provide feedback noting the action is being tracked
echo "{\"feedback\": \"Action logged: ${TOOL_NAME}\"}" >&2
exit 0
```

#### Task 3.3: Audit logging hook (PostToolUse)

Create `scripts/audit-log.sh`:

```bash
#!/bin/bash
# PostToolUse hook: Append tool usage to audit log
# Creates a structured log entry for each tool invocation

TOOL_INPUT=$(cat)
TOOL_NAME=$(echo "$TOOL_INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Only log if symbiont.toml exists (project is governed)
if [ -f "symbiont.toml" ]; then
    LOG_DIR=".symbiont/audit"
    mkdir -p "$LOG_DIR"
    echo "{\"timestamp\": \"${TIMESTAMP}\", \"tool\": \"${TOOL_NAME}\", \"source\": \"claude-code\"}" >> "${LOG_DIR}/tool-usage.jsonl"
fi

exit 0
```

#### Task 3.4: Hook configuration

Create `hooks/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Bash|mcp__*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/policy-log.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|Bash|mcp__*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/audit-log.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

**Note**: SessionStart hooks are not yet widely supported in the plugin system. The install check can be moved to a PreToolUse hook on first invocation, or handled by the CLAUDE.md instructions.

---

### Phase 4: Agents

**Goal**: Define specialized agents that leverage Symbiont's capabilities.

#### Task 4.1: Governance agent

Create `agents/symbi-governor.md`:

```markdown
---
name: symbi-governor
description: Governance-aware coding agent that enforces security policies and maintains audit trails. Activated by default when the Symbiont plugin is enabled.
model: claude-sonnet-4-20250514
allowed-tools: [
  "Read", "Write", "Edit", "Bash", "Glob", "Grep", "LS",
  "mcp__symbi__invoke_agent",
  "mcp__symbi__list_agents",
  "mcp__symbi__parse_dsl",
  "mcp__symbi__get_agent_dsl",
  "mcp__symbi__verify_schema"
]
---

You are a governance-aware coding assistant powered by Symbiont. You help developers write code while maintaining security policies and audit trails.

## Core Behaviors

1. **Policy Awareness**: Before modifying files or executing commands that affect production systems, check if Cedar policies in `policies/` apply. Respect deny rules.

2. **Tool Verification**: When using MCP tools for the first time, verify their schemas using SchemaPin via `verify_schema`.

3. **Audit Trail**: Important actions should be noted. The PostToolUse hook handles automatic logging, but call out security-relevant decisions in your responses.

4. **Agent Governance**: When asked to create or modify agents, ensure their DSL definitions include appropriate policy blocks and capability restrictions.

5. **Least Privilege**: Default to the minimum capabilities needed. Don't request broad permissions when narrow ones suffice.

## When to Escalate

- If a requested action would violate a Cedar policy, explain which policy blocks it and suggest alternatives
- If an MCP tool fails SchemaPin verification, warn the user and do not proceed
- If an agent definition lacks security policies, suggest appropriate ones before proceeding
```

#### Task 4.2: DSL development agent

Create `agents/symbi-dev.md`:

```markdown
---
name: symbi-dev
description: Specialized agent for developing Symbiont DSL definitions, Cedar policies, and trust stack configurations. Use for agent development tasks.
model: claude-sonnet-4-20250514
allowed-tools: [
  "Read", "Write", "Edit", "Bash", "Glob", "Grep", "LS",
  "mcp__symbi__invoke_agent",
  "mcp__symbi__list_agents",
  "mcp__symbi__parse_dsl",
  "mcp__symbi__get_agent_dsl",
  "mcp__symbi__verify_schema"
]
---

You are a Symbiont DSL development specialist. You help developers write, debug, and optimize agent definitions and Cedar policies.

## Expertise Areas

- **DSL Syntax**: Agent definitions, behavior blocks, metadata, schedules, webhooks, channels
- **Cedar Policies**: Authorization rules, condition expressions, principal/action/resource modeling
- **Trust Configuration**: SchemaPin setup, AgentPin identity, sandbox tier selection
- **Testing**: Agent behavior validation, policy simulation, DSL parsing

## Development Workflow

1. Understand requirements — what should the agent do and what are its security constraints
2. Design the agent's capabilities and policy model
3. Write the DSL definition with inline documentation
4. Validate with `parse_dsl` after each edit
5. Create corresponding Cedar policies
6. Test the agent with `invoke_agent`

## Best Practices to Enforce

- Every agent must have at least one policy block
- Use the most restrictive sandbox tier that meets requirements
- Capabilities should be explicitly listed, never wildcarded
- Schedule and webhook blocks need corresponding security policies
- DSL files should include metadata with version and description
```

---

### Phase 5: Documentation and Distribution

#### Task 5.1: README.md

Write a comprehensive README covering:

- What the plugin does and why (1-paragraph pitch)
- Prerequisites (symbi binary installed, or Docker)
- Installation via marketplace: `/plugin marketplace add https://github.com/thirdkeyai/symbi-claude-code`
- Installation via local dev: `claude --plugin-dir ./symbi-claude-code`
- Quick start: install -> `/symbi-init` -> write agents -> govern
- Available skills, agents, and hooks
- Configuration options
- Link to Symbiont docs, ThirdKey AI site

#### Task 5.2: CHANGELOG.md

Initialize with v0.2.0 entry listing all initial components.

#### Task 5.3: LICENSE

Apache 2.0 license file.

#### Task 5.4: install.sh

Optional convenience script:

```bash
#!/bin/bash
# Install symbi binary from crates.io or pre-built releases
set -e

echo "Installing Symbiont CLI..."

if command -v cargo &> /dev/null; then
    echo "Installing from crates.io..."
    cargo install symbi
elif command -v docker &> /dev/null; then
    echo "Docker detected. You can use symbi via Docker:"
    echo "  docker pull ghcr.io/thirdkeyai/symbi:latest"
    echo "  alias symbi='docker run --rm -v \$(pwd):/workspace ghcr.io/thirdkeyai/symbi:latest'"
else
    echo "Neither cargo nor docker found."
    echo "Install Rust: https://rustup.rs"
    echo "Or Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

echo "Done! Run 'symbi --version' to verify."
```

---

---

### Phase 6: CliExecutor Bridge

**Goal**: Enable the plugin to work in both standalone (Mode A) and ORGA-managed (Mode B) configurations, bridging Claude Code and Symbiont's runtime.

#### The Two Entry Points

**Mode A -- Plugin-first (developer pulls Symbiont in):**
Developer installs the plugin -> Claude Code loads hooks/MCP/skills -> Symbiont provides a governance layer *inside* Claude Code's process. The plugin spawns its own `symbi mcp` server.

**Mode B -- Runtime-first (Symbiont wraps Claude Code):**
Symbiont's CliExecutor spawns `claude` (or uses the Agent SDK programmatically) -> ORGA governs the *outer* execution loop -> Claude Code starts up and loads the same plugin -> the plugin detects it's inside a managed runtime and connects *back* to the parent Symbiont instance instead of spawning a new one.

Mode B is the dark factory architecture. Symbiont is the security perimeter; Claude Code is the execution engine inside it. The plugin becomes the bridge between the two layers.

#### Task 6.1: Environment detection in hooks

Update all hook scripts to check `SYMBIONT_MANAGED` and adjust behavior:
- `policy-log.sh`: Defer to outer ORGA Gate in Mode B, advisory logging in Mode A
- `audit-log.sh`: Skip local logging in Mode B (outer runtime journals), log locally in Mode A
- `install-check.sh`: Report managed mode in Mode B, check binary in Mode A

#### Task 6.2: MCP transport switching

For Mode B, users override the default stdio `.mcp.json` with a project-level HTTP MCP entry pointing at `SYMBIONT_MCP_URL`. Native Claude Code HTTP transport handles this without a wrapper script, avoiding the `npx @anthropic-ai/mcp-proxy` dependency. (The earlier `scripts/mcp-wrapper.sh` was removed as an orphan -- `.mcp.json` never referenced it.)

#### Task 6.3: Agent SDK skill

Create `skills/symbi-agent-sdk/SKILL.md`:
- Generate boilerplate for wrapping Claude Agent SDK agents in ORGA governance
- Document the `claude_code` executor type in DSL
- Document CliExecutor environment variables

#### Task 6.4: DSL executor type

Document the `claude_code` executor block for DSL agent definitions:

```symbiont
agent code_reviewer(input: PullRequest) -> ReviewResult {
    capabilities = ["read", "analyze"]

    executor {
        type = "claude_code"
        allowed_tools = ["Bash", "Read", "Grep", "mcp__symbi__*"]
        plugin = "symbi"
        model = "claude-sonnet-4-20250514"
    }

    policy review_policy {
        allow: read(any) if true
        deny: write(any) if not input.is_draft
        audit: all_operations
    }
}
```

#### Task 6.5: Examples

Create `examples/` directory with:
- `examples/standalone/` -- Plugin-only setup for individual developers
- `examples/cli-executor/` -- DSL + config for running Claude Code wrapped in ORGA
- `examples/agent-sdk/` -- Agent SDK wrapper pattern for headless agents

#### Task 6.6: Dual-mode documentation

Update README and CLAUDE.md with:
- Architecture diagrams for both modes
- Environment variable reference
- When to use Mode A vs Mode B

---

## Implementation Order

1. **Phase 1** (Day 1): Scaffold repo, plugin.json, marketplace.json, .mcp.json, CLAUDE.md, settings.json
2. **Phase 2** (Day 2-3): Skills (/symbi-init, /symbi-policy, /symbi-dsl, /symbi-verify, /symbi-audit) and /symbi-status command
3. **Phase 3** (Day 3-4): Hook scripts (policy-log, audit-log, install-check) and hooks.json
4. **Phase 4** (Day 4): Agent definitions (symbi-governor, symbi-dev)
5. **Phase 5** (Day 5): README, CHANGELOG, LICENSE, install.sh, test with `claude --plugin-dir`
6. **Phase 6** (Day 6): CliExecutor bridge -- environment detection, MCP transport switching, Agent SDK skill, examples, dual-mode docs

## Testing Checklist

- [ ] Plugin loads without errors: `claude --plugin-dir ./symbi-claude-code`
- [ ] `/mcp` shows symbi server connected (requires symbi binary on PATH)
- [ ] `/symbi-init` creates project scaffold
- [ ] `/symbi-dsl` triggers DSL skill correctly
- [ ] `/symbi-policy` generates valid Cedar policies
- [ ] `/symbi-status` reports installation status
- [ ] Hooks fire on Write/Edit/Bash operations (check `.symbiont/audit/`)
- [ ] `symbi-governor` agent activates as default when enabled in settings
- [ ] Plugin installs from marketplace: `/plugin marketplace add` with repo URL
- [ ] All scripts are executable (`chmod +x scripts/*.sh`)
- [ ] Hook scripts detect `SYMBIONT_MANAGED=true` and adjust behavior
- [ ] Mode B users can override `.mcp.json` with a native HTTP MCP entry pointing at `SYMBIONT_MCP_URL`
- [ ] `/symbi-agent-sdk` skill triggers correctly
- [ ] Example DSL files parse without errors

## Dependencies on Symbiont Monorepo

This plugin depends on the `symbi` binary being available. The MCP server is built from `src/mcp_server/mod.rs` in the Symbiont monorepo and exposes these tools:

- `invoke_agent` (InvokeAgentParams: agent, prompt, system_prompt?)
- `list_agents` (no params)
- `parse_dsl` (ParseDslParams: file?, content?)
- `get_agent_dsl` (GetAgentDslParams: agent)
- `get_agents_md` (no params)
- `verify_schema` (VerifySchemaParams: schema, public_key_url)

If the symbi binary is not installed, the plugin degrades gracefully — skills and agents still provide guidance, hooks still log, but MCP tools are unavailable.

## Future Enhancements (Post-v0.2.0)

- **Anthropic official marketplace submission**: Submit via `anthropics/claude-plugins-official` submission form
- **SchemaPin PreToolUse enforcement**: Full cryptographic verification before any MCP tool call
- **Cedar policy simulation**: Dry-run policy evaluation without executing actions
- **Agent SDK wrapper**: Use the Claude Agent SDK to wrap agents in ORGA governance
- **symbi.cloud integration**: Connect to hosted governance infrastructure
- **LSP server**: Bundle `repl-lsp` for DSL syntax highlighting in Claude Code
