# Linked folders missing from the project tree

**Status:** ⏳ The link can show. Opening one still shows none of the files or folders inside it.

## Problem

- 🔷 A folder linked into a project does not appear in the tree, so it cannot be opened.
- 🔷 Prime example: a project folder is a symlink to a directory outside that project.
- 🔷 Expected: that link shows under the project, and opening it shows the linked folder.
- 🔷 Actual: the tree has no row for it. Confirmed again on the Pixel Tablet emulator after the 2026-10-21 21:13 source-diff APK.
- 🔷 `ProjectFiles` is what places a linked folder inside the project. The tree should use that.
- 🔷 22 Oct, on the tablet: the link row can show, and opening it lists that folder.
- 🔷 Two names in the project are the same link. One points at the other. Missing one of that pair is acceptable.
- 🔷 Opening another linked folder shows the folder and none of the files or folders inside the linked directory.
- 🚫 Do not name the outside projects, or list what is inside these links.
- ℹ️ The path of the link is not a folder on the server. The real directory is. A folder listing of that real directory returns the files. The tree reply includes that directory under the folder that holds the link.

## What the server sends for one folder

- ℹ️ This is the project folder that holds the links, from `Folder.fetch_children` (the tree) and `Folder.fetch_dir` (the file list). Skip scan, copy of the file index. The outside project name is not written here.
- ℹ️ A folder link is not an alias row in the tree. The row is the outside directory. Its `parent-id` is this folder. The name is the outside directory's basename, not the link's name.
- ℹ️ The file list is files only. A link to a folder is not a file-list row.

```text
tree, Folder.fetch_children
Pman                          folder, inside the project
├── Admin                     folder, outside, row is Pman.Admin, 6 child folders
├── Ai                        missing, alias to a folder
├── BAdmin                    folder, outside, row is Pman.BAdmin, 1 child folder
├── Builder                   missing, alias to a folder
├── Cash                      folder, outside, row is Pman.Cash, 7 child folders
├── Clipping                  folder, inside, 11 child folders
├── Cms                       folder, outside, row is Pman.Cms, 10 child folders
├── CmsMigrate                folder, inside, no child folders
├── Core                      folder, outside, row is Pman.Core, 15 child folders
├── Crm                       folder, outside, row is Pman.Crm, 11 child folders
├── Documents                 missing, alias to a folder
├── Ftp                       missing, alias to a folder
├── Mail                      folder, outside, row is Pman.Mail, 7 child folders
├── (one other real folder)   folder, inside, 3 child folders
├── PressRelease              folder, inside, 19 child folders
└── templates                 folder, outside, 1 child folder
```

```text
file list, Folder.fetch_dir
├── I18n.php                  alias to a file
├── Images.php                alias to a file
├── Login.php                 alias to a file
└── Roo.php                   alias to a file
```

- ℹ️ `Mail`'s 7 child folders are in the tree reply. Their names are not recorded here.

## Evidence

- ℹ️ The link on disk points at a directory outside the project.
- ℹ️ `ProjectFiles.handle_file_alias` follows a folder alias. The target goes into `folder_map`. The alias goes into `all_files` at the path of the link. That alias's parent is the project folder where the link sits.
- ℹ️ The target's own `parent_id` stays the real parent, outside this project. `ProjectFiles` does not rewrite that on the live folder. The other project still owns it.
- ℹ️ `Folder.fetch_children` sends the `folder_map` row and copies that outside `parent_id`.
- ℹ️ `FolderTreeStore.load` skips a row whose `parent_id` is not already in `id_map`. The outside parent is not in the map, so the row `ProjectFiles` included is dropped.
- ℹ️ Children of the linked folder have real paths outside the project. The load loop sorts by that path and skips a row it sees before its parent is in the map. It does not come back to them.
- 🚫 The real `parent` chain is the wrong one to walk. It leaves the mapped project. The in-project parent is the alias parent `ProjectFiles` already followed.
- ℹ️ 2026-10-21 tablet run: `adb -s emulator-5554` installed `.pixiewood/oc-test-source-diff-arm64-v8a-debug.apk` and started `org.roojs.ollmchat.sourcediff`. The host process was `/usr/bin/ollmfilesd`. That binary was not rebuilt from this tree.
- 💩 The tablet still missing the link matches an old daemon on the wire. It does not show that the `link_parent` copy is wrong, and it does not show that the copy is right. No reply from that session was captured.
- ✔️ 23:35, this tree's `build/ollmfilesd/ollmfilesd` (the binary that contains `link_parent`). `OLLMFILES_IS_TEST=1`, a copy of the file index, skip scan, then `Folder.fetch_children` for the project. Activate replied `ok`. `fetch_children` replied `msg=95`.
- ✔️ None of those 95 paths is the linked folder. The rows under the project are the project's own folders.
- ℹ️ The alias row is `base_type` `fa`. Its `points_to_id` is the outside directory. That directory's `parent_id` is 0.
- ✔️ `FileAlias` extends `File`. `update_from_recursive` checks `child is File` and `continue`s. The `child is FileAlias` branch is the only call to `handle_file_alias`. That branch does not run. `link_parent` stays empty, and the target never enters `folder_map`. `fetch_children` has nothing to reparent.

