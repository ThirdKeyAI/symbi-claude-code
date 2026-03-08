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
