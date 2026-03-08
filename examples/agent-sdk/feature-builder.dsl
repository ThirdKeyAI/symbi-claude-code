metadata {
    version = "1.0.0"
    description = "Headless agent using Agent SDK via CliExecutor"
}

agent feature_builder(input: FeatureSpec) -> Implementation {
    capabilities = ["read", "write", "analyze", "test"]

    executor {
        type = "claude_code"
        allowed_tools = ["Bash", "Read", "Write", "Edit", "Grep", "Glob", "mcp__symbi__*"]
        plugin = "symbi"
        model = "claude-sonnet-4-20250514"
    }

    policy build_policy {
        allow: read(any) if true
        allow: write(source_code) if input.approved
        deny: write(config) if not input.is_admin
        audit: all_operations
    }

    with sandbox = "tier1", timeout = "60m", budget_tokens = 100000 {
        implementation = build(input)
        return implementation
    }
}
