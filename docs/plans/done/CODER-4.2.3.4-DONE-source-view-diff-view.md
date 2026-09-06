# 4.2.3.4 — SourceView diff Phase 3: view pending file

**Status:** **✔️** **done** — `backup_path` on pending rows; `show_pending_diff` + open / refresh / invalidate wiring

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3-URGENT-source-view-diff.md`](../CODER-4.2.3-URGENT-source-view-diff.md)

**Depends on:** [`CODER-4.2.3.2-DONE-source-view-diff-db.md`](CODER-4.2.3.2-DONE-source-view-diff-db.md) · [`CODER-4.2.3.3-DONE-source-view-diff-render.md`](CODER-4.2.3.3-DONE-source-view-diff-render.md)

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans; proposed Vala follows **`docs/coding-standards.md`**

**Next:** Phase 4 [`CODER-4.2.3.5`](../CODER-4.2.3.5-source-view-diff-approval.md)

---

## Purpose

- 🔷 When user **opens** a pending-approval file, build **`new Differ(V_backup, V_disk)`** and call **`SourceView.show_diff(differ)`**.
- 🔷 **V_backup** = contents of **`file_history.backup_path`** for the newest pending chunk (`reviewed=0`).
- 🔷 **V_disk** = loaded **`file.buffer`** text (agent end result).
- 🔷 Pending = path in **`review_files.file_map`** (not stale `File.is_need_approval`).
- 🔷 Wire **`backup_path`** on **`FileWithHistory`** (daemon SQL + client + refresh upsert).
- 🔷 Read backup via **`RPC-File.read`** (daemon) — **not** local `GLib.FileUtils` / `GLib.File` in SourceView.
- 🔷 Empty **`backup_path`** → `""` (all-green for **added**).
- 🔷 Named method **`show_pending_diff(File file)`** — async; RPC backup + `show_diff` (shared by open / refresh / invalidate).
- 🔷 **`navigate_to_line`** / cursor restore while diff-active map **V_disk** (0-based file line) → unified **display** line via compact **remove offsets** (not a per-row array).
- 🔷 **`clear_diff`** when opening a non-pending file, when approve/reject drops the path from `ReviewFiles`, or before buffer swap while diff is active.
- 🔷 Rebuild on **`review_files.refreshed`** while the open file is still pending (stacked write → new backup).
- 🔷 Approvals bar already opens the file via **`file_selected` → `open_file`** — no Approvals UI change.
- 🔷 No per-hunk controls (Phase **4**).

---

## How it works

1. Daemon pending SELECT adds **`backup_path`** from newest `reviewed=0` `file_history` row.
2. Client `ReviewFiles.refresh` keeps that field on upsert.
3. `SourceView.open_file` — leave any prior diff, load buffer, then **`yield show_pending_diff(file)`**.
4. `review_files.refreshed` — if current path gone → `clear_diff`; if still pending → **`show_pending_diff.begin`**.

ℹ️ **Trigger is `open_file`**, not window-focus. Approvals and file dropdown both end in `open_file`.

ℹ️ Thin client contract: content from daemon (`RPC-File.read`). Editor **`GtkSourceFileBuffer.read_async`** still loads the **open project file** locally — that hybrid stays; Phase 3 must **not** extend SourceView to open daemon backup paths on disk.

---

## Named methods (approved)

- 🔷 **`SourceView.show_pending_diff(OLLMfiles.File file)`** — `async`; if `file.path` ∈ `review_files.file_map`, empty `backup_path` → `show_diff(Differ("", V_disk))` and return; else `RPC-File.read` then `show_diff`. No-op when not pending. **Early return** after `yield` if `current_file != file`.
- 🔷 Field **`diff_remove_at`** / **`diff_remove_n`** — one entry per removed hunk: **1-based V_disk** line at which those removals appear in the unified stream (`patch.new_line_start`), and how many removed rows. **`display = disk_0based + sum(n where at <= disk_1based)`**. Filled in **`show_diff`**, cleared in **`clear_diff`**.
- 🔷 **`navigate_to_line`** — when **`diff_active`**, apply that offset; do **not** store every display row’s disk line.

---

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `ollmfilesd/FileWithHistory.vala` — wire `backup_path`

**Where:** properties (~32–47) and pending SELECT (~75–107).

#### Add (property, after `reviewed`)

```vala
		/**
		 * Backup snapshot path for the newest pending chunk ({@code reviewed=0}).
		 * Empty when the pending write has no backup (e.g. added).
		 */
		public string backup_path { get; set; default = ""; }
