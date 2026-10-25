# File sheet opens at the project, not the open file

**Status:** ✅ User closed the file sheet. Closed 2026-10-25.

## Problem

- 🔷 Opening the tablet file sheet (the look-around view) always starts at the project root.
- 🔷 When a file is already open in the editor, the sheet should open on that file's folder.
- 🔷 The open file should be highlighted in the file list.
- 🔷 That highlight is not a selection. The row is not the selected file, and opening the sheet does not act as if that file was chosen.
- 🔷 With no file open, the sheet still starts at the project.

## Evidence

- ℹ️ `FileOverlay.activate` sets `level` to the project and loads that folder. `examples/oc-test-source-diff/FileOverlay.vala`.
- ℹ️ `SourceView.open_file` calls `manager.activate_file`, so the open file is `ProjectManager.active_file`. `FileOverlay` already has that manager. `examples/oc-test-source-diff/SourceView.vala`.
- ℹ️ `CoderView` hears `file_changed` and only updates the header label. `examples/oc-test-source-diff/CoderView.vala`.
- ℹ️ The file grid uses `Gtk.SingleSelection` with `autoselect` off. A selected row is the keyboard target. `FileList.load` clears that selection. `examples/oc-test-source-diff/FileList.vala`.
- ℹ️ `FileList.load` does not remember the folder. Every call clears the rows and asks the server with `Folder.fetch_dir`. Opening the sheet on the folder already showing fetches again and drops any mark. `examples/oc-test-source-diff/FileList.vala`, `examples/oc-test-source-diff/FileListStore.vala`.
- ℹ️ `row.selector-mark` is the existing paint for a marked row that is not the Gtk selection. `resources/style.css`.

## Root cause

- ✔️ Tablet `FileOverlay.activate` always sets `level` to the project and loads that folder. It never reads `manager.active_file`. Nothing paints a non-selected mark on the file grid.

## Attempts

- 💩 A first pass stored the path again on `FileNav.open_path` and `FileList.mark_path`. Pulled out. The open file is already `manager.active_file`.

## Proposed fix

- 🔷 Tablet open sets `level` to the folder already stored for `manager.active_file.parent_id` in `folder_tree.folders.id_map`, then `refresh_folder` and `file_list.load` use that folder. No open file, or a parent that is not in this tree, still opens the project.
- 🔷 `FileList` remembers that folder. A later `load` of the same folder returns before `Folder.fetch_dir`, so the rows stay.
- 💩 Choosing a file sets `is_active` on that row's file. The bound row adds `selector-mark` then. The sheet can close and open again on that folder without a fetch, and the mark is still on the row. `file_selection.selected` stays cleared. A real load of a different folder paints the mark in `bind` when that file is already `is_active`.
- 🚫 Do not store the open path as a string. Do not add `open_path` or `mark_path`. Do not derive the folder with `GLib.Path.get_dirname` or `path_map`.
- 🚫 Do not scan the file grid for the open file, and do not scroll to it.

### 1. `examples/oc-test-source-diff/FileOverlay.vala` — `activate`: land on the open file's folder

**Why:** The sheet has to select the parent folder the tree already stored for the open file. `refresh_folder` already selects that row when the folder has no child folders.

**Where:** `activate`, both tablet landings. The tree-already-loaded branch, then the same lines in the `load` callback. Up is hidden only at the project.

**Depends on:** none.

#### Remove

```vala
				this.level = this.project;
				this.place_gen++;
				this.render_crumbs();
				this.up.visible = false;
				this.browse.project = this.project;
				this.browse.refresh_folder(this.project);
				this.file_list.load(this.project);
```

#### Replace with

Tree already loaded. Inside `if (this.folder_tree.folders.loaded.contains(this.project.path))`.

```vala
				this.level = this.project;
				var open = this.manager.active_file;
				if (open != null &&
					this.folder_tree.folders.id_map.has_key((int) open.parent_id)) {
					this.level = this.folder_tree.folders.id_map.get((int) open.parent_id);
				}
				this.place_gen++;
				this.render_crumbs();
				this.up.visible = !this.level.is_project;
				this.browse.project = this.project;
				this.browse.refresh_folder(this.level);
				this.file_list.load(this.level);
```

#### Remove

```vala
				this.level = this.project;
				this.place_gen++;
				this.render_crumbs();
				this.up.visible = false;
				this.browse.project = this.project;
				this.browse.refresh_folder(this.project);
				this.file_list.load(this.project);
```

#### Replace with

After `this.folder_tree.folders.load.end(res)`. One more indent than the loaded branch.

```vala
					this.level = this.project;
					var open = this.manager.active_file;
					if (open != null &&
						this.folder_tree.folders.id_map.has_key((int) open.parent_id)) {
						this.level = this.folder_tree.folders.id_map.get((int) open.parent_id);
					}
					this.place_gen++;
					this.render_crumbs();
					this.up.visible = !this.level.is_project;
					this.browse.project = this.project;
					this.browse.refresh_folder(this.level);
					this.file_list.load(this.level);
```

### 2. `examples/oc-test-source-diff/FileList.vala` — row factory: mark the open file

**Why:** The highlight has to be paint, not `file_selection`. It is added when that file is chosen, so a later open of the same folder still shows it. `bind` also paints a file that is already `is_active` after a real load.

**Where:** `FileList` constructor, `row_factory.bind`.

**Depends on:** none.

#### Remove

```vala
			row_factory.bind.connect((obj) => {
				var view_row = (Gtk.ColumnViewRow) obj;
				var openable = ((OLLMfiles.File) view_row.item).points_to_id != -1;
				view_row.selectable = openable;
				view_row.activatable = openable;
			});
```

#### Replace with

```vala
			row_factory.bind.connect((obj) => {
				var view_row = (Gtk.ColumnViewRow) obj;
				var shown = (OLLMfiles.File) view_row.item;
				var openable = shown.points_to_id != -1;
				view_row.selectable = openable;
				view_row.activatable = openable;
				view_row.remove_css_class("selector-mark");
				if (shown.is_active) {
					view_row.add_css_class("selector-mark");
				}
				var active_watch = shown.notify["is-active"].connect(() => {
					if (shown.is_active) {
						view_row.add_css_class("selector-mark");
						return;
					}
					view_row.remove_css_class("selector-mark");
				});
				view_row.set_data("active-watch", active_watch);
			});
			row_factory.unbind.connect((obj) => {
				var view_row = (Gtk.ColumnViewRow) obj;
				var shown = (OLLMfiles.File) view_row.item;
				shown.disconnect(view_row.get_data<ulong>("active-watch"));
				view_row.remove_css_class("selector-mark");
			});
```

### 3. `examples/oc-test-source-diff/FileList.vala` — `load`: keep the same folder

**Why:** Opening the sheet on the folder already showing must not fetch the file list again. The rows, including `selector-mark`, stay.

**Where:** `FileList` fields, then the start of `load`, and `clear` forgets the folder. `activate` still calls `load`. The same folder makes that call return.

**Depends on:** section 2.

#### Add

Field on `FileList`, next to `notice`. The grid remembers the folder it is showing.

```vala
		private OLLMfiles.Folder showing_folder;
		private bool showing_kept = false;
```

#### Remove

```vala
		public void load(OLLMfiles.Folder folder)
		{
			this.file_scroll.vadjustment.value = this.file_scroll.vadjustment.lower;
```

#### Replace with

```vala
		public void load(OLLMfiles.Folder folder)
		{
			if (this.showing_kept && this.showing_folder.id == folder.id) {
				return;
			}
			this.showing_kept = true;
			this.showing_folder = folder;
			this.file_scroll.vadjustment.value = this.file_scroll.vadjustment.lower;
```

#### Remove

```vala
		public void clear()
		{
			this.file_scroll.vadjustment.value = this.file_scroll.vadjustment.lower;
```

#### Replace with

```vala
		public void clear()
		{
			this.showing_kept = false;
			this.file_scroll.vadjustment.value = this.file_scroll.vadjustment.lower;
```

## Next

- ✔️ Applied. `ColumnViewRow` in this binding is not a `Gtk.Widget`, so the mark calls `add_css_class` on `(Gtk.Widget) view_row`.
- ✅ 25 Oct. User closed the file sheet.

## Conclusion

- ✅ 🔷 The tablet sheet opens on the open file's folder, marks that file without selecting it, and keeps the file list when that folder is already showing. User closed this bug on 2026-10-25.
