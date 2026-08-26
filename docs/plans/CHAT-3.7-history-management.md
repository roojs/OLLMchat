# 3.7. History Management

## Overview

Comprehensive history management: ability to prune, delete (flag delete), restore deleted chats, and archive deleted chats.

## Status

⏳ **TODO** - To be implemented.

## Implementation Details

### Features

#### Deletion System
- **Flag Delete** - Mark chats for deletion (soft delete)
- **Restore Deleted Chats** - Restore chats that have been flagged for deletion
- **Archive Deleted Chats** - Move deleted chats to archive (don't delete immediately)
- **Permanent Delete** - Actually delete archived chats
- **Prune** - Remove old chats based on criteria (age, size, etc.)

#### UI Components
- Delete/flag delete interface
- Restore deleted chats interface
- Archive management interface
- Prune settings/interface
- Deleted chats view/filter

### Deletion Workflow
1. User flags chat for deletion (soft delete)
2. Chat moves to "deleted" state (still recoverable)
3. User can restore deleted chat
4. After some time or user action, chat can be archived
5. Archived chats can be permanently deleted
6. Or archived chats can be restored

### Features Details
- **Flag Delete**: Mark chat as deleted but keep data
- **Restore**: Move deleted chat back to active
- **Archive**: Move deleted chat to archive (separate storage)
- **Permanent Delete**: Actually remove archived chat data
- **Prune**: Automatic cleanup based on rules (age, count, size)

### Files to Create/Modify
- `libollmchat/History/Manager.vala` - Deletion/restore/archive logic
- `libollmchat/History/Session.vala` - Deletion state management
- `libollmchatgtk/HistoryBrowser.vala` - Delete/restore UI
- Archive storage system
- Prune rules system

### Implementation Notes
- Design deletion state model (active, deleted, archived)
- Implement soft delete (flag, don't remove)
- Create archive storage location
- Design restore workflow
- Implement prune rules (age, count, size)
- Add UI for all operations
- Ensure data safety (backup before permanent delete)
- Add confirmation dialogs for permanent operations
