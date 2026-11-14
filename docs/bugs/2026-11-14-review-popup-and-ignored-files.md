# ReviewBar file popup layout/icons and ignored files still in review list

**Status:** ✔️ applied 2026-11-14 — awaiting a check in the app and the file daemon

## Problem

- 🔷 In the `ReviewBar` footer file-switcher popup (`File N of M`):
  - 🔷 Each row should display an icon indicating the file change status (`added`, `modified`, `deleted`) instead of text prefixes (`deleted — `, `modified — `).
  - 🔷 Selecting a file in the popup shows only a tick (`object-select-symbolic`) with no filename; the selected file should be highlighted (e.g. selected row background) rather than showing a tick.
  - 🔷 All rows in the popup are center-aligned instead of left-aligned.
- 🔷 Ignored files under `.git` (`.git/index` / git-ignored paths) are still appearing in the pending review popup even though ignored-file handling was supposed to exclude them.

## Evidence

- ℹ️ Live session at `12:19:58`–`12:21:29` (`~/.cache/ollmchat/ollmchat.debug.log`, `~/.cache/ollmchat/ollmfilesd.debug.log`, `~/.local/share/ollmchat/files.sqlite`), running `/usr/bin/ollmfilesd` and `/usr/bin/ollmchat` built `2026-11-14 12:05`.
- ✔️ **ReviewBar popup (`liboccoder/Diff/ReviewBar.vala:1641-1689`):**
  - ✔️ `sync_pending` formats `row_label = "%s — %s".printf(this.queue.get(fi).last_change_type, row_label)` (lines 1653–1657) as text instead of an icon.
  - ✔️ `row_btn` is created with `new Gtk.Button() { label = row_label, tooltip_text = rel, has_frame = false }` (lines 1658–1662). A `Gtk.Button` created with `label` centers its internal `Gtk.Label` (`xalign = 0.5f`), so all rows are center-aligned.
  - ✔️ Lines 1663–1665 run `if (on_list && fi == this.file_index) { row_btn.icon_name = "object-select-symbolic"; }`. In GTK4, setting `Gtk.Button.icon_name` replaces `Gtk.Button.child` with a `Gtk.Image`, removing `label` completely so the active row renders only the checkmark icon.
  - ✔️ `file_menu_popover` is declared and constructed as `Gtk.PopoverMenu.from_model(file_menu)` (lines 186, 327), and `sync_pending` replaces its child with `((Gtk.Popover) this.file_menu_popover).set_child(file_list)` (line 1689). In `~/.cache/ollmchat/ollmchat.debug.log` (lines 184–235), every popup open/close emits three `GTK_CRITICAL` errors (`gtk_scrolled_window_get_child`, `gtk_viewport_get_child`, `gtk_stack_set_visible_child_name`) because `Gtk.PopoverMenu`'s internal `GtkStack` was replaced.
  - ✔️ Clicking `file_prev` (lines 238–256), `file_next` (lines 260–278), or a popover `row_btn` (lines 1666–1686) updates `this.file_index` immediately, while `sync_pending` only rebuilds `file_list` later when `open_file` completes (`SourceView.vala:625, 657`).
