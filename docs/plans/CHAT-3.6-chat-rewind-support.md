# 3.6. Chat Rewind Support

## Overview

Support for rewinding the chat view to a particular point in history. May involve git checkpoints when committing code changes.

## Status

⏳ **TODO** - To be implemented.

## Implementation Details

### Features
- Rewind chat view to a specific point in message history
- Git checkpoint integration for code commits
- Visual indication of rewind point
- Ability to continue from rewind point

### Git Integration Requirements
- **Important**: Git committing automatically should NOT be done on main/master branch
- Use work-in-progress branch for automatic commits
- Create git checkpoints when code changes are committed
- Link chat messages to git commits/checkpoints

### Use Cases
- Review conversation at a specific point
- Restore code state to a checkpoint
- Continue conversation from a previous point
- Undo changes by rewinding

### Implementation Approach
- Add rewind UI (slider, timeline, or message selection)
- Store checkpoint information with messages
- Integrate with git for code checkpoints
- Create work-in-progress branch for auto-commits
- Link messages to git commits

### Files to Create/Modify
- `libollmchatgtk/ChatView.vala` - Rewind UI
- `libollmchat/History/Session.vala` - Checkpoint storage
- Git integration module
- Checkpoint management system

### Implementation Notes
- Design rewind UI (timeline, slider, message list)
- Determine checkpoint storage format
- Implement git integration (work-in-progress branch)
- Handle git operations safely (no auto-commit on main/master)
- Store checkpoint references with messages
- Allow continuing from rewind point

### Related Plans
- Review and modify any existing plans that discussed git auto-committing
- Ensure git operations respect branch protection
