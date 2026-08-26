# 2.6.2. Bwrap UX Fixes: Pulldown Sizing and Open-First-File

## Overview

This plan addresses UX issues in the bwrap/run-command and edit-file flow:

1. **Pulldown too small** – The Approvals "next" button popover (and any related dropdowns in the code editor when bwrap changes are applied) is too small to use; it needs minimum width and minimum height.
2. **Open first modified/added file** – When edit_file or run_command complete and focus is **not** on the source view, the app should open the first file that was **modified** or **added** (never open deleted files).

## Status

⏳ **PLANNING** – Design phase.

## Problem

1. **Approvals popover too small**  
   When RunCommand (with bwrap) modifies or adds files, they appear in ReviewFiles and the Approvals bar is shown. The "next" button’s popover lists those files. The popover can be too small (narrow or short) to use comfortably, especially with long paths or several items.

2. **No automatic open after edit/run**  
   When the user is in the chat and the agent runs edit_file or run_command, changed files are not opened. The user has to find and open them manually. When the user is already in the source view, we should **not** switch files (they may be looking at something else). Deleted files must never be auto-opened.

## Goals

1. **Pulldown min width and min height**
   - Apply minimum width and minimum height to the Approvals "next" button popover so it stays usable.
   - Optionally apply similar constraints to SearchableDropdown-based popups (FileDropdown, ProjectDropdown) in the SourceView header if they are too small in the same context.

2. **Open first modified/added when focus not on source view**
   - After **edit_file** completes: if the file was modified or added, and focus is not on the source view, open that file.
   - After **run_command** (bwrap path) completes: after `Scan.run()`, if there is at least one modified or added file, and focus is not on the source view, open the **first** such file (do not open deleted files).
   - Never open deleted files.

---

## 1. Approvals Popover: Min Width and Min Height

### Context

- **Widget:** `liboccoder/Approvals.vala` – the "next" button uses a `Gtk.Popover` with a `Gtk.ScrolledWindow` and `Gtk.ListView` for files needing approval.
- **Sizing:** `update_popover_size()` sets the popover **content** height only:  
  `calculated_height = (int)(n_items * 30)` with `min 100`, `max 400`.  
  There is no minimum width and the minimum height (100px) may still be too small to use.

### Implementation

1. **Min width**
   - In `update_popover_size()` (or when building the popover), set a minimum width on the popover’s child (the `Gtk.ScrolledWindow`), e.g. `set_size_request(280, -1)` or use `width_request` / `min-width` so the list remains readable (long paths, `display-approval-text`).
   - Ensure the popover itself is not given a smaller width (e.g. via `Gtk.Popover` or its child).

2. **Min height**
   - Increase the effective minimum height from 100px to something more comfortable (e.g. 180–200px), or use a `min_content_height` on the `Gtk.ScrolledWindow` that is at least ~180px when there are items.
   - Keep the existing per-item logic and max (400px) so it doesn’t grow excessively.

3. **Where to apply**
   - Apply to the `ScrolledWindow` (or the box that wraps it) used as `popover.child` in `Approvals`.
   - If the popover is constrained by `Gtk.Popover` layout, ensure the child’s minimum size is respected (e.g. via `set_size_request(min_width, min_height)` or `set_min_content_size` / `min_content_height` where available).

### Files to Modify

- `liboccoder/Approvals.vala`
  - In `update_popover_size()` (and/or in popover setup): set a minimum width (e.g. 280px) and a higher minimum height (e.g. 180px) on the popover content.
  - If the popover is shown before `update_popover_size()` runs, ensure initial min width/height in the popover’s child so it is never too small on first open.

### Optional: SearchableDropdown / FileDropdown / ProjectDropdown

- `liboccoder/SearchableDropdown.vala` uses `popup.set_size_request(width * 2, -1)`. If the entry is narrow, the popup can be too small. If the same “too small” behavior appears in the code editor (e.g. when used with bwrap results), add:
  - A minimum width (e.g. 220–260px) so `width * 2` is not below that.
  - A minimum height on the popup or its scrolled content (e.g. 120–160px) when there are items.
- `liboccoder/FileDropdown.vala` and `liboccoder/ProjectDropdown.vala` inherit from `SearchableDropdown`; changes in the base popup sizing apply to them.
- `ollmapp/SettingsDialog/SearchablePulldown.vala` has similar `set_size_request(width * 2, -1)`; only adjust if the same issue appears in settings/dialogs.

---

## 2. Open First Modified or Added File When Focus Not on Source View

### Behavior

- **Edit_file:** One file; it is either “modified” or “added”. After a successful edit, if focus is **not** inside the source view, call `open_file` for that file. Never for “deleted” (edit_file does not produce “deleted” in the same sense; it’s only modified or added).
- **Run_command (bwrap):** After `overlay.scan.run()` finishes, we have a set of files that were modified, added, or deleted. Take the **first** file that is modified or added (in the order produced by the scan). If focus is not inside the source view, open that file. **Do not** open deleted files.
- **Run_command (subprocess, no bwrap):** No overlay/Scan; we do not have a structured list of changed files. **No** automatic open.

### 2.1. ProjectManager: `open_file_requested` Signal

We need a single, tool-agnostic way for EditMode and RunCommand to ask for a file to be opened. ProjectManager is already available to both.

1. **Add signal and helper**

   - In `libocfiles/ProjectManager.vala`:
     - `public signal void open_file_requested(OLLMfiles.File file)`
     - `public void request_open_file(OLLMfiles.File file) { open_file_requested(file); }`

2. **Semantics**

   - Emitting `request_open_file(file)` means: “please open this file in the code editor **if** the app decides it’s appropriate (e.g. focus not already in the source view).” The actual “focus check” and `open_file` call live in the UI layer (AgentFactory/SourceView).

### 2.2. SourceView: `is_focus_inside`

The “open only when focus is not on the source view” logic needs a clear predicate.

1. **Add method**

   - In `liboccoder/SourceView.vala`:
     - `public bool is_focus_inside()`
     - Implement by obtaining the toplevel `Gtk.Window`, then `window.get_focus()` (or equivalent), and checking whether that widget is `this` or a descendant of `this` (e.g. `widget.is_ancestor()` or walking the ancestor chain). Return `true` if focus is inside the SourceView, `false` otherwise (no toplevel, no focus, or focus outside).

### 2.3. AgentFactory: Connect `open_file_requested` and Decide Whether to Open

Only the code-assistant AgentFactory has a SourceView. It should react to `open_file_requested` and only open when focus is not already in the source view.

1. **Connect to `project_manager.open_file_requested`**
   - In `liboccoder/AgentFactory.vala`, when the SourceView is created (inside `get_widget()`), connect to `project_manager.open_file_requested` **once** (use a flag or id to avoid duplicate connections if `get_widget()` is called multiple times).

2. **Handler logic**
   - On `open_file_requested(File file)`:
     - If `this.widget == null`, return.
     - If `this.widget.is_focus_inside()` is `true`, return (do not open).
     - Otherwise call `this.widget.open_file.begin(file, null)`.

### 2.4. EditMode Request: Call `request_open_file` After Success

1. **Where**
   - In `liboctools/EditMode/Request.vala`, at the end of `execute()` (or the async path that applies edits and marks the file as modified/added), after we know the change was applied and we have the `OLLMfiles.File` and `change_type`.

2. **Condition**
   - Only when `change_type` is `"modified"` or `"added"`. (Edit_file does not produce “deleted” in this sense.)

3. **Action**
   - Get `project_manager` from `(Tool) this.tool` (or equivalent) and call `project_manager.request_open_file(file)`.

### 2.5. RunCommand Scan: Collect First Modified/Added and Call `request_open_file`

1. **Collect modified/added in Scan**
   - In `liboctools/RunCommand/Scan.vala`:
     - Add a `Gee.ArrayList<OLLMfiles.File> modified_or_added` (or similar) to collect files that are **modified** or **added** (not deleted).
     - In `handle_file()`, when `change_type` is `"modified"` or `"added"`, append the `OLLMfiles.File` to `modified_or_added`. Do **not** add for `"deleted"` or for folders-only in `handle_folder` (we only open files).
     - Order: use the order in which `handle_file` is called (same as current scan order).

2. **After `run()` finishes**
   - At the end of `Scan.run()`, after the cleanup and `review_files.refresh()`:
     - If `modified_or_added.size > 0`, take the first element.
     - Get `project_manager` from `project_folder.manager` and call `project_manager.request_open_file(first_file)`.
   - `Bubble.exec()` and `Request.execute()` need no changes; the Scan already runs in the bwrap path and has access to `project_folder` and thus `project_manager`.

### Files to Modify

- `libocfiles/ProjectManager.vala`
  - Add `public signal void open_file_requested(OLLMfiles.File file)` and `public void request_open_file(OLLMfiles.File file)`.
- `liboccoder/SourceView.vala`
  - Add `public bool is_focus_inside()`.
- `liboccoder/AgentFactory.vala`
  - In `get_widget()`, when creating the SourceView, connect to `project_manager.open_file_requested` and implement the handler (open only if `!widget.is_focus_inside()`).
- `liboctools/EditMode/Request.vala`
  - At the end of the successful edit path, if `change_type` is `"modified"` or `"added"`, call `project_manager.request_open_file(file)`.
- `liboctools/RunCommand/Scan.vala`
  - Add `modified_or_added` list; in `handle_file()` push for modified/added only; at end of `run()` call `project_folder.manager.request_open_file(first)` if the list is non‑empty.

---

## 3. Implementation Phases

### Phase 1: Approvals Popover Min Width and Min Height

- [ ] In `Approvals.update_popover_size()` (and/or popover setup), set a minimum width (e.g. 280px) on the popover child.
- [ ] Set a higher minimum height (e.g. 180px) for the list area when there are items, while keeping the existing per‑item and max (400px) behavior.
- [ ] Ensure the popover is usable on first open (initial min size before `update_popover_size` runs, if needed).
- [ ] Manually test: RunCommand with bwrap that modifies/adds files → Approvals bar → next popover is comfortably sized.

### Phase 2: ProjectManager `open_file_requested` and Helpers