- ✔️ **Ignored `.git/index` still in pending list (`files.sqlite`, `ollmfilesd`):**
  - ✔️ `filebase` id `112505`: `/home/alan/gitlive/OLLMchat/.git/index`, `is_ignored=0`, `is_need_approval=1`, `delete_id=43029`, `parent_id=112504` (`OLLMchat/.git`, `is_ignored=0`, `delete_id=43028`). History rows `43026` (`added`, `reviewed=0`) and `43029` (`deleted`, `reviewed=0`).
  - ✔️ `filebase` id `113030`: `/home/alan/gitlive/OLLMchat/.git`, `is_ignored=1`, `is_need_approval=0`, `delete_id=0`.
  - ✔️ In `argusrm`: `filebase` id `112979` (`/home/alan/gitlive/argusrm/.git`, `is_ignored=0`) and 7 rows `112980`–`112986` (`/home/alan/gitlive/argusrm/.git/index`, `is_ignored=0`, `is_need_approval=1`).
  - ✔️ `/home/alan/gitlive/OLLMchat/.gitignore` (`id=40`) has `is_ignored=0`, `is_need_approval=0`, and no `file_history` rows (it is a tracked git file, not ignored, and not in the review list).
  - ✔️ Running `FileWithHistory.pending`'s SQL query against `files.sqlite` for `/home/alan/gitlive/OLLMchat` returns `112505` (`/home/alan/gitlive/OLLMchat/.git/index`) among the 5 pending files.
  - ✔️ [`2026-11-13-FIXED-ignored-git-index-in-review.md`](done/2026-11-13-FIXED-ignored-git-index-in-review.md) (`e711f928`) noted that restarting `ollmfilesd` would leave the pre-existing `112505` row as `is_ignored=0` because `Folder.read_dir` skips ignored directories (`if (child.delete_id != 0 || child.is_ignored) continue;`) and `Folder.load_files_from_db` filters `AND delete_id = 0`. Restarting `ollmfilesd` today (`12:05:51`) did not clear `112505`, so `FileWithHistory.pending` still returns it.
  - ✔️ `ollmfilesd/FileVerification.vala` (`created` lines 150–156 and `modified` lines 254–260) still writes `FileHistory` and sets `is_need_approval = true` on `modified` without checking `check_path_ignored` or `!file.is_ignored` (unlike `ollmfilesd/File.vala:443-451`).
  - ✔️ `Folder.make_children` (`ollmfilesd/Folder.vala:1635`) and `File.to_real` (`ollmfilesd/File.vala:775`) call `check_path_ignored` on `this` / `found_base_folder`, which returns `false` if `discover_repository` has not yet populated `"repo"` on that folder (e.g. a folder loaded from DB before `read_dir` visits it, or a newly created subfolder from `make_children`).

## Root cause

- ✔️ **Popup rows:** `ReviewBar.sync_pending` sets `row_btn.icon_name` after `row_btn.label` (replacing the label widget with an icon in GTK4), uses `Gtk.Button.label` directly (center-aligned by default), formats `last_change_type` as text instead of an icon, and calls `set_child` on a `Gtk.PopoverMenu` instead of a `Gtk.Popover`.
- ✔️ **Ignored files:** `FileWithHistory.pending` trusts the stored `filebase.is_ignored` column alone without consulting `project.check_path_ignored`, so pre-existing rows under `.git/` (such as `112505` in `OLLMchat` and `112980`–`112986` in `argusrm`, which `read_dir` never re-visits) stay `is_ignored=0` and keep appearing in the review list. In addition, `FileVerification.vala` (`created`/`modified`) and `check_path_ignored` on folders without `"repo"` yet can still record ignored modifications.

## Proposed fix

- 🔷 **Popup status icon, left alignment, and selected row (`liboccoder/Diff/ReviewBar.vala`):**
  - 🔷 Replace `Gtk.PopoverMenu` for `file_menu_popover` with `Gtk.Popover`. The popover child is a `Gtk.ListBox` kept on `file_list`.
  - 🔷 Each row is a left-aligned `Gtk.Box(Gtk.Orientation.HORIZONTAL, 6)`: a status `Gtk.Image`, then a `Gtk.Label(basename)` (`xalign = 0.0f`, `hexpand = true`).
  - 💩 Status icon mapping (confirm icon choices): `added` → `list-add-symbolic`, `modified` → `document-edit-symbolic`, `deleted` → `user-trash-symbolic`.
  - 🔷 The open file is `file_list.select_row` on that index. `selection_mode` is `SINGLE`. The theme paints the selected row. No new CSS class, and no walk of the list’s children.
- 🔷 **Exclude git-ignored paths from pending approvals and overlay writes (`ollmfilesd/FileWithHistory.vala`, `ollmfilesd/Folder.vala`, `ollmfilesd/FileVerification.vala`, `ollmfilesd/File.vala`):**
  - 🔷 Ensure `project.discover_repository` has run before `check_path_ignored` (or delegate to `this.manager.active_project.check_path_ignored` when a folder has no `"repo"` attached).
  - 🔷 Filter `FileWithHistory.pending` results with `project.check_path_ignored(row.path)` so ignored paths (including pre-existing `.git/index` rows) are never returned to the client.
  - 💩 Also clear stale `is_ignored = 1, is_need_approval = 0` in `filebase` when `FileWithHistory.pending` encounters an ignored row so it does not keep getting scanned on every `since_id = 0` replay.
  - 🔷 Add the same `check_path_ignored` / `!file.is_ignored` guard to `FileVerification.created` and `FileVerification.modified` (`ollmfilesd/FileVerification.vala`) that `File.write` (`ollmfilesd/File.vala`) already uses.

