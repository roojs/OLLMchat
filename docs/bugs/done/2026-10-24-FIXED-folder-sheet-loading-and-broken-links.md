# Folder sheet is blank while loading, and a broken link is not marked

**Status:** ✅ User confirmed the folder sheet. Closed 2026-10-24.

## Problem

- 🔷 Choosing a project closes the project list and leaves the screen blank until the folder load finishes. Nothing says it is loading.
- 🔷 The step from the project list to the file sheet is too slow to sit on a blank screen. The file sheet should open as soon as the project is chosen, with a loading indicator until the folders and files are in.
- 🔷 A broken link shows in the file list. `Builder` is one: it is a link to a folder that is not on disk. The row should show the link mark, and the name should be red.

## Evidence

- ℹ️ Tablet, 24 Oct, after the source-diff rebuild. The linked-folder bug is closed: `docs/bugs/done/2026-10-21-FIXED-linked-folders-missing-from-tree.md`. That log recorded `Builder`, `Documents`, and `Ftp` as folder rows with `points_to_id` -1.
- ℹ️ `ProjectSelector.choose` hides the project list, then emits `chosen`. `CoderView` sets `files.project` from that. `FileOverlay` hears `notify["project"]` and calls `activate(OpenReason.PROJECT)`. `examples/oc-test-source-diff/ProjectSelector.vala`, `CoderView.vala`, `FileOverlay.vala`.
- ℹ️ On the tablet, `activate` starts `FolderTreeStore.load` and sets `list.visible` only in the callback, after `fetch_children` returns. Until then the sheet is hidden and the project list is already gone.
- ℹ️ Desktop `activate` sets `list.visible` before the load returns. `FolderTree` already shows a spinner while `FolderTreeStore.loading` is true, and hides the tree until that finishes. The tablet sheet has no spinner.
- ℹ️ `FileBase.css_classes` returns `error` when `points_to_id` is -1. `resources/style.css` colors `label.error` with `@error_color`. `FolderTree` binds `css-classes` onto the name. `libocfiles/FileBase.vala`.
- ℹ️ The tablet folder row is `FolderBrowse.list_box_factory`. A folder with `points_to_id` other than 0 gets the link mark, including -1. The name label is given `body` and `list-chat-title` and does not use `css_classes`, so the red class never reaches it.
- ℹ️ The file grid is `FileList`. The name label binds `path_basename` and `icon_name`. It does not add a link mark and does not bind `css_classes`. `examples/oc-test-source-diff/FileList.vala`.

## Root cause

- ✔️ The blank screen is the tablet sheet. `activate` sets `list.visible` only after `FolderTreeStore.load` returns. `ProjectSelector.choose` has already hidden the project list. Desktop shows the sheet before that load and `FolderTree` already spins while `loading` is true.
- ✅ 24 Oct. User confirmed project loading. The sheet opens at once and shows the loading indicator.
- ✔️ A broken link has `file_count` and `folder_count` of 0, because `points_to` is null. `FolderTree.filter` hides that row while empty folders are hidden, so `Builder` is missing from the folders.
- ✔️ `Folder.fetch_dir` skips a symlink only when `points_to` is a folder. A broken link has no `points_to`, so the same row is sent as a file. The file grid binds `path_basename` and does not use `css_classes`.

## Proposed fix

- 🔷 Show the tablet sheet as soon as the project is chosen. A spinner and ''Loading folders'' cover the panes while `FolderTreeStore.loading` is true. The file grid says ''Loading files'' until its reply.

### `examples/oc-test-source-diff/FileOverlay.vala` — tablet body

**Why:** The sheet has to be on screen during the folder request. The panes stay, at opacity 0, so the spinner has a place to sit.

**Where:** The sheet body, after `place_row`. `activate` for the tablet.

#### Replace with — the sheet body

```vala
			this.list.append(header);
			if (this.form == Form.TABLET) {
				this.list.append(place_row);
				var loading_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
					visible = false,
					halign = Gtk.Align.CENTER,
					valign = Gtk.Align.CENTER,
					can_target = false,
				};
				var spinner = new Gtk.Spinner() {
					width_request = 16,
					height_request = 16,
					valign = Gtk.Align.CENTER,
				};
				loading_row.append(spinner);
				loading_row.append(new Gtk.Label("Loading folders") {
					halign = Gtk.Align.START,
					valign = Gtk.Align.CENTER,
				});
				var body = new Gtk.Overlay() {
					hexpand = true,
					vexpand = true,
					child = this.pages,
				};
				body.add_overlay(loading_row);
				this.folder_tree.folders.notify["loading"].connect(() => {
					spinner.spinning = this.folder_tree.folders.loading;
					loading_row.visible = this.folder_tree.folders.loading;
					this.pages.opacity = this.folder_tree.folders.loading ? 0 : 1;
				});
				this.list.append(body);
			}
			if (this.form != Form.TABLET) {
				this.list.append(this.pages);
			}
```

