# 4.2.3.5.2 — ReviewBar Phase B: product wire

**Status:** **⏳** proposed — design carry-over from parent

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md)

**Depends on:**

- [`done/CODER-4.2.3.4-DONE-source-view-diff-view.md`](done/CODER-4.2.3.4-DONE-source-view-diff-view.md) — **`show_pending_diff`**, backup vs disk diff
- [`done/CODER-4.2.3.5.1-DONE-source-view-diff-review-responses.md`](done/CODER-4.2.3.5.1-DONE-source-view-diff-review-responses.md) — **`responses()`**, **Feedback** popover (harness)
- Phase A **`ReviewBar`** + **`oc-test-source-diff`** — footer chrome **✅** user-smoked

**Contract reference:** [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md) (walkthrough, **`file_diff_part`**, Flow A–F) · [`CODER-4.2.3.1-source-view-diff-walkthrough-hello.md`](CODER-4.2.3.1-source-view-diff-walkthrough-hello.md)

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 Phase 1 — embed **`ReviewBar`** in the product editor and drive file nav from the real **`ReviewFiles`** queue.
- 🔷 Phase 2 — persist hunk decisions as **`file_diff_part`** via daemon RPC; reject writes **V_disk**, accept does not.
- 🔷 Phase 3 — header **`Approvals`** drops the changed-files list; **`show_pending_diff`** is the only pending-diff entry.
- ℹ️ Phase A mock decisions in **`ReviewBar`** become persistence + RPC in Phase 2.
- ℹ️ **`ReviewBar`** stays the review-chrome owner. **`SourceView`** keeps **`show_diff` / `navigate_to_line` / `clear_diff`** only (parent **SourceView vs ReviewBar**).

---

## Phase 1 — Wire chrome

Embed **`ReviewBar`** under **`SourceView`** (same layout as **`oc-test-source-diff`**). File nav, the inactive middle label, and the bulk menu use the real **`ReviewFiles`** queue. Bulk actions are stubs that report real counts. Part rows and disk writes are Phase 2.

- 🔷 ⏳ Pending file opens through existing **`show_pending_diff`** (builds **`Differ`**). Editor hosts **`ReviewBar`** under **`SourceView`**.
- 🔷 ⏳ **`n / N`** over the footer file list. Order is **basename**, then full path when basenames match.
- 🔷 ⏳ Footer file menu (header **`Approvals`** `next_button` interaction, anchored on the footer):
  - A file that is fully decided leaves the list. The previous queue is not copied back in.
  - That row is marked selected when the open file is in the list (1 of 3 on file 1 → row 1 selected).
  - No pending / partial / decided glyphs.
  - Header popover removal is Phase 3.
- 🔷 ⏳ Footer file menu row label is the basename. Hover tooltip is the path relative to the project root (no leading slash). Header **`Approvals`** stays **`last_modified` descending** until Phase 3.
- 🔷 ⏳ **1 of 1** (queue down to the file already open):
  - Bar stays visible.
  - Label stays **File n of N** (**File 1 of 1** on that file).
  - Prev / next hidden.
  - File-list popover disabled (no hover, click does nothing).
- 🔷 ⏳ Open a file with **zero** approvals → review bar hidden.
- 🔷 ⏳ Change notification (`event.project.invalidate_cache` / review refresh):
  - Current file is in the change set → stay on it. A later change to another file does not switch.
  - Current file is **not** in the change set → open the first change file.
  - Current file **is** the file that changed, already open, bar hidden → show the bar.
- 🔷 ⏳ Non-pending file: grey bar, red **`N changes pending review`** (real **N**). Click opens the **first** file in that basename order via **`show_pending_diff`**.
- 🔷 ⏳ Bulk hover menu is present (unapprove all on the file, accept all pending files, destructive bulk per parent). Actions are stubs. Confirm / revert semantics are Phase 2.
- 🔷 ⏳ Phone: no source-view diff preview. Tablet: **ReviewBar** + interleaved diff.
- 🔷 ⏳ A tap on the editor scroll view (menu dismiss and similar) belongs to the scroll view / **`SourceView`**, not **`ReviewBar`**.
- 🔷 ⏳ Owner calls **`responses()`** as in the harness. Product **`review_response`** handler (send the prompt to the LLM) is outside daemon part work.