```

#### Remove (SELECT columns through `reject_id` subquery)

```vala
SELECT
	file_history.filebase_id AS id,
	file_history.path,
	file_history.change_type AS last_change_type,
	filebase.last_modified,
	file_history.reviewed,
	(
		SELECT
			file_history.id
		FROM
			file_history
		WHERE
				file_history.filebase_id = filebase.id
			AND
				file_history.reviewed = 0
		ORDER BY
			file_history.timestamp DESC
		LIMIT 1
	) AS approve_id,
	(
		SELECT
			file_history.id
		FROM
			file_history
		WHERE
				file_history.filebase_id = filebase.id
			AND
				file_history.backup_path != ''
		ORDER BY
			file_history.timestamp DESC
		LIMIT 1
	) AS reject_id
```

#### Replace with

```vala
SELECT
	file_history.filebase_id AS id,
	file_history.path,
	file_history.change_type AS last_change_type,
	filebase.last_modified,
	file_history.reviewed,
	(
		SELECT
			file_history.id
		FROM
			file_history
		WHERE
				file_history.filebase_id = filebase.id
			AND
				file_history.reviewed = 0
		ORDER BY
			file_history.timestamp DESC
		LIMIT 1
	) AS approve_id,
	(
		SELECT
			file_history.id
		FROM
			file_history
		WHERE
				file_history.filebase_id = filebase.id
			AND
				file_history.backup_path != ''
		ORDER BY
			file_history.timestamp DESC
		LIMIT 1
	) AS reject_id,
	(
		SELECT
			file_history.backup_path
		FROM
			file_history
		WHERE
				file_history.filebase_id = filebase.id
			AND
				file_history.reviewed = 0
		ORDER BY
			file_history.timestamp DESC
		LIMIT 1
	) AS backup_path
```

---

### 2. `libocfiles/FileWithHistory.vala` — client property

**Where:** after `reviewed` (~43).

#### Add

```vala
		/**
		 * Backup snapshot path for the newest pending chunk ({@code reviewed=0}).
		 * Empty when the pending write has no backup (e.g. added).
		 */
		public string backup_path { get; set; default = ""; }
```

---

### 3. `libocfiles/ReviewFiles.vala` — upsert copies `backup_path`

**Where:** refresh upsert branch (~140–147).

#### Remove

```vala
					if (this.file_map.has_key(file.path)) {
						var existing = this.file_map.get(file.path);
						existing.last_change_type = file.last_change_type;
						existing.last_modified = file.last_modified;
						existing.approve_id = file.approve_id;
						existing.reject_id = file.reject_id;
						existing.reviewed = 0;
						continue;
					}
```

#### Replace with

```vala
					if (this.file_map.has_key(file.path)) {
						var existing = this.file_map.get(file.path);
						existing.last_change_type = file.last_change_type;
						existing.last_modified = file.last_modified;
						existing.approve_id = file.approve_id;
						existing.reject_id = file.reject_id;
						existing.backup_path = file.backup_path;
						existing.reviewed = 0;
						continue;
					}
```

---

### 4. `liboccoder/SourceView.vala` — remove offsets + `show_diff` / `clear_diff` / `navigate_to_line`

**Where:** fields (~51); `show_diff` removed-hunk arm; `clear_diff`; `navigate_to_line` (~693); `restore_cursor_position` (~818).

ℹ️ Unified display inserts **removed** rows before the following **V_disk** lines. So
`display_line = disk_0based + sum(removed counts whose at <= disk_1based)`.
Only store one pair per removed hunk — not every row.

#### Add (fields, next to `diff_baseline`)

```vala
		private Gee.ArrayList<int> diff_remove_at { get; set; default = new Gee.ArrayList<int>(); }
		private Gee.ArrayList<int> diff_remove_n { get; set; default = new Gee.ArrayList<int>(); }
