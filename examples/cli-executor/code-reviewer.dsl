metadata {
    version = "1.0.0"
    description = "Code reviewer that runs Claude Code inside ORGA governance"
}

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

    with sandbox = "tier1", timeout = "15m" {
        review = analyze(input)
        return review
    }
}
