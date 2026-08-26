# 4.2.1. Tree Navigation in FileDropdown

## Overview

Add tabbed interface to FileDropdown widget to provide tree navigation mode alongside the existing search mode.

## Status

⏳ **TODO** - Not yet implemented.

## Features

- Tabbed interface in FileDropdown popup with two navigation modes:
  - **Tab 1: Search Mode** (existing implementation) - Search through ProjectFiles flat list
  - **Tab 2: Tree Navigation Mode** (new) - Hierarchical tree view of folder structure

## Implementation Plan

### Component: Tabbed FileDropdown
- **Purpose**: Provide two navigation modes for file selection
- **Location**: Extends existing FileDropdown widget (`liboccoder/FileDropdown.vala`)

### Tab 1: Search Mode (Current Implementation)
- **Description**: Search through ProjectFiles (flat list)
- **Functionality**: 
  - Current searchable dropdown implementation
  - Filters files by name/path
  - Shows all files in project as flat list
  - Sorted by open status, then by path
- **Status**: ✅ Already implemented, no changes needed

### Tab 2: Tree Navigation Mode
- **Description**: Tree view of Folder.children hierarchy
- **Data Source**: `project.children` (FolderFiles ListModel)
- **Functionality**:
  - Hierarchical tree view showing folder structure
  - All folders expanded by default
  - Click folders to expand/collapse
  - Click files to select
  - Visual tree structure with indentation
- **Implementation**:
  - Use `Gtk.TreeView` or `Gtk.ColumnView` with tree model
  - Bind to `project.children` (FolderFiles) which maintains Folder.children hierarchy
  - Use `Gtk.TreeListModel` to create tree structure from FolderFiles
  - Each Folder maintains its children via Folder.children (FolderFiles ListModel)

### UI Design
- **Tab Switcher**: Add `Gtk.Notebook` or `Gtk.StackSwitcher` to FileDropdown popup
- **Tab 1 Label**: "Search" or "List"
- **Tab 2 Label**: "Tree" or "Folders"
- **Default Tab**: Tab 1 (Search mode) for backward compatibility

### Files to Modify
- `liboccoder/FileDropdown.vala` - Add tabbed interface with tree view tab

## Technical Details

### Tree Model Structure
- **Root**: Active project (Folder with `is_project = true`)
- **Children**: `project.children` (FolderFiles ListModel)
- **Recursive Structure**: Each Folder in the tree has its own `children` (FolderFiles) for subdirectories
- **Tree Model**: Use `Gtk.TreeListModel` to convert FolderFiles hierarchy into tree structure

### Tree View Widget
- **Widget Type**: `Gtk.ColumnView` (GTK4 recommended) or `Gtk.TreeView` (GTK3 compatibility)
- **Columns**: 
  - Icon (file/folder icon)
  - Name (basename)
  - Path (optional, for tooltip or secondary display)
- **Expansion**: All folders expanded by default
- **Selection**: Single selection mode, emits file selection signal when file clicked

### Integration with Existing FileDropdown
- **Search Tab**: Keep existing search functionality unchanged
- **Tree Tab**: New tree view widget alongside search
- **File Selection**: Both tabs should emit the same `file_selected` signal
- **Active File Highlighting**: Both tabs should highlight the currently active file

## Dependencies

- GTK4 widgets (`Gtk.Notebook`, `Gtk.Stack`, `Gtk.ColumnView` or `Gtk.TreeView`)
- `Gtk.TreeListModel` for tree structure conversion
- Existing FolderFiles ListModel from `liboccoder`

## Related Plans

- Part of 4.2 Code Editor Interface (now 4.2-DONE)
- Depends on Phase 2C: Searchable Dropdown Widgets (✅ DONE)
- Uses Folder.children hierarchy from Phase 2A: Data Layer (✅ DONE)