Proposed edits below. Not applied. Phase 2 still owns part rows and disk writes. Bulk accept / reject stay the existing in-memory stubs and emit **`accept_all_files`** / **`reject_all_files`**. Phone (`ANDROID`) does not host the bar.

### 1. `liboccoder/Diff/ReviewBar.vala` — live queue fields

**Why:** Product file nav is a live list. The harness still uses the constructor `file_count` / `file_labels` path.

**Where:** `ReviewBar` fields, after `file_labels`.

**Depends on:** none.

#### Add — after `private string[] file_labels = {};`, the live queue of `FileWithHistory` rows. The menu reads display fields off each row.

```vala
		private bool live_queue = false;
		public Gee.ArrayList<OLLMfiles.FileWithHistory> queue {
			get; private set;
			default = new Gee.ArrayList<OLLMfiles.FileWithHistory>();
		}
```

`file_nav` stays the box. The control inside it is a `Gtk.Button`, so the field is `file_nav_btn`. Apply these before ### 4. ### 4 still removes the old `file_nav_label` line inside `update_diff`.

#### Remove

```vala
		private Gtk.Button file_nav_label;
```

#### Replace with — button field, not a label.

```vala
		private Gtk.Button file_nav_btn;
```

#### Remove

```vala
				this.file_nav_label.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
				this.file_index_changed(this.file_index);
			});
			this.file_next = new Gtk.Button() {
```

#### Replace with — prev click uses `file_nav_btn`.

```vala
				this.file_nav_btn.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
				this.file_index_changed(this.file_index);
			});
			this.file_next = new Gtk.Button() {
```

#### Remove

```vala
				this.file_nav_label.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
				this.file_index_changed(this.file_index);
			});
			this.file_nav_label = new Gtk.Button.with_label("");
```

#### Replace with — next click uses `file_nav_btn`.

```vala
				this.file_nav_btn.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
				this.file_index_changed(this.file_index);
			});
			this.file_nav_btn = new Gtk.Button.with_label("");
```

#### Remove

```vala
				this.file_nav_label.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
			}
			this.file_nav = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
			this.file_nav.append(this.file_prev);
			this.file_nav.append(this.file_nav_label);
```

#### Replace with — initial caption and box child.

```vala
				this.file_nav_btn.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
			}
			this.file_nav = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
			this.file_nav.append(this.file_prev);
			this.file_nav.append(this.file_nav_btn);
```

#### Remove

```vala
						this.file_nav_label.label = "File %d of %d".printf(
							pick + 1, this.file_count);
```

#### Replace with — harness menu pick uses `file_nav_btn`.

```vala
						this.file_nav_btn.label = "File %d of %d".printf(
							pick + 1, this.file_count);
```

#### Remove

```vala
			this.file_menu_popover.set_parent(this.file_nav_label);
			((Gtk.Popover) this.file_menu_popover).autohide = false;
			this.file_nav_label.clicked.connect(() => {
```

#### Replace with — popover parent and click handler.

```vala
			this.file_menu_popover.set_parent(this.file_nav_btn);
			((Gtk.Popover) this.file_menu_popover).autohide = false;
			this.file_nav_btn.clicked.connect(() => {
```

#### Remove

```vala
			this.file_nav_label.add_controller(file_anchor_motion);
```

#### Replace with — hover controller on the button.

```vala
			this.file_nav_btn.add_controller(file_anchor_motion);
```

### 2. `liboccoder/Diff/ReviewBar.vala` — inactive label opens the first file

**Why:** Click on `N changes pending review` opens the first file in basename order. The harness mock path is unchanged.

**Where:** `ReviewBar` constructor, `pending_click.pressed`.

**Depends on:** ### 1.

#### Remove

```vala
			pending_click.pressed.connect(() => {
				if (!this.mock_inactive) {
					return;
				}
```

#### Replace with — live queue emits index 0 and does not enter the mock path.