### 1. `liboccoder/Diff/ReviewBar.vala` — `file_menu_popover` type and mock/live row layout

**Why:** `Gtk.PopoverMenu` asserts when its child replaces the internal `GtkStack`. A `Gtk.Popover` whose child is a `Gtk.ListBox` fixes that. `select_row` marks the open file, so the filename stays, the row is left-aligned, and the theme draws the selection. A status icon replaces the `added` / `modified` / `deleted` text.

**Where:** `file_menu_popover` field (line 186), constructor file-menu setup (lines 296–385), `file_prev` / `file_next` handlers (lines 238–278), and `sync_pending` row construction (lines 1641–1689).

#### Remove

```vala
		private Gtk.PopoverMenu file_menu_popover;
```

#### Replace with

```vala
		private Gtk.Popover file_menu_popover;
		private Gtk.ListBox file_list;
```

#### Remove

```vala
			var file_menu = new GLib.Menu();
			var file_actions = new GLib.SimpleActionGroup();
			for (var fi = 0; fi < this.file_labels.length; fi++) {
				var pick = fi;
				var action_name = "pick-%u".printf(fi);
				var pick_action = new GLib.SimpleAction(action_name, null);
				pick_action.activate.connect(() => {
					if (this.file_index != pick) {
						this.file_index = pick;
						this.file_nav_btn.label = "File %d of %d".printf(
							pick + 1, this.file_count);
						if (this.queue.size > 1) {
							this.file_prev.tooltip_text = this.queue.get(
								(this.file_index - 1 + this.file_count) % this.file_count).path_basename;
							this.file_next.tooltip_text = this.queue.get(
								(this.file_index + 1) % this.file_count).path_basename;
						}
						if (this.queue.size < 2 && this.file_labels.length > 1) {
							this.file_prev.tooltip_text = this.file_labels[
								(this.file_index - 1 + this.file_count) % this.file_count];
							this.file_next.tooltip_text = this.file_labels[
								(this.file_index + 1) % this.file_count];
						}
						this.file_index_changed(pick);
					}
					((Gtk.Popover) this.file_menu_popover).popdown();
				});
				file_actions.add_action(pick_action);
				file_menu.append(this.file_labels[fi], "file.%s".printf(action_name));
			}
			this.insert_action_group("file", file_actions);
			this.file_menu_popover = new Gtk.PopoverMenu.from_model(file_menu);
			this.file_menu_popover.set_parent(this.file_nav_btn);
			((Gtk.Popover) this.file_menu_popover).autohide = false;
```

#### Replace with

```vala
			this.file_list = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.SINGLE,
				activate_on_single_click = true,
			};
			for (var fi = 0; fi < this.file_labels.length; fi++) {
				this.file_list.append(new Gtk.Label(this.file_labels[fi]) {
					xalign = 0.0f,
					hexpand = true,
				});
			}
			this.file_list.select_row(
				this.file_list.get_row_at_index(this.file_index));
			this.file_list.row_activated.connect((line) => {
				var pick = line.get_index();
				if (this.file_index == pick) {
					this.file_menu_popover.popdown();
					return;
				}
				this.file_index = pick;
				this.file_nav_btn.label = "File %d of %d".printf(
					pick + 1, this.file_count);
				if (this.queue.size > 1) {
					this.file_prev.tooltip_text = this.queue.get(
						(this.file_index - 1 + this.file_count) % this.file_count).path_basename;
					this.file_next.tooltip_text = this.queue.get(
						(this.file_index + 1) % this.file_count).path_basename;
				}
				if (this.queue.size < 2 && this.file_labels.length > 1) {
					this.file_prev.tooltip_text = this.file_labels[
						(this.file_index - 1 + this.file_count) % this.file_count];
					this.file_next.tooltip_text = this.file_labels[
						(this.file_index + 1) % this.file_count];
				}
				this.file_index_changed(pick);
				this.file_menu_popover.popdown();
			});
			this.file_menu_popover = new Gtk.Popover() {
				autohide = false,
				child = this.file_list,
			};
			this.file_menu_popover.set_parent(this.file_nav_btn);
```

