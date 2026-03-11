// Code reviewer that runs Claude Code inside ORGA governance
metadata {
    version: "1.0.0",
    description: "Code reviewer that runs Claude Code inside ORGA governance"
}

agent code_reviewer(input: PullRequest) -> ReviewResult {
    capabilities: [read, analyze]

    policy review_policy {
        allow: read(any)
        deny: write(any)
        audit: log(all_operations)
    }

    with sandbox = "Tier1", timeout = 900.seconds {
        let review = analyze(input);
        return review;
    }
}