```vala
			pending_click.pressed.connect(() => {
				if (this.live_queue) {
					if (this.file_count < 1) {
						return;
					}
					this.file_index_changed(0);
					return;
				}
				if (!this.mock_inactive) {
					return;
				}
```

### 3. `liboccoder/Diff/ReviewBar.vala` — bulk menu always lists all-files stubs

**Why:** The product bar is constructed with `file_count` 1, so the all-files items would never appear. They stay stubs.

**Where:** `ReviewBar` constructor, both `if (this.file_count > 1)` blocks around the all-files menu section and its actions.

**Depends on:** none.

#### Remove

```vala
			if (this.file_count > 1) {
				var all_section = new GLib.Menu();
				var accept_all_files = new GLib.MenuItem(
					"Accept changes to all files", "bulk.accept-all-files");
				accept_all_files.set_icon(new GLib.ThemedIcon("emblem-ok-symbolic"));
				all_section.append_item(accept_all_files);
				var reject_all_files = new GLib.MenuItem(
					"Reject changes to all files", "bulk.reject-all-files");
				reject_all_files.set_icon(new GLib.ThemedIcon("dialog-cancel-symbolic"));
				all_section.append_item(reject_all_files);
				bulk_menu.append_section(null, all_section);
			}
```

#### Replace with — all-files section is always on the bulk menu.

```vala
			var all_section = new GLib.Menu();
			var accept_all_files = new GLib.MenuItem(
				"Accept changes to all files", "bulk.accept-all-files");
			accept_all_files.set_icon(new GLib.ThemedIcon("emblem-ok-symbolic"));
			all_section.append_item(accept_all_files);
			var reject_all_files = new GLib.MenuItem(
				"Reject changes to all files", "bulk.reject-all-files");
			reject_all_files.set_icon(new GLib.ThemedIcon("dialog-cancel-symbolic"));
			all_section.append_item(reject_all_files);
			bulk_menu.append_section(null, all_section);
```

#### Remove

```vala
			if (this.file_count > 1) {
				var accept_all_files_action = new GLib.SimpleAction("accept-all-files", null);
```

#### Replace with — drop the condition. Action bodies stay.

```vala
			var accept_all_files_action = new GLib.SimpleAction("accept-all-files", null);
```

#### Remove

```vala
				bulk_actions.add_action(reject_all_files_action);
			}
			this.insert_action_group("bulk", bulk_actions);
```

#### Replace with — remove the `if` closing brace. Action group insert stays.

```vala
				bulk_actions.add_action(reject_all_files_action);
			this.insert_action_group("bulk", bulk_actions);
```

### 4. `liboccoder/Diff/ReviewBar.vala` — `update_diff` keeps 1 of 1 nav

**Why:** `update_diff` currently hides file nav when `file_count` is 1. A live queue of one file stays visible as `File 1 of 1` with prev / next hidden. Popover click already returns when `file_count < 2`.

**Where:** `update_diff`, the `file_nav.visible` assignment.

**Depends on:** ### 1.

#### Remove

```vala
			this.file_nav.visible = this.file_count > 1;
			if (this.file_count > 1) {
				this.file_nav_label.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
			}
```

#### Replace with — live queue shows nav for one file. Label stays `File n of N`.

```vala
			this.file_nav.visible = this.live_queue ? this.file_count > 0 : this.file_count > 1;
			this.file_prev.visible = this.file_count > 1;
			this.file_next.visible = this.file_count > 1;
			if (this.file_nav.visible) {
				this.file_nav_btn.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
			}
```

### 5. `liboccoder/Diff/ReviewBar.vala` — `sync_pending`

**Why:** One method owns the live list: basename order, mark the open file when it is in that list, hide the bar when the list is empty. The pending rows passed in are the queue.

**Where:** end of class `ReviewBar`, after `on_reject_clicked`.

**Depends on:** ### 1, ### 4.

#### Add — new method `sync_pending` after `on_reject_clicked`.