## Root cause

- ✔️ The linked folder is not in the reply. `handle_file_alias` is unreachable, so `folder_map` never receives the target and `link_parent` is never filled. The parent rewrite only matters after that follow runs. The real parent id on the target is still the wrong parent to send once the row exists.

## Proposed fix

- 🔷 A linked file or folder keeps its real `path` on the row that goes down the wire.
- 🔷 That row's `parent_id` is the alias's parent, the folder where the link sits in this project.
- 🔷 The live object is left alone. `build_tree_structure` still attaches it to its real parent. The other project still owns that parent.
- 🔷 `ProjectFiles` already holds the alias, with `parent_id` and `points_to`. It records `link_parent` then, target id to that parent id. A fetch only calls `has_key` and `get`.
- 🚫 No flag. The row path is the real path. The parent path is where the link sits. The consumer sees that the row path does not start with the parent path.
- 🚫 `fetch_dir` does not rewrite `parent_id`. Those files already parent to the folder being listed.
- ℹ️ A name search still returns folder ids, not rows. Nothing on that reply has a parent to replace.
- ✔️ Applied in `ollmfilesd/ProjectFiles.vala`, `ollmfilesd/Folder.vala`, and `examples/oc-test-source-diff/FolderTreeStore.vala`.
- 🔷 `update_from_recursive` has to match `FileAlias` before `File`. `FileAlias` is a `File`, so the first check swallows the alias.

### `ollmfilesd/ProjectFiles.vala` — `update_from_recursive` checks the alias first

**Why:** `handle_file_alias` is what puts the target in `folder_map` and what records `link_parent`. It is only called from the `FileAlias` branch. That branch sits after `child is File`, and a `FileAlias` is a `File`, so the follow never happens.

**Where:** The child loop in `update_from_recursive`.

#### Remove

```vala
				// Handle File objects - add real files to project_files
				if (child is File) {
					var file = child as File;
					// Add all files to all_files (even non-text files)
					this.all_files.set(file.path, file);
				 
					// Only add text files to ProjectFile list (via add_file_if_new)
					// GLib.debug("DEBUG update_from_recursive: child is File (not FileAlias)");
					this.add_file_if_new(
						file,
						project_folder,
						found_files,
						symlink_path);
					continue;
				}
				
				// Handle FileAlias - follow to the real file
				if (child is FileAlias) {
					// GLib.debug("DEBUG update_from_recursive: child is FileAlias");
					// Add FileAlias to all_files (symlinks are included in all_files)
					this.all_files.set(child.path, child);
					this.handle_file_alias(
						child as FileAlias,
						project_folder,
						scanned_folders,
						found_files,
						found_folders,
						symlink_path);
					continue;
				}
```

#### Replace with

```vala
				// FileAlias is a File. This check has to come first.
				if (child is FileAlias) {
					this.all_files.set(child.path, child);
					this.handle_file_alias(
						child as FileAlias,
						project_folder,
						scanned_folders,
						found_files,
						found_folders,
						symlink_path);
					continue;
				}

				if (child is File) {
					var file = child as File;
					this.all_files.set(file.path, file);
					this.add_file_if_new(
						file,
						project_folder,
						found_files,
						symlink_path);
					continue;
				}
```

### `ollmfilesd/ProjectFiles.vala` — `link_parent` filled while the project is built

**Why:** `folder_map` is keyed by path. `all_files` is keyed by path. The alias already stores `parent_id` and `points_to`. Nothing stores the reverse, target id to that alias. `load_files_from_db` builds an id map and drops it when the tree is done.

**Where:** Next to `folder_map`. Cleared where `folder_map` and `all_files` are cleared in `update_from`. Set at the start of `handle_file_alias` once `points_to` is in hand.

#### Add — after the `folder_map` property

```vala
		/**
		 * Target id to the parent id of the alias that linked it
		 * into this project.
		 */
		public Gee.HashMap<int, int> link_parent { get; private set;
			default = new Gee.HashMap<int, int>(); }
```

#### Remove

```vala
			this.folder_map.clear();
			this.all_files.clear();
```

#### Replace with

```vala
			this.folder_map.clear();
			this.link_parent.clear();
			this.all_files.clear();
```

#### Remove

```vala
			var target = alias.points_to;
```

#### Replace with

```vala
			var target = alias.points_to;
			this.link_parent.set((int) target.id, (int) alias.parent_id);
```

### `ollmfilesd/Folder.vala` — `fetch_children`

**Why:** This is the tree the client builds. The copy parents a linked folder from `link_parent`. It does not walk the project.

**Where:** The loop that copies each `folder_map` row into the reply. `project` is the project `fetch_children` already resolved.

#### Remove

```vala
			var list = new Gee.ArrayList<GLib.Object>();
			foreach (var next in rows) {
				var row = new Folder(this.manager);
				row.copy_from(next, {
					"manager", "children", "project-files", "parent",
					"points-to", "buffer"
				});
				list.add(row);
			}
```