#### Replace with — tablet `activate`

```vala
			this.list.visible = true;
			if (this.folder_tree.folders.loaded.contains(this.project.path)) {
				this.level = this.project;
				this.place_gen++;
				this.render_crumbs();
				this.up.visible = false;
				this.browse.project = this.project;
				this.browse.refresh_folder(this.project);
				this.file_list.load(this.project);
				this.entry.text = "";
				this.history_epoch++;
				this.load("", this.recent_files, this.recent_list,
					this.history_epoch, Slot.HISTORY);
				return;
			}
			this.folder_tree.folders.load.begin(this.project, (obj, res) => {
				this.folder_tree.folders.load.end(res);
				this.level = this.project;
				this.place_gen++;
				this.render_crumbs();
				this.up.visible = false;
				this.browse.project = this.project;
				this.browse.refresh_folder(this.project);
				this.file_list.load(this.project);
				this.entry.text = "";
				this.history_epoch++;
				this.load("", this.recent_files, this.recent_list,
					this.history_epoch, Slot.HISTORY);
			});
```

### `examples/oc-test-source-diff/FileList.vala` — `load`

**Why:** After the folders arrive, the grid hides its placeholder and waits with nothing on screen.

**Where:** The end of `load`.

#### Replace with

```vala
			this.files.load.begin(folder);
			this.file_empty.label = "Loading files";
			this.file_empty.visible = true;
			this.file_view.visible = true;
```

## Broken link

- 🔷 24 Oct, corrected. A broken link is not a folder. Nothing can be done with it, so the folder list does not show it.
- 🔷 It stays in the file grid, which is the compact list. The name is followed by ''[broken link]'' and is red.
- 🔷 A tap, click, or double click does not select it and does not open it.
- 🚫 Do not keep it in the folder list. The earlier filter exception and the file-grid drop are the wrong way around.

### `examples/oc-test-source-diff/FolderTree.vala` — `filter`

**Why:** The folder list is for folders that can be opened. A broken link cannot.

**Where:** The start of the filter, after the project row is kept.

#### Add

```vala
				if (folder.points_to_id == -1) {
					return false;
				}
```

### `examples/oc-test-source-diff/FileList.vala` — name bind

**Why:** The file grid is where the broken link is shown. The mark and the red name say it is broken.

**Where:** The name factory bind, in place of the `path_basename` binding.

#### Replace with

```vala
				var title = file.path_basename;
				if (file.points_to_id == -1) {
					title = title + " [broken link]";
					name_label.add_css_class("error");
				}
				if (file.points_to_id != -1) {
					name_label.remove_css_class("error");
				}
				name_label.label = title;
```

### `ollmfilesd/Folder.vala` — `fetch_dir`

**Why:** A broken link stays in the file reply. Only a symlink whose target is a folder is left out.

**Where:** The child loop.

#### Replace with

```vala
				if (child.points_to is Folder) {
					continue;
				}
```

## Next

- ✔️ 24 Oct. Applied in `FileOverlay.vala` and `FileList.vala`. Rebuilt and installed on `emulator-5554`.
- ✅ Project loading. User confirmed 24 Oct.
- ✔️ 24 Oct. Filter, red name, and file-grid drop are in the tablet app installed on `emulator-5554`. `Folder.fetch_dir` also skips a broken link. That part needs a filesd restart; the grid drop does not.
- 🚫 The folder-list exception and the file-grid drop. A broken link is a file row.
- ✔️ 24 Oct. Corrected build installed on `emulator-5554`. The folder list drops a broken link. The file grid keeps it, with the link mark and a red name.
- ✅ 24 Oct. User closed the folder sheet. Loading, the broken-link row, and `[broken link]` are done.

## Conclusion

- ✅ 🔷 The sheet opens while a project loads, and a broken link stays in the file grid as `name [broken link]`, not as a folder. User closed this bug on 2026-10-24.