```vala
		/**
		 * Replace the footer file list from the live pending queue.
		 *
		 * Basename order, then full path. The queue stores the
		 * ``FileWithHistory`` rows passed in. ``current_file`` is the
		 * open editor file, or null when none is open. The open row
		 * gets a select icon when it is in that list. No pending /
		 * partial / decided glyphs.
		 *
		 * @param pending pending rows (copied, then sorted)
		 * @param current_file open editor file, or null
		 */
		public void sync_pending(
			Gee.ArrayList<OLLMfiles.FileWithHistory> pending,
			OLLMfiles.File? current_file)
		{
			this.live_queue = true;
			var rows = new Gee.ArrayList<OLLMfiles.FileWithHistory>();
			rows.add_all(pending);
			rows.sort((a, b) => {
				var cmp = a.path_basename.collate(b.path_basename);
				if (cmp != 0) {
					return cmp;
				}
				return a.path.collate(b.path);
			});
			var on_list = false;
			this.file_index = 0;
			if (current_file != null) {
				for (var i = 0; i < rows.size; i++) {
					if (rows.get(i).path != current_file.path) {
						continue;
					}
					on_list = true;
					this.file_index = i;
				}
			}
			this.queue = rows;
			this.file_count = this.queue.size;
			this.file_bulk = new HunkDecision[int.max(1, this.file_count)];
			this.visible = this.file_count > 0;
			this.file_nav.visible = this.file_count > 0;
			this.file_prev.visible = this.file_count > 1;
			this.file_next.visible = this.file_count > 1;
			if (this.file_count < 1) {
				return;
			}
			if (on_list) {
				this.file_nav_btn.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
			}
			if (!on_list) {
				this.file_nav_btn.label = "%d files".printf(this.file_count);
				this.file_index = 0;
			}
			this.pending_label.visible = !on_list;
			this.map_area.visible = on_list;
			this.map_scroll_left.visible = on_list;
			this.map_scroll_right.visible = on_list;
			if (!on_list) {
				this.pending_label.label = "%d changes pending review".printf(
					this.file_count);
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.feedback_btn.visible = false;
				this.unapprove_btn.visible = false;
			}
			var file_list = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			var project = this.source_view.manager.active_project;
			for (var fi = 0; fi < this.queue.size; fi++) {
				var pick = fi;
				var rel = this.queue.get(fi).path;
				if (project != null && rel.has_prefix(project.path)) {
					rel = rel.substring(project.path.length);
					if (rel.has_prefix("/")) {
						rel = rel.substring(1);
					}
				}
				var row_btn = new Gtk.Button() {
					label = this.queue.get(fi).path_basename,
					tooltip_text = rel,
					has_frame = false,
				};
				if (on_list && fi == this.file_index) {
					row_btn.icon_name = "object-select-symbolic";
				}
				row_btn.clicked.connect(() => {
					if (this.file_index != pick) {
						this.file_index = pick;
						this.file_nav_btn.label = "File %d of %d".printf(
							pick + 1, this.file_count);
						this.file_index_changed(pick);
					}
					((Gtk.Popover) this.file_menu_popover).popdown();
				});
				file_list.append(row_btn);
			}
			((Gtk.Popover) this.file_menu_popover).set_child(file_list);
		}
```

### 6. `liboccoder/SourceView.vala` — host the bar

**Why:** Same stack as `oc-test-source-diff`: overlay plus footer. `ANDROID` keeps the scrolled view only.

**Where:** field next to `approvals`. Constructor, replace `this.append(this.scrolled_window)`.

**Depends on:** ### 5.

#### Add — field under `private Approvals? approvals = null;`.

```vala
#if !ANDROID
		private OLLMcoder.Diff.ReviewBar review_bar;
#endif
```

#### Remove

```vala
			this.scrolled_window.set_child(this.source_view);
			// Hide sourceview initially until a file is opened
			this.scrolled_window.visible = false;
			this.append(this.scrolled_window);
```

#### Replace with — desktop hosts `ReviewBar`. Phone appends the scrolled view as today.

