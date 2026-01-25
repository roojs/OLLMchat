# 1.21. Multi-Agent Flow

## Status

⏳ **NOT STARTED**

## Overview

Add support for a configurable plans directory that allows users to specify where implementation plans should be stored. This will enable better organization and flexibility for different project structures.

## Problem

Currently, the workflow assumes plans are stored in `docs/plans/` or falls back to `/plans`. However, users may want to:
- Store plans in a different location
- Use a centralized plans directory across multiple projects
- Configure the plans location based on their workflow preferences

## Goals

1. **Configurable Plans Directory**: Allow users to configure where plans are stored
2. **Default Behavior**: Default to `datadir/plans` if no configuration is provided
3. **Fallback Logic**: Maintain existing fallback to `docs/plans` if it exists in the project
4. **Configuration Integration**: Integrate with existing configuration system

## Implementation Plan

### Phase 1: Configuration Support

1. **Add Plans Directory Configuration**
   - Add `plans_directory` configuration option
   - Default value: `datadir/plans`
   - Allow absolute or relative paths
   - Support environment variable expansion if applicable

2. **Update Configuration Schema**
   - Add plans directory field to configuration structure
   - Ensure proper validation of directory paths
   - Handle path resolution (absolute vs relative)

### Phase 2: Directory Resolution Logic

1. **Implement Resolution Priority**
   - First: Check if `docs/plans` exists in project root
   - Second: Use configured `plans_directory` if set
   - Third: Fall back to default `datadir/plans`
   - Ensure directory exists or create it if needed

2. **Update Workflow Logic**
   - Modify `create_plan` workflow to use new resolution logic
   - Update path references throughout the workflow
   - Ensure proper error handling for invalid paths

### Phase 3: Integration and Testing

1. **Update Workflow Documentation**
   - Update workflow file to reflect new behavior
   - Document configuration options
   - Provide examples of different configurations

2. **Testing**
   - Test with `docs/plans` existing
   - Test with configured plans directory
   - Test with default `datadir/plans`
   - Test error cases (invalid paths, permissions)

## Requirements

1. **Backward Compatibility**: Existing workflows using `docs/plans` should continue to work
2. **Configuration File**: Plans directory should be configurable via user configuration
3. **Directory Creation**: System should create plans directory if it doesn't exist (with appropriate permissions)
4. **Path Validation**: Validate that configured path is accessible and writable

## Success Criteria

### Automated Verification:
- [ ] Configuration option can be set and retrieved
- [ ] Directory resolution follows priority order correctly
- [ ] Plans directory is created if it doesn't exist
- [ ] Invalid paths are handled gracefully with error messages
- [ ] Unit tests pass for directory resolution logic

### Manual Verification:
- [ ] Plans are written to correct location based on configuration
- [ ] Fallback to `docs/plans` works when it exists
- [ ] Default `datadir/plans` is used when no configuration is set
- [ ] Configuration changes take effect immediately
- [ ] Error messages are clear when directory cannot be created

## Converting Commands to Workflows

### Summary of Changes Made to `create_plan.md`

This section documents the conversion of the `create_plan` command to a workflow format, establishing the pattern for future command-to-workflow conversions.

#### 1. File Structure and Location
- **Created**: New `resources/workflows/` directory
- **Moved**: `resources/commands/create_plan.md` → `resources/workflows/create_plan.md`
- **Rationale**: Workflows are a type of agent that manage specific file types, distinct from commands

#### 2. Frontmatter Updates
Added comprehensive frontmatter metadata:
- `name: create_plan` - Workflow identifier
- `manages: plan-file` - Indicates this workflow manages plan files
- `agents:` - List of agents the workflow can use (codebase-locator, codebase-analyzer, etc.)
- `tools:` - List of tools available (ticket-tool, read_file, task-tool, agent-tool)
- `model: opus` - Model preference

#### 3. Terminology Changes
- **"command" → "workflow"**: Updated all references to reflect workflow nature
- **"parameters" → "user's input"**: Workflows take prompts, not parameters
- **"spawn/spawning" → "use the agent tool"**: Clarified that agents are invoked via tool calls
- **"thoughts" → "document"**: Updated terminology (thoughts-locator → document-locator, etc.)
- **"TodoWrite" → "task tool"**: Updated tool name references
- **"linear-searcher" → "ticket tool"**: Clarified that linear-searcher is actually a tool, not an agent

#### 4. Agent and Tool Usage
- **Parallel execution**: Clarified that "in parallel" means multiple agent tool requests in a single tool call batch (synchronous)
- **Removed "wait for completion"**: Tool calls are synchronous, so waiting instructions are unnecessary
- **Agent tool**: Explicitly state to use the agent tool to run agents, not "spawn tasks"

#### 5. File Path Updates
- **Plans directory**: Changed from `thoughts/shared/plans/` → `docs/plans/` with fallback to `/plans`
- **Research directory**: Changed from `documents/shared/research/` → `docs/Research/`
- **Ticket references**: Updated from `documents/allison/tickets/eng_XXXX.md` → `[URL or ticket ID]` format
- **Branch naming**: Changed from `ENG-XXXX` → `TXXX` to match branch naming standards

#### 6. Plan Management System
**Removed file-writing instructions** and replaced with prompt-based plan management:
- Plans are included in the prompt context
- **Full plan update**: Use `---UPDATE PLAN---` ... `---END---` markers
- **Section update**: Use `---UPDATE SECTION---` starting [section header] ... `---END---`
- **Add section**: Use `---ADD SECTION---` after [section header] ... `---END---`

This eliminates file I/O operations and makes plan management part of the conversation flow.

#### 7. Removed Obsolete Steps
- **Removed sync steps**: System automatically indexes all files, so `humanlayer documents sync` is unnecessary
- **Removed file location presentation**: No longer needed since plans are in prompt context

#### 8. Workflow-Specific Instructions
- **Introduction**: Added "You are a project planning specialist" and "You should follow the steps below"
- **Ticket handling**: Use ticket tool if available, otherwise check user's context
- **File reading**: Check what user is looking at in prompt area when files are mentioned

### Key Logic Changes

1. **Workflows vs Commands**:
   - Workflows are agents that manage specific file types (indicated by `manages:` field)
   - Workflows take prompts, not parameters
   - Workflows use the agent tool to run other agents
   - Workflows maintain state through prompt context, not file I/O

2. **Plan Management**:
   - Plans are managed in-memory through prompt context
   - Updates use special markers (`---UPDATE PLAN---`, `---UPDATE SECTION---`, `---ADD SECTION---`)
   - No file writing required during workflow execution

3. **Agent Invocation**:
   - Agents are invoked via the agent tool
   - Multiple agents can be run in parallel by making multiple agent tool requests in a single batch
   - Tool calls are synchronous, so no waiting/coordination needed

4. **Directory Resolution**:
   - Plans directory: Check `docs/plans` first, then configured `plans_directory`, then default `datadir/plans`
   - Research directory: `docs/Research/`
   - Ticket references: URL, ticket ID, or file path

### Pattern for Future Conversions

When converting other commands to workflows:
1. Move file to `resources/workflows/`
2. Add frontmatter with `name`, `manages`, `agents`, `tools`
3. Update terminology (command → workflow, parameters → user's input)
4. Replace file I/O with prompt-based management using markers
5. Update agent/tool invocation to use explicit tool calls
6. Remove sync/wait steps (tool calls are synchronous)
7. Update file paths and references to match current standards

## References

- Related workflow: `resources/workflows/create_plan.md`
- Configuration system: (to be determined based on existing config structure)
