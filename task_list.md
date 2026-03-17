## Original prompt

We added project path support for sessions — however its' not getting filled in with any value.

## Goals / summary

The user is reporting a bug where the project path feature added to sessions is not being populated with actual values. This task list will research the session and project path implementation, identify where the value should be set, analyze why it's not being populated, and produce a fix for the issue.

## Tasks

### Task section 1

- **Name** Research Sessions
- **What is needed** Find session-related code, particularly where project path support was added, and understand the session storage mechanism.
- **Skill** analyze_codebase
- **References** [sessions](libollmchat/)
- **Expected output** Findings about session implementation and project path support location.

- **Name** Research Session Files
- **What is needed** Locate specific session-related files (JSON, C/Vala files) that handle session creation, loading, and project path storage.
- **Skill** analyze_codebase
- **References** [session](libollmchat/), [project path](libollmchat/)
- **Expected output** List of relevant files where session data is created and persisted.

- **Name** Coding Standards Research
- **What is needed** Locate project coding standards to ensure any fixes align with established conventions.
- **Skill** analyze_code_standards
- **References** [.cursor/rules/CODING_STANDARDS.md](.cursor/rules/CODING_STANDARDS.md)
- **Expected output** Coding conventions and style guidelines for reference.

### Task section 2

- **Name** Analysis Project Path Issue
- **What is needed** Analyze the session implementation to identify where project path should be set and why it's not getting a value.
- **Skill** analyze_code
- **References** [Research Sessions Results](task://research-sessions.md), [Research Session Files Results](task://research-session-files.md)
- **Expected output** Findings document identifying the root cause of the project path not being populated.

### Task section 3

- **Name** Plan Fix
- **What is needed** Produce a concrete fix plan for the project path issue, including code changes needed.
- **Skill** plan_code
- **References** [Analysis Project Path Issue Results](task://analysis-project-path-issue.md)
- **Expected output** Proposed code changes for the fix.

### Task section 4

- **Name** Review Plan
- **What is needed** Review the proposed fix against coding standards and ensure correctness before implementation.
- **Skill** plan_review
- **References** [Plan Fix Results](task://plan-fix.md)
- **Expected output** Reviewed and validated fix ready for implementation.

### Task section 5

- **Name** Implement Fix
- **What is needed** Apply the code changes to fix the project path not being filled in.
- **Skill** implement_code
- **References** [Plan Fix Results](task://plan-fix.md)
- **Expected output** Fixed code with project path support working.
- **Requires user approval**