# BWRAP-2.6.2: Open first changed file after bwrap run

**Source:** Remaining scope from [`done/TOOLS-2.6.2-SUPERSEDED-bwrap-ux-fixes.md`](done/TOOLS-2.6.2-SUPERSEDED-bwrap-ux-fixes.md) (moved from TOOLS → BWRAP).

**Parent:** [`done/2.6-DONE-run-terminal-command-tool.md`](done/2.6-DONE-run-terminal-command-tool.md)

## Status

⏳ **TODO** — not started.

## Purpose

After **edit_file** or **run_command** (bwrap path) changes files, open the first **modified** or **added** file in the code assistant when the user is **not** already focused in the source view. Never auto-open deleted files. Subprocess run_command (no bwrap / no Scan) does nothing.

**Already shipped (out of scope here):**

- Approvals “next” popover min width (400px in `Approvals.update_popover_size()`).
- File **reload** when already open after LLM write — [`docs/bugs/2026-08-15-open-file-not-reloaded-after-llm-write.md`](../bugs/2026-08-15-open-file-not-reloaded-after-llm-write.md).

**Deferred / separate:**

- Approvals popover min **height** bump (100px → ~180px) — minor; do only if still cramped after width fix.
- SearchableDropdown / Android popover sizing — [`docs/bugs/2026-09-02-android-add-model-search-popover-layout.md`](../bugs/2026-09-02-android-add-model-search-popover-layout.md).

---

## Phase 1: `open_file_requested` plumbing

### `libocfiles/ProjectManager.vala`

- Add `public signal void open_file_requested(OLLMfiles.File file)`.
- Add `public void request_open_file(OLLMfiles.File file) { this.open_file_requested(file); }`.
- Semantics: “open in code editor **if** the UI decides it is appropriate” (focus check lives in AgentFactory).

### `liboccoder/SourceView.vala`

- Add `public bool is_focus_inside()`.
- Toplevel `Gtk.Window` → `get_focus()` → return true when focus is `this` or a descendant.

### `liboccoder/AgentFactory.vala`

- In `get_widget()`, connect once to `project_manager.open_file_requested`.
- Handler: if `this.widget == null` or `this.widget.is_focus_inside()` → return; else `this.widget.open_file.begin(file, null)`.

---

## Phase 2: EditMode

### `liboctools/EditMode/Request.vala`

- After successful apply, when `change_type` is `"modified"` or `"added"`, call `project_manager.request_open_file(file)`.

---

## Phase 3: RunCommand Scan (bwrap only)

### `liboctools/RunCommand/Scan.vala`

- Add `Gee.ArrayList<OLLMfiles.File> modified_or_added`.
- In `handle_file()`, append only for `"modified"` and `"added"` (not `"deleted"`).
- At end of `run()`, after cleanup and `review_files.refresh()`: if list non-empty, `project_folder.manager.request_open_file(modified_or_added[0])`.
- “First” = first in `handle_file` call order.

---

## Testing

**edit_file**

- [ ] Focus in chat → modify or add → that file opens.
- [ ] Focus in source view → modify or add → no switch.

**run_command (bwrap)**

- [ ] Focus in chat → one modified/added → that file opens.
- [ ] Focus in chat → several modified/added → **first** opens.
- [ ] Only deletes → nothing opens.
- [ ] Focus in source view → modifies/adds → no auto-open.

**run_command (subprocess, no bwrap)**

- [ ] No automatic open.

---

## Open points

- Prefer a different “first file” order (path, added-before-modified)? Adjust Scan collection only.
- Bump Approvals min height in same pass if popover still feels short.