```vala
			this.scrolled_window.set_child(this.source_view);
			// Hide sourceview initially until a file is opened
			this.scrolled_window.visible = false;
#if ANDROID
			this.append(this.scrolled_window);
#else
			this.review_bar = new OLLMcoder.Diff.ReviewBar(this);
			this.review_bar.visible = false;
			this.review_bar.responses(new Gee.ArrayList<OLLMcoder.Diff.ReviewResponse>());
			var editor_overlay = new Gtk.Overlay() {
				vexpand = true,
				hexpand = true,
			};
			editor_overlay.set_child(this.scrolled_window);
			editor_overlay.add_overlay(this.review_bar.review_overlay);
			this.append(editor_overlay);
			this.append(this.review_bar);
			this.review_bar.file_index_changed.connect((index) => {
				if (index < 0 || index >= this.review_bar.queue.size) {
					return;
				}
				var path = this.review_bar.queue.get(index).path;
				if (this.current_file != null && this.current_file.path == path) {
					return;
				}
				var cached = this.manager.file_cache.get(path) as OLLMfiles.File;
				if (cached != null) {
					this.open_file.begin(cached);
					return;
				}
				if (this.manager.active_project == null) {
					return;
				}
				this.manager.active_project.fetch_file.begin(path, (obj, res) => {
					var file = this.manager.active_project.fetch_file.end(res);
					if (file == null) {
						return;
					}
					if (this.current_file != null && this.current_file.path == path) {
						return;
					}
					this.open_file.begin(file);
				});
			});
#endif
```

### 7. `liboccoder/SourceView.vala` — `review_files.refreshed`

**Why:** On a review refresh, stay when the open file is in the queue (including a decided file kept on the bar). Otherwise open the first file in basename order. An already-open changed file with the bar hidden is shown by `sync_pending`.

**Where:** constructor, `review_files.refreshed` handler.

**Depends on:** ### 5, ### 6.

#### Remove

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

#### Replace with — desktop follows the live queue. Phone keeps the old handler.

```vala
			this.manager.review_files.refreshed.connect(() => {
#if ANDROID
				if (this.current_file == null) {
					return;
				}
				if (!this.manager.review_files.file_map.has_key(this.current_file.path)) {
					this.clear_diff();
					return;
				}
				this.show_pending_diff.begin(this.current_file);
#else
				var rows = new Gee.ArrayList<OLLMfiles.FileWithHistory>();
				rows.add_all(this.manager.review_files.file_map.values);
				this.review_bar.sync_pending(rows, this.current_file);
				if (this.review_bar.queue.size < 1) {
					return;
				}
				if (this.current_file != null
					&& this.manager.review_files.file_map.has_key(this.current_file.path)) {
					this.show_pending_diff.begin(this.current_file);
					return;
				}
				var first = this.review_bar.queue.get(0).path;
				var cached = this.manager.file_cache.get(first) as OLLMfiles.File;
				if (cached != null) {
					this.open_file.begin(cached);
					return;
				}
				if (this.manager.active_project == null) {
					return;
				}
				this.manager.active_project.fetch_file.begin(first, (obj, res) => {
					var file = this.manager.active_project.fetch_file.end(res);
					if (file == null) {
						return;
					}
					if (this.current_file != null
						&& this.manager.review_files.file_map.has_key(this.current_file.path)) {
						return;
					}
					this.open_file.begin(file);
				});
#endif
			});
```

### 8. `liboccoder/SourceView.vala` — `open_file` hides the bar when nothing is pending

**Why:** Opening a file with zero approvals hides the bar. The pending list passed in is the queue.

**Where:** `open_file`, immediately before `yield this.show_pending_diff(file)`.

**Depends on:** ### 5, ### 6.

#### Remove

```vala
				yield this.show_pending_diff(file);
```

#### Replace with — sync the queue, then show the diff when this file is pending.

```vala
#if !ANDROID
				var rows = new Gee.ArrayList<OLLMfiles.FileWithHistory>();
				rows.add_all(this.manager.review_files.file_map.values);
				this.review_bar.sync_pending(rows, file);
#endif
				yield this.show_pending_diff(file);
```

### 9. `liboccoder/SourceView.vala` — `show_pending_diff` feeds `update_diff`

**Why:** The bar's hunk map follows the differ `show_pending_diff` already builds. No new review API on `SourceView`.

**Where:** `show_pending_diff`, both `show_diff` call sites.

