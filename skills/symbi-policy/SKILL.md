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
