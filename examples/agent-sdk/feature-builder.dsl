// Headless agent using Agent SDK via CliExecutor
metadata {
    version: "1.0.0",
    description: "Headless agent using Agent SDK via CliExecutor"
}

agent feature_builder(input: FeatureSpec) -> Implementation {
    capabilities: [read, write, analyze, test]

    policy build_policy {
        allow: read(any)
        allow: write(source_code)
        deny: write(config)
        audit: log(all_operations)
    }

    with sandbox = "Tier1", timeout = 3600.seconds {
        let implementation = build(input);
        return implementation;
    }
}
