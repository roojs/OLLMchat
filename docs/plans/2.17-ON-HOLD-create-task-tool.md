# 2.17. Create Task Tool

## Status

⏸️ **ON HOLD** - Task tool needs to be implemented. This is a to-do list feature, which would normally be handled by creating a to-do list on the plan itself, so it may not be needed.

## Purpose

Create a task management tool (TodoWrite/task-tool) that allows agents to create, update, and manage task lists during planning and implementation workflows. This tool is referenced in multiple workflows and agents as "TodoWrite" or "task-tool" and is used for tracking progress on complex multi-step tasks.

## Requirements

1. **Task List Management**: Create and manage task lists with multiple items
2. **Task Status Tracking**: Track task status (pending, in_progress, completed, cancelled)
3. **Task Updates**: Update task status and content during workflow execution
4. **Tool Name**: Must be registered as "TodoWrite" to match agent references, with internal name "task_tool" or "todo_write"

## Usage Context

The task tool is referenced in:
- **Agents**: `web-search-researcher.md` lists `TodoWrite` in tools
- **Workflows**: Multiple workflows reference `task-tool`:
  - `create_plan.md`
  - `ralph_plan.md`
  - `ralph_impl.md`
  - `research_codebase.md`
  - `research_codebase_generic.md`
  - `oneshot_plan.md`
  - `debug.md`

**Common Usage Patterns:**
- "Create a research todo list using the task tool to track all subtasks"
- "Use the task tool to track your tasks"
- "Use the task tool to track your progress"
- "Use TodoWrite to maintain task continuity"

## Implementation Approach

### Option 1: Simple Wrapper Tool
If task management can be handled via file operations, create a wrapped tool that uses `edit_mode` or file writing to manage task lists in markdown format.

### Option 2: Full Tool Implementation
Create a dedicated tool class that:
- Manages task lists in memory or database
- Provides structured task management API
- Supports task creation, updates, status changes
- Returns task list summaries

### Option 3: Integration with Existing System
If there's an existing task/todo system, integrate with it or create an alias/wrapper.

## Files to Create/Modify

### Core Tool Files (if full implementation)
- `liboctools/TaskTool/Tool.vala` - Main tool class (namespace: `OLLMtools.TaskTool`)
- `liboctools/TaskTool/Request.vala` - Request handler class
- `liboctools/meson.build` - Add new files to build

### Wrapped Tool File (if simple wrapper)
- `resources/wrapped-tools/TodoWrite.tool` - Alias/wrapper definition

## Tool Interface

The tool should support operations like:
- Create task list with initial tasks
- Add task to existing list
- Update task status
- Update task content
- Get task list summary
- Mark tasks as complete/cancelled

## Parameters

Potential parameters:
- `action` (string) - Action to perform: "create", "add", "update", "get", "merge"
- `tasks` (array) - Array of task objects with `id`, `content`, `status`
- `list_id` (string, optional) - Identifier for task list (for multi-list scenarios)

## Next Steps

1. **Research**: Determine if existing task management system exists
2. **Design Decision**: Choose implementation approach (wrapper vs full tool)
3. **Implementation**: Create tool files and integrate
4. **Testing**: Verify tool works in workflow contexts
5. **Documentation**: Update agent/workflow docs with tool usage

## Related Plans

- 2.16-wrapped-tools.md - Wrapped tools infrastructure (may be used if wrapper approach)
- Workflow plans that reference task-tool