#### Remove

In `sync_pending`, from `var file_list = new Gtk.Box` through `set_child` (lines 1641–1689), including `var pick = fi`:

```vala
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
				var row_label = this.queue.get(fi).path_basename;
				if (this.queue.get(fi).last_change_type != "") {
					row_label = "%s — %s".printf(
						this.queue.get(fi).last_change_type,
						row_label);
				}
				var row_btn = new Gtk.Button() {
					label = row_label,
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
						if (this.queue.size > 1) {
							this.file_prev.tooltip_text = this.queue.get(
								(this.file_index - 1 + this.file_count) % this.file_count).path_basename;
							this.file_next.tooltip_text = this.queue.get(
								(this.file_index + 1) % this.file_count).path_basename;
						}
						if (this.queue.size < 2 && this.file_labels.length > 1) {
							this.file_prev.tooltip_text = this.file_labels[
								(this.file_index - 1 + this.file_count) % this.file_count];
							this.file_next.tooltip_text = this.file_labels[
								(this.file_index + 1) % this.file_count];
						}
						this.file_index_changed(pick);
					}
					((Gtk.Popover) this.file_menu_popover).popdown();
				});
				file_list.append(row_btn);
			}
			((Gtk.Popover) this.file_menu_popover).set_child(file_list);
```

#### Replace with

```vala
			this.file_list = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.SINGLE,
				activate_on_single_click = true,
			};
			var project = this.source_view.manager.active_project;
			for (var fi = 0; fi < this.queue.size; fi++) {
				var rel = this.queue.get(fi).path;
				if (project != null && rel.has_prefix(project.path)) {
					rel = rel.substring(project.path.length);
					if (rel.has_prefix("/")) {
						rel = rel.substring(1);
					}
				}
				var row = this.queue.get(fi);
				var row_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
					hexpand = true,
				};
				switch (row.last_change_type) {
					case "added":
						row_box.append(new Gtk.Image.from_icon_name(
							"list-add-symbolic"));
						break;

					case "deleted":
						row_box.append(new Gtk.Image.from_icon_name(
							"user-trash-symbolic"));
						break;

					case "modified":
						row_box.append(new Gtk.Image.from_icon_name(
							"document-edit-symbolic"));
						break;

					default:
						break;
				}
				row_box.append(new Gtk.Label(row.path_basename) {
					xalign = 0.0f,
					hexpand = true,
					tooltip_text = rel,
				});
				this.file_list.append(row_box);
			}
			if (on_list) {
				this.file_list.select_row(
					this.file_list.get_row_at_index(this.file_index));
			}
			this.file_list.row_activated.connect((line) => {
				var pick = line.get_index();
				if (this.file_index == pick) {
					this.file_menu_popover.popdown();
					return;
				}
				this.file_index = pick;
				this.file_nav_btn.label = "File %d of %d".printf(
					pick + 1, this.file_count);
				if (this.queue.size > 1) {
					this.file_prev.tooltip_text = this.queue.get(
						(this.file_index - 1 + this.file_count) % this.file_count).path_basename;
					this.file_next.tooltip_text = this.queue.get(
						(this.file_index + 1) % this.file_count).path_basename;
				}
				if (this.queue.size < 2 && this.file_labels.length > 1) {
					this.file_prev.tooltip_text = this.file_labels[
						(this.file_index - 1 + this.file_count) % this.file_count];
					this.file_next.tooltip_text = this.file_labels[
						(this.file_index + 1) % this.file_count];
				}
				this.file_index_changed(pick);
				this.file_menu_popover.popdown();
			});
			this.file_menu_popover.child = this.file_list;
```

#### Add

In `file_prev.clicked` and `file_next.clicked`, after `this.file_index` changes and before `this.file_index_changed`:

```vala
				this.file_list.select_row(
					this.file_list.get_row_at_index(this.file_index));
```

### 2. `ollmfilesd/Folder.vala` — `check_path_ignored` when folder has no `"repo"` yet

**Why:** Folders created by `make_children` or loaded from DB before `read_dir` reaches them do not have `"repo"` set yet, so `check_path_ignored` returns `false` on them.

