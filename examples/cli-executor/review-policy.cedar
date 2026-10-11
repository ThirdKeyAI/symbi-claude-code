// Managed runtime schema; source roots separately bound all reads.
// No write, shell or arbitrary network tool is permitted here.
permit(principal, action == Action::"tool_call::claude_code", resource);
permit(principal, action == Action::"tool_call::read_file", resource);
permit(principal, action == Action::"tool_call::list_files", resource);
permit(principal, action == Action::"tool_call::grep_files", resource);
