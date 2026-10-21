# Linked folders missing from the project tree

**Status:** ⏳ applied in the daemon and the smoke tree load. Not yet verified against Web Media Outreach.

## Problem

- 🔷 A folder linked into a project does not appear in the tree, so it cannot be opened.
- 🔷 Prime example: `web.MediaOutreach/Publisher` is a symlink to `web.MediaOutreach.publisher/Publisher`.
- 🔷 Expected: that link shows under Web Media Outreach, and opening it shows the linked folder.
- 🔷 Actual: the tree has no row for it.
- 🔷 `ProjectFiles` is what places a linked folder inside the project. The tree should use that.

## Evidence

- ℹ️ The link on disk is `/home/alan/gitlive/web.MediaOutreach/Publisher` → `../web.MediaOutreach.publisher/Publisher`.
- ℹ️ `ProjectFiles.handle_file_alias` follows a folder alias. The target goes into `folder_map`. The alias goes into `all_files` at `web.MediaOutreach/Publisher`. That alias's parent is the Web Media Outreach folder.
- ℹ️ The target's own `parent_id` stays the real parent, `web.MediaOutreach.publisher`. `ProjectFiles` does not rewrite that on the live folder. The other project still owns it.
- ℹ️ `Folder.fetch_children` sends the `folder_map` row and copies that outside `parent_id`.
- ℹ️ `FolderTreeStore.load` skips a row whose `parent_id` is not already in `id_map`. The outside parent is not in the map, so the row `ProjectFiles` included is dropped.
- ℹ️ Children of `Publisher` have real paths under `web.MediaOutreach.publisher`. The load loop sorts by that path and skips a row it sees before its parent is in the map. It does not come back to them.
- 🚫 The real `parent` chain is the wrong one to walk. It leaves the mapped project. The in-project parent is the alias parent `ProjectFiles` already followed.

## Root cause

- ✔️ `ProjectFiles` already contains the linked folder. `fetch_children` sends the real parent id, and the tree drops the row because that parent is outside the project.

## Proposed fix

- 🔷 A linked file or folder keeps its real `path` on the row that goes down the wire.
- 🔷 That row's `parent_id` is the alias's parent, the folder where the link sits in this project.
- 🔷 The live object is left alone. `build_tree_structure` still attaches it to its real parent. The other project still owns that parent.
- 🔷 `ProjectFiles` already holds the alias, with `parent_id` and `points_to`. It records `link_parent` then, target id to that parent id. A fetch only calls `has_key` and `get`.
- 🚫 No flag. The row path is the real path. The parent path is where the link sits. The consumer sees that the row path does not start with the parent path.
- 🚫 `fetch_dir` does not rewrite `parent_id`. Those files already parent to the folder being listed.
- ℹ️ A name search still returns folder ids, not rows. Nothing on that reply has a parent to replace.
- ✔️ Applied in `ollmfilesd/ProjectFiles.vala`, `ollmfilesd/Folder.vala`, and `examples/oc-test-source-diff/FolderTreeStore.vala`.

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

`Publisher` then goes out with `path` still `web.MediaOutreach.publisher/Publisher` and `parent_id` the Web Media Outreach folder. That path does not start with the parent path. A folder inside `Publisher` keeps `parent_id` pointing at `Publisher`. Its path does start with that folder's path.

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

**Why:** `Publisher` sorts before the project folders because its real path is `web.MediaOutreach.publisher`. Its children sort before `Publisher` itself. One list holds the rows whose parent is not in the map yet. An offset walks that list, and goes back to zero when it passes the end. The walk does not yield. `load_epoch` is already checked when the reply arrives, and it cannot change until this method yields again.

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

## Next

- ⏳ After the wire parent is the alias parent, crumb walking follows that parent and stops at the mapped project. That is a separate edit. `is_project` is still the wrong stop.