**Depends on:** ### 4, ### 6.

#### Remove

```vala
			if (row.backup_path == "") {
				this.show_diff(new OLLMfiles.Diff.Differ("", gtk_buffer.text));
				return;
			}
```

#### Replace with — empty backup still shows the diff, then updates the bar.

```vala
			if (row.backup_path == "") {
				var differ = new OLLMfiles.Diff.Differ("", gtk_buffer.text);
				this.show_diff(differ);
#if !ANDROID
				this.review_bar.update_diff(differ, this.review_bar.file_index);
#endif
				return;
			}
```

#### Remove

```vala
			this.show_diff(new OLLMfiles.Diff.Differ(v_backup, gtk_buffer.text));
		}
```

#### Replace with — backup text updates the bar the same way.

```vala
			var differ = new OLLMfiles.Diff.Differ(v_backup, gtk_buffer.text);
			this.show_diff(differ);
#if !ANDROID
			this.review_bar.update_diff(differ, this.review_bar.file_index);
#endif
		}
```

---

## Phase 2 — Daemon + parts

**`ReviewBar.update_diff`** loads hunks from **`Differ.patches`** and merges **`file_diff_part`** rows for the active **`file_history`** chunk. No row means the hunk is still pending. Depends on Phase 1 hosting the bar.

- 🔷 ⏳ Accept hunk → insert **`file_diff_part`** with **`accepted=1`**. No disk write. Grey band and advance.
- 🔷 ⏳ Reject hunk → undo that hunk on **V_disk** and insert **`accepted=0`**. Grey band and advance.
- 🔷 ⏳ Unapprove → delete the part row. Band returns to pending. Disk is unchanged for a prior accept.
- 🔷 ⏳ Insert a part row on the **first** accept or reject of that hunk. No upfront rows on agent write.
- 🔷 ⏳ Every hunk in the chunk has a part row → **`file_history.reviewed=1`**.
- 🔷 ⏳ Daemon RPC for part insert, part delete, and reject-apply. Method names still open.
- 🔷 ⏳ Hunk bytes at **`FileDiffPart.path`**: unified-diff text vs serialised **`Patch`**. Still open (parent).
- 🔷 ⏳ Stacked LLM edit (**Flow B**): review **H2** only. No carry-forward in v1.
- 🔷 ⏳ Unsaved dirty buffer while reviewing: **lean no**.
- 🔷 ⏳ Accept all pending files: confirm and revert semantics still open. Phase 1 only stubs the menu.
- ℹ️ Accept does not rewrite disk. Reject does, for that hunk only.

---

## Phase 3 — Approvals cleanup

Header **`Approvals`** no longer owns the changed-files list. Depends on Phase 1 footer nav. Whole-file approve / reject moves off the header once the footer bulk menu is real (Phase 2).

- 🔷 ⏳ Remove the header changed-files popover.
- 🔷 ⏳ Relocate whole-file Approve / Reject. They are not a second pending-diff path.
- 🔷 ⏳ **`show_pending_diff`** is the single entry for pending diff and bar state.
- 🔷 ⏳ Whole-file reject (full **V_backup** restore) stays destructive: header **`Approvals`** or the bulk menu, not a casual band click.

---

## LLM notes

- 🚫 Accept all files as primary header button.
- 🚫 Carry-forward inside **`OLLMfiles.Diff`**.
- 🚫 Keep header changed-files popover after footer file nav ships.
- 🚫 Phone source-view diff preview (tablet only).
- 🚫 **ReviewBar** handling taps on the editor scroll view.
- 🚫 Split **`ReviewBar.vala`** without explicit user request.
- 🚫 Add review-state APIs to **`SourceView`** — **ReviewBar** only.
- 🚫 Rewrite disk on **accept**.
- 🚫 Approve / unapprove aliased to GtkSource undo/redo.
- ℹ️ Touch points: `liboccoder/Diff/ReviewBar.vala`, `liboccoder/SourceView.vala`, `liboccoder/Approvals.vala`, `ollmfilesd/FileHistory.vala`, `ollmfilesd/FileDiffPart.vala`, `libocfiles/ReviewFiles.vala`.