**Where:** `check_path_ignored` (lines 786–797).

#### Remove

```vala
			// Check if repository exists
			if (!this.manager.git_provider.repository_exists(this)) {
				return false;
			}
```

#### Replace with

```vala
			if (!this.manager.git_provider.repository_exists(this)) {
				this.discover_repository(this.is_project);
			}
			if (!this.manager.git_provider.repository_exists(this)) {
				return false;
			}
```

### 3. `ollmfilesd/FileWithHistory.vala` — `pending`: enforce `project.check_path_ignored`

**Why:** Pre-existing ignored rows (such as `.git/index` row `112505` with `delete_id=43029` and `is_ignored=0`) are never revisited by `read_dir`, so `filebase.is_ignored` stays `0` in SQLite. Checking `project.check_path_ignored(row.path)` keeps them out of the review list.

**Where:** `FileWithHistory.pending` loop (lines 166–170).

#### Remove

```vala
			foreach (var row in rows) {
				list.add(row);
			}
```

#### Replace with

```vala
			foreach (var row in rows) {
				if (project.check_path_ignored(row.path)) {
					continue;
				}
				list.add(row);
			}
```

- 💩 Optional DB cleanup inside that `if (project.check_path_ignored(row.path))` block: update `filebase` (`SET is_ignored = 1, is_need_approval = 0 WHERE id = ...`) when `row.id > 0` so stale rows are corrected on disk too.

### 4. `ollmfilesd/FileVerification.vala` — `created` and `modified`: skip history for ignored files

**Why:** Overlay sync handles `modified` writes from sandboxed commands (such as `git`) the same way `File.write` does, and currently sets `is_need_approval = true` and commits `FileHistory` even when the file is git-ignored.

**Where:** `FileVerification.created` (lines 150–156) and `FileVerification.modified` (lines 254–260).

#### Remove

In `FileVerification.created` (and the identical lines in `FileVerification.modified`):

```vala
						if (change_type == "modified" && this.manager.db != null) {
							file.is_need_approval = true;
							file.last_change_type = "modified";
							var file_history = new FileHistory(this.manager.db,
								file, "modified", new GLib.DateTime.now_local());
							yield file_history.commit();
							file.saveToDB(this.manager.db, null, false);
						}
```

#### Replace with

```vala
						if (this.manager.active_project != null) {
							file.is_ignored =
								this.manager.active_project.check_path_ignored(
									file.path
								);
						}
						if (change_type == "modified" &&
							this.manager.db != null &&
							!file.is_ignored) {
							file.is_need_approval = true;
							file.last_change_type = "modified";
							var file_history = new FileHistory(this.manager.db,
								file, "modified", new GLib.DateTime.now_local());
							yield file_history.commit();
							file.saveToDB(this.manager.db, null, false);
						}
```

## Attempts / changelog

- ✔️ 2026-11-14: Inspected `liboccoder/Diff/ReviewBar.vala`, `resources/style.css`, `ollmfilesd/Folder.vala`, `ollmfilesd/FileWithHistory.vala`, `ollmfilesd/File.vala`, `ollmfilesd/FileVerification.vala`, `~/.cache/ollmchat/ollmchat.debug.log`, `~/.cache/ollmchat/ollmfilesd.debug.log`, and `~/.local/share/ollmchat/files.sqlite`. No product code edited.
- 🔷 2026-11-14: Click handlers denest with early `if (this.file_index == pick) { popdown(); return; }`. Queue rows use `this.queue.get(fi)` (not `[]`). Popover child uses `.child` property (not `set_child` / `get_child`). `file_labels` stays `string[]` index access.
- 🚫 2026-11-14: `oc-diff-file-selected` and the sibling walk are withdrawn. The popup child is a `Gtk.ListBox` on `file_list`. `select_row` marks the open file. The theme paints that row.
- ✔️ 2026-11-14: Applied the popup list, `check_path_ignored` discovery, the pending-list filter, and the overlay ignore guard. The optional `filebase` flag cleanup was not applied. `ninja -C build` linked `liboccoder.so`.

## Next

- 🔷 ⏳ Open the review popup: each row is left-aligned, shows a status icon, and the open file is the selected row. `.git/index` is absent from the list after `ollmfilesd` is restarted.
