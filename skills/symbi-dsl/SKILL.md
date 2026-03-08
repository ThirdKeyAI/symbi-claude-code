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
