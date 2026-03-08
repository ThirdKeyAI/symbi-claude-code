// Policy for code_reviewer agent
// Allow read access to all resources
permit(
    principal == Agent::"code_reviewer",
    action == Action::"read",
    resource
);

// Forbid write access unless the PR is in draft mode
forbid(
    principal == Agent::"code_reviewer",
    action == Action::"write",
    resource
) unless {
    resource.pr_status == "draft"
};
