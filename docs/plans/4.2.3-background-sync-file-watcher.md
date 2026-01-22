# 4.2.3. Background Sync and File Watcher

## Overview

Implement background sync process and file system watcher to keep database and in-memory objects synchronized with filesystem changes in real-time.

## Status

⏳ **TODO** - Not yet implemented.

## Features

- **Background Sync Process**: Periodic background process to update database
- **File System Watcher**: Monitor file system for real-time updates
- **Automatic Updates**: Update ProjectFiles when files are added/removed/modified
- **UI Synchronization**: Emit signals when changes detected for UI refresh

## Implementation Plan

### Component: Background Sync and File Watcher
- **Purpose**: Keep database and in-memory objects synchronized with filesystem changes
- **Location**: `liboccoder/ProjectManager.vala` and new watcher component

### Background Sync Process
- **Functionality**:
  - Periodic background process to update database
  - Sync objects to database (via libocsqlite)
  - Sync to UI if necessary (when UI is active)
  - Handle file system changes detected by watcher
- **Implementation**:
  - Use `GLib.Timeout` or `GLib.Idle` for periodic sync
  - Process queued file system events from watcher
  - Update ProjectFiles when files are added/removed/modified

### File System Watcher
- **Functionality**:
  - Monitor file system for real-time updates
  - Detect file changes (create, modify, delete, move)
  - Detect directory changes (create, delete, move)
  - Queue events for background sync process
- **Implementation**:
  - Use `Gio.FileMonitor` for file system monitoring
  - Monitor project root directories
  - Handle symlink/alias changes
  - Integrate with Folder.read_dir() for directory scanning

### Integration Points
- **ProjectManager**: Coordinate watcher and sync process
- **Folder.read_dir()**: Triggered by watcher events or periodic sync
- **ProjectFiles**: Updated when files are added/removed/modified
- **UI Updates**: Emit signals when changes detected (for UI refresh)

### Files to Create/Modify
- `liboccoder/ProjectManager.vala` - Add background sync and watcher management
- `liboccoder/files/Folder.vala` - Integrate with watcher events (optional)

## Technical Details

### File System Watcher Implementation

#### Gio.FileMonitor Usage
- Create `Gio.FileMonitor` for each project root directory
- Monitor types:
  - `Gio.FileMonitorFlags.WATCH_MOVES` - Track file/directory moves
  - `Gio.FileMonitorFlags.SEND_MOVED` - Send moved events
- Event types to handle:
  - `Gio.FileMonitorEvent.CREATED` - New file/directory created
  - `Gio.FileMonitorEvent.DELETED` - File/directory deleted
  - `Gio.FileMonitorEvent.CHANGED` - File content modified
  - `Gio.FileMonitorEvent.MOVED` - File/directory moved/renamed
  - `Gio.FileMonitorEvent.ATTRIBUTE_CHANGED` - File attributes changed

#### Event Queue
- Queue file system events for processing
- Process events in background sync process
- Batch similar events to reduce database writes
- Handle rapid file changes (e.g., during build processes)

### Background Sync Process

#### Periodic Sync
- Use `GLib.Timeout.add_seconds()` for periodic sync (e.g., every 30 seconds)
- Process queued file system events
- Update database with changes
- Emit signals for UI updates

#### Sync Strategy
- **Incremental Updates**: Only sync changed files/directories
- **Batch Operations**: Group multiple changes together
- **Conflict Resolution**: Handle conflicts when file changed both in editor and on disk
- **Performance**: Avoid blocking UI thread, use async operations

### Integration with Existing Components

#### ProjectManager Integration
- Add watcher management methods:
  - `start_watching()` - Start file system watchers for all projects
  - `stop_watching()` - Stop all file system watchers
  - `watch_project(Folder project)` - Start watcher for specific project
  - `unwatch_project(Folder project)` - Stop watcher for specific project
- Add sync process management:
  - `start_sync_process()` - Start background sync process
  - `stop_sync_process()` - Stop background sync process

#### Folder Integration
- `Folder.read_dir()` may be triggered by watcher events
- Handle directory structure changes
- Update Folder.children when files added/removed

#### ProjectFiles Integration
- Update ProjectFiles when files added/removed/modified
- Maintain flat list consistency with filesystem
- Handle file moves/renames

### Signals and Events

#### New Signals
- `file_changed(File file)` - Emitted when file content changes on disk
- `file_created(File file)` - Emitted when new file created
- `file_deleted(File file)` - Emitted when file deleted
- `file_moved(File old_file, File new_file)` - Emitted when file moved/renamed
- `directory_changed(Folder folder)` - Emitted when directory structure changes

#### UI Integration
- SourceView can listen to these signals to refresh file content
- FileDropdown can listen to update file list
- ProjectDropdown can listen to update project list

### Performance Considerations

#### Watcher Performance
- Limit number of watchers (one per project root, not per directory)
- Use recursive monitoring where supported
- Handle large directory trees efficiently

#### Sync Performance
- Debounce rapid file changes
- Batch database writes
- Use async operations to avoid blocking

#### Memory Management
- Clean up watchers when projects removed
- Limit event queue size
- Release resources when not needed

## Related Plans

- Part of 4.2 Code Editor Interface (now 4.2-DONE)
- Depends on Phase 2A: Data Layer (✅ DONE)
- Depends on Phase 2B: Database Schema and Sync (✅ DONE)
- Enhances Phase 3: Source View Component (✅ DONE) with real-time updates