```

#### Remove (`show_diff` clear + removed arm)

```vala
			this.diff_baseline.clear();
			var old_i = 1, new_i = 1;
			foreach (var patch in differ.patches) {
				while (old_i < patch.old_line_start && new_i < patch.new_line_start
					&& old_i <= differ.lines1.length && new_i <= differ.lines2.length) {
					display.add(differ.lines2[new_i - 1]);
					this.diff_baseline.add(old_i);
					kinds.add(0);
					old_i++;
					new_i++;
				}
				if (patch.old_line_start > patch.old_line_end) {
					old_i = patch.old_line_start;
				} else {
					for (var ln = patch.old_line_start; ln <= patch.old_line_end; ln++) {
						display.add(differ.lines1[ln - 1]);
						this.diff_baseline.add(ln);
						kinds.add(2);
					}
					old_i = patch.old_line_end + 1;
				}
```

#### Replace with

```vala
			this.diff_baseline.clear();
			this.diff_remove_at.clear();
			this.diff_remove_n.clear();
			var old_i = 1, new_i = 1;
			foreach (var patch in differ.patches) {
				while (old_i < patch.old_line_start && new_i < patch.new_line_start
					&& old_i <= differ.lines1.length && new_i <= differ.lines2.length) {
					display.add(differ.lines2[new_i - 1]);
					this.diff_baseline.add(old_i);
					kinds.add(0);
					old_i++;
					new_i++;
				}
				if (patch.old_line_start > patch.old_line_end) {
					old_i = patch.old_line_start;
				} else {
					for (var ln = patch.old_line_start; ln <= patch.old_line_end; ln++) {
						display.add(differ.lines1[ln - 1]);
						this.diff_baseline.add(ln);
						kinds.add(2);
					}
					this.diff_remove_at.add(patch.new_line_start);
					this.diff_remove_n.add(patch.old_line_end - patch.old_line_start + 1);
					old_i = patch.old_line_end + 1;
				}
```

#### Remove (`clear_diff` baseline clear)

```vala
			this.diff_buffer = null;
			this.pre_diff_buffer = null;
			this.diff_baseline.clear();
			this.source_view.show_line_numbers = true;
```

#### Replace with

```vala
			this.diff_buffer = null;
			this.pre_diff_buffer = null;
			this.diff_baseline.clear();
			this.diff_remove_at.clear();
			this.diff_remove_n.clear();
			this.source_view.show_line_numbers = true;
```

#### Remove (`navigate_to_line`)

```vala
		public void navigate_to_line(int line_number)
		{
			var buffer = this.source_view.buffer;
			
			Gtk.TextIter iter;
			if (!buffer.get_iter_at_line(out iter, line_number)) {
				return;
			}
			buffer.place_cursor(iter);
			this.source_view.scroll_to_iter(iter, 0.0, false, 0.0, 0.5);
		}
```

#### Replace with

```vala
		public void navigate_to_line(int line_number)
		{
			var buffer = this.source_view.buffer;
			var display_line = line_number;
			if (this.diff_active) {
				var extras = 0;
				var disk = line_number + 1;
				for (var i = 0; i < this.diff_remove_at.size; i++) {
					if (this.diff_remove_at.get(i) > disk) {
						break;
					}
					extras += this.diff_remove_n.get(i);
				}
				display_line = line_number + extras;
			}
			Gtk.TextIter iter;
			if (!buffer.get_iter_at_line(out iter, display_line)) {
				return;
			}
			buffer.place_cursor(iter);
			this.source_view.scroll_to_iter(iter, 0.0, false, 0.0, 0.5);
		}
```

#### Remove (`restore_cursor_position` body after bounds check)

```vala
			// Use navigate_to_line to handle line navigation and scrolling
			this.navigate_to_line(file.cursor_line);
			
			// Then adjust the offset (character position within the line)
			Gtk.TextIter iter;
			if (!buffer.get_iter_at_line_offset(out iter, file.cursor_line, file.cursor_offset)) {
				return;
			}
			buffer.place_cursor(iter);
```

#### Replace with

```vala
			// Use navigate_to_line to handle line navigation and scrolling
			this.navigate_to_line(file.cursor_line);
			if (this.diff_active) {
				return;
			}
			// Then adjust the offset (character position within the line)
			Gtk.TextIter iter;
			if (!buffer.get_iter_at_line_offset(out iter, file.cursor_line, file.cursor_offset)) {
				return;
			}
			buffer.place_cursor(iter);
```

---

### 5. `liboccoder/SourceView.vala` — `show_pending_diff`

**Where:** after `clear_diff` (~666).

#### Add

```vala
		/**
		 * If {@code file} is pending approval, load V_backup via daemon and show inline diff.
		 *
		 * @param file open project file (buffer already holds V_disk)
		 */
		public async void show_pending_diff(OLLMfiles.File file)
		{
			if (!this.manager.review_files.file_map.has_key(file.path)) {
				return;
			}
			var row = this.manager.review_files.file_map.get(file.path);
			var gtk_buffer = file.buffer as GtkSource.Buffer;
			if (row.backup_path == "") {
				this.show_diff(new OLLMfiles.Diff.Differ("", gtk_buffer.text));
				return;
			}
			var v_backup = "";
			try {
				var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
					method = "RPC-File.read",
					args = OLLMrpc.args("s", row.backup_path)
				});
				if (this.current_file != file) {
					return;
				}
				v_backup = response.msg;
				if (response.msg_encode == 1) {
					v_backup = (string) GLib.Base64.decode(response.msg);
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed to read backup %s: %s", row.backup_path, e.message);
			}
			if (this.current_file != file) {
				return;
			}
			this.show_diff(new OLLMfiles.Diff.Differ(v_backup, gtk_buffer.text));
		}
```

---

### 6. `liboccoder/SourceView.vala` — leave-pending / rebuild on refresh

**Where:** after Approvals `file_selected` connect (~188–191).

#### Add

```vala
			this.manager.review_files.refreshed.connect(() => {
				if (this.current_file == null) {
					return;
				}
				if (!this.manager.review_files.file_map.has_key(this.current_file.path)) {
					this.clear_diff();
					return;
				}
				this.show_pending_diff.begin(this.current_file);
			});
```

---

### 7. `liboccoder/SourceView.vala` — `open_file` clear + show

**Where:** start of `open_file` (~460) and after buffer is on screen / deleted handled (~517–533).

#### Remove (start of `open_file`)

```vala
		public async void open_file(OLLMfiles.File file, int line_number = -1)
		{
			// Save current file state if switching away
			if (this.current_file != null && this.current_file != file) {
				this.save_current_file_state();
				// Disconnect delete_id signal handler from previous file
				this.disconnect_delete_id_handler();
			}
```

#### Replace with

```vala
		public async void open_file(OLLMfiles.File file, int line_number = -1)
		{
			// Leave diff before saving state (save reads source_view.buffer)
			if (this.diff_active) {
				this.clear_diff();
			}
			// Save current file state if switching away
			if (this.current_file != null && this.current_file != file) {
				this.save_current_file_state();
				// Disconnect delete_id signal handler from previous file
				this.disconnect_delete_id_handler();
			}
```

#### Remove (after deleted / editable branch, before search reset)

```vala
			// Check if file is already deleted
			if (file.delete_id > 0) {
				this.handle_file_deleted(file);
			} else {
				// Remove deleted CSS class if it was set
				this.source_view.remove_css_class("file-deleted");
				
				// Enable save button when file is open
				this.save_button.sensitive = true;
				
				// Make editor editable
				this.source_view.editable = true;
			}
			
			// Reset search context when switching files
```

#### Replace with

```vala
			// Check if file is already deleted
			if (file.delete_id > 0) {
				this.handle_file_deleted(file);
			} else {
				// Remove deleted CSS class if it was set
				this.source_view.remove_css_class("file-deleted");
				
				// Enable save button when file is open
				this.save_button.sensitive = true;
				
				// Make editor editable
				this.source_view.editable = true;

				yield this.show_pending_diff(file);
			}
			
			// Reset search context when switching files
```

ℹ️ Idle restore / `navigate_to_line` stay as today — **`navigate_to_line`** maps when **`diff_active`**; do **not** early-return on `diff_active` in the Idle.

---

### 8. `liboccoder/SourceView.vala` — invalidate reload while pending

**Where:** invalidate_cache handler after `file.read` (~153–160).

#### Remove

```vala
					file.read.begin((read_obj, read_res) => {
						file.read.end(read_res);
						if (this.current_file != file) {
							return;
						}
						this.source_view.set_buffer(file.buffer as GtkSource.Buffer);
						this.restore_cursor_position(file);
						this.restore_scroll_position(file);
					});
```

#### Replace with

```vala
					file.read.begin((read_obj, read_res) => {
						file.read.end(read_res);
						if (this.current_file != file) {
							return;
						}
						if (this.diff_active) {
							this.clear_diff();
						}
						this.source_view.set_buffer(file.buffer as GtkSource.Buffer);
						if (this.manager.review_files.file_map.has_key(file.path)) {
							this.show_pending_diff.begin(file);
							return;
						}
						this.restore_cursor_position(file);
						this.restore_scroll_position(file);
					});
```

---

## LLM notes

- 🚫 Local `GLib.FileUtils.get_contents` / `GLib.File` for backup paths in SourceView — use **`RPC-File.read`**.
- 🚫 New dedicated “read backup” RPC — reuse **`RPC-File.read`** with wired `backup_path`.
- 🚫 `File.read()` on a throwaway `File` for backup (would create an editor buffer) — call RPC for the string only.
- 🚫 Skip `navigate_to_line` when diff-active — map via remove offsets instead.
- 🚫 Per-row `diff_disk` array — only **`diff_remove_at` / `diff_remove_n`** per removed hunk.
- 🚫 Per-hunk approve / reject / unapprove (Phase **4**).
- 🚫 Carry-forward / cross-chunk matching.
- 🚫 Change Approvals button layout for Phase 3.