- [ ] Add `open_file_requested` signal and `request_open_file()` to `ProjectManager`.
- [ ] Add `is_focus_inside()` to `SourceView`.
- [ ] In `AgentFactory.get_widget()`, connect to `project_manager.open_file_requested` and open only when `!widget.is_focus_inside()`.

### Phase 3: EditMode – Request Open After Success

- [ ] In `EditMode/Request.vala`, after a successful apply, if `change_type` is `"modified"` or `"added"`, call `project_manager.request_open_file(file)`.
- [ ] Test: focus in chat → edit_file (modify or add) → that file opens in the code assistant.
- [ ] Test: focus in source view → edit_file → current file does not change.

### Phase 4: RunCommand Scan – First Modified/Added and Request Open

- [ ] In `Scan.vala`, add `modified_or_added` and in `handle_file()` append only for `"modified"` and `"added"`.
- [ ] At end of `Scan.run()`, if `modified_or_added.size > 0`, call `project_folder.manager.request_open_file(modified_or_added[0])`.
- [ ] Test: focus in chat → run_command with bwrap that modifies/adds files → first modified/added file opens.
- [ ] Test: run_command that only deletes files → no file opened.
- [ ] Test: focus in source view → run_command with bwrap that modifies/adds → no automatic open.

### Phase 5 (Optional): SearchableDropdown / Pulldown Min Sizing

- [ ] If the FileDropdown/ProjectDropdown popups in the code editor are too small, add min width and min height in `SearchableDropdown` (and optionally `SearchablePulldown`) similar to Approvals.
- [ ] Re-test in the bwrap + code assistant scenario.

---

## 4. Files to Create or Modify

### Phase 1

- `liboccoder/Approvals.vala` – min width and min height for the “next” button popover content.

### Phase 2–4

- `libocfiles/ProjectManager.vala` – `open_file_requested` signal and `request_open_file()`.
- `liboccoder/SourceView.vala` – `is_focus_inside()`.
- `liboccoder/AgentFactory.vala` – connect `open_file_requested` and open only when `!is_focus_inside()`.
- `liboctools/EditMode/Request.vala` – `request_open_file(file)` after successful modified/added edit.
- `liboctools/RunCommand/Scan.vala` – `modified_or_added` list, and `request_open_file(first)` at end of `run()`.

### Phase 5 (Optional)

- `liboccoder/SearchableDropdown.vala` – min width/height for popup.
- `ollmapp/SettingsDialog/SearchablePulldown.vala` – only if the same UX issue appears there.

---

## 5. Dependencies

- Existing RunCommand bwrap + Overlay + Scan flow.
- Existing EditMode `execute()` and `change_type` (`"modified"` / `"added"`).
- `ProjectManager` and `AgentFactory` as used by the code-assistant and tools.

---

## 6. Testing

### Approvals popover

- [ ] RunCommand with bwrap that modifies/adds several files.
- [ ] Open Approvals “next” popover: width and height are at least the new minima; list is readable and scrollable.
- [ ] One file, many files, long paths: popover remains usable.

### Open first modified/added

**Edit_file**

- [ ] Focus in chat: edit_file (modify) → that file opens in the code assistant.
- [ ] Focus in chat: edit_file (add) → that file opens.
- [ ] Focus in source view: edit_file (modify or add) → no automatic switch.

**Run_command (bwrap)**

- [ ] Focus in chat: run_command with bwrap that modifies one file → that file opens.
- [ ] Focus in chat: run_command with bwrap that adds one file → that file opens.
- [ ] Focus in chat: run_command with bwrap that modifies/adds several files → **first** modified/added opens.
- [ ] Focus in chat: run_command with bwrap that only deletes files → no file opened.
- [ ] Focus in source view: run_command with bwrap that modifies/adds → no automatic open.

**Run_command (subprocess, no bwrap)**

- [ ] run_command without bwrap (e.g. Flatpak or no bwrap): no automatic open (no Scan, no list of changed files).

---

## 7. Open Points

- Exact min width (e.g. 280px) and min height (e.g. 180px) for the Approvals popover: to be confirmed with UI or user feedback.
- Whether to apply min sizing to SearchableDropdown/FileDropdown/ProjectDropdown in this plan or a follow-up.
- “First” file in RunCommand: currently “first” means first in Scan’s `handle_file` order. If a different order (e.g. by path or by “added” before “modified”) is preferred, Scan can be adjusted.

---

## 8. Summary

- **Pulldown:** Approvals “next” popover gets minimum width and minimum height so it stays usable when bwrap/run_command adds files to ReviewFiles.
- **Open first modified/added:**  
  - `ProjectManager.request_open_file(File)` and `open_file_requested` allow EditMode and RunCommand to request opening a file.  
  - `SourceView.is_focus_inside()` and an AgentFactory handler ensure we only open when focus is **not** already in the source view.  
  - EditMode: after a successful modified/added edit, call `request_open_file(file)`.  
  - RunCommand (bwrap): Scan collects modified/added files and, at the end of `run()`, calls `request_open_file(first)`; deleted files are never opened.  
  - RunCommand (subprocess): no automatic open.