#### Replace with

```vala
			var list = new Gee.ArrayList<GLib.Object>();
			foreach (var next in rows) {
				var row = new Folder(this.manager);
				row.copy_from(next, {
					"manager", "children", "project-files", "parent",
					"points-to", "buffer"
				});
				if (project.project_files.link_parent.has_key((int) row.id)) {
					row.parent_id = project.project_files.link_parent.get((int) row.id);
				}
				list.add(row);
			}
```

The linked folder then goes out with its real path and `parent_id` set to the folder where the link sits. That path does not start with the parent path. A folder inside the link keeps `parent_id` pointing at the linked folder. Its path does start with that folder's path.

### `ollmfilesd/Folder.vala` — `fetch_files_reply`

**Why:** A file page and a path batch send file rows. A file reached through a link has the same real path and the same outside parent as a linked folder.

**Where:** The path-batch copy and the empty-query page. Both use `link_parent` on `project.project_files`. The name-search reply stays as it is.

#### Remove

```vala
					var row = new File(this.manager);
					row.copy_from(source, {
						"manager",
						"buffer",
						"parent",
						"last-modified"
					});
					list.add(row);
```

#### Replace with

```vala
					var row = new File(this.manager);
					row.copy_from(source, {
						"manager",
						"buffer",
						"parent",
						"last-modified"
					});
					if (project.project_files.link_parent.has_key((int) row.id)) {
						row.parent_id = project.project_files.link_parent.get((int) row.id);
					}
					list.add(row);
```

#### Remove

```vala
				if (matched.size > 0) {
					list.add_all(matched.slice(0, int.min(limit, matched.size)));
				}
```

#### Replace with

```vala
				var take = int.min(limit, matched.size);
				for (var i = 0; i < take; i++) {
					var source = matched.get(i);
					if (!project.project_files.link_parent.has_key((int) source.id)) {
						list.add(source);
						continue;
					}
					var row = new File(this.manager);
					row.copy_from(source, {
						"manager", "buffer", "parent", "points-to"
					});
					row.parent_id = project.project_files.link_parent.get((int) row.id);
					list.add(row);
				}
```

A file already inside the project is still the live object. A linked file is a copy, so `parent_id` on that copy is the alias parent and the stored row is unchanged.

### `examples/oc-test-source-diff/FolderTreeStore.vala` — `load`

**Why:** The linked folder sorts before the project folders because its real path is outside the project. Its children sort before the linked folder itself. One list holds the rows whose parent is not in the map yet. An offset walks that list, and goes back to zero when it passes the end. The walk does not yield. `load_epoch` is already checked when the reply arrives, and it cannot change until this method yields again.

**Where:** The loop after `rows.sort` that calls `append`.

#### Remove

```vala
				for (var i = 0; i < rows.size; i++) {
					if (epoch != this.load_epoch) {
						break;
					}
					var row = rows.get(i);
					if (row.path == "" || row.path == folder.path) {
						continue;
					}
					if (!this.id_map.has_key((int) row.parent_id)) {
						continue;
					}
					row.manager = folder.manager;
					this.append(this.id_map.get((int) row.parent_id), row);
				}
```

#### Replace with

```vala
				var waiting = new Gee.ArrayList<OLLMfiles.Folder>();
				for (var i = 0; i < rows.size; i++) {
					var row = rows.get(i);
					if (row.path == "" || row.path == folder.path) {
						continue;
					}
					if (!this.id_map.has_key((int) row.parent_id)) {
						waiting.add(row);
						continue;
					}
					row.manager = folder.manager;
					this.append(this.id_map.get((int) row.parent_id), row);
				}
				var offset = 0;
				var skipped = 0;
				while (waiting.size > 0) {
					if (offset >= waiting.size) {
						offset = 0;
					}
					if (skipped >= waiting.size) {
						break;
					}
					var row = waiting.get(offset);
					if (!this.id_map.has_key((int) row.parent_id)) {
						offset++;
						skipped++;
						continue;
					}
					row.manager = folder.manager;
					this.append(this.id_map.get((int) row.parent_id), row);
					waiting.remove_at(offset);
					skipped = 0;
				}
```

## Attempts

- ✔️ 22 Oct 08:18 build, then `/usr/bin/ollmfilesd` (copied 08:51, different checksum, same size). Same script as the 95-row run, skip scan, database copy. `fetch_children` replied `msg=603`. The linked folder is in the reply, with `parent-id` set to the project folder.
- ✔️ 09:13 Pixel Tablet, `org.roojs.ollmchat.sourcediff`. The link is in the tree. Opening it shows the linked folder's own files and folders. The names of those are not recorded here.

## Next

- ⏳ 🔷 Opening the linked folder that still shows empty still has to list the files and folders inside the link. The pair of names for one link can lose one side.
- ℹ️ The path bar that follows that parent is closed: `docs/bugs/done/2026-10-21-FIXED-tablet-path-bar-not-rendering.md`.
