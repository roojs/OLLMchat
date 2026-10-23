# Linked folders missing from the project tree

**Status:** ⏳ A link is hidden until empty folders are shown, and opening it lists nothing of the target. The second line under a link is the target path.

## Problem

- 🔷 A folder linked into a project shows under the project, and opening it shows the linked folder.
- ✔️ 22 Oct, on the tablet: one link row can show, and opening it lists that folder.
- 🔷 Opening another linked folder shows the folder and none of the files or folders inside it.
- 🔷 Two names in the project are the same link. One points at the other. Missing one of that pair is acceptable.
  - A name inside `Pman`, such as `Ai`, links to `Pman.Ai` on the parent of `Pman`. That parent link points again at the outside `Pman.Ai`.
  - Those inner folders used to be sub-repositories checked out in the project. They moved to a flat list of repositories outside, and the inner names were linked through to those.
  - The link on the parent is the top-level exposure for the public repository, so you can see what this project uses.
- 🔷 The returned tree points at the final solid folder. The chain is followed through. The row is the link. Its path is that link, so the name is the basename (`Admin`). `points_to` is the solid folder (`Pman.Admin`). Opening it lists that folder, the way a desktop does. The render tree does not need the hops in between.
- 🔷 `Builder`, `Documents`, and `Ftp` are links whose target folders are not on disk. They are not projects. A broken link still shows in the tree, in red. Its name is the link. `points_to_id` is -1.
- 🔷 The file list is files only. A link to a folder is not a file-list row.
- 🔷 Showing empty folders reveals the links. Opening one shows an empty folder. The target has files and folders.
- 🔷 The left folder list does not merge a folder icon with a link icon. The second line under a link is the real path, so the row shows where it points.
- 🚫 Do not name the outside projects, or list what is inside these links.

## Reply we expect

- 🔷 `Folder.fetch_children` for this folder returns one flat list. A real folder inside the project stays as it is. A link is the alias row: its path is the link, so the name is the basename, and `points_to` is the solid folder on that same row. `parent_id` is the folder where the kept link sits, and that folder's own children follow it. A broken link is the alias with `points_to` empty and `points_to_id` -1. One name of a pair is enough. No row is an intermediate hop.

```text
expected, Folder.fetch_children
Pman                          folder, inside the project
├── Admin                     basename Admin, target is the Pman.Admin folder
├── Ai                        basename Ai, target is the Pman.Ai folder, or the other name of this pair
├── BAdmin                    basename BAdmin, target is the Pman.BAdmin folder
├── Builder                   basename Builder, points_to_id -1
├── Cash                      basename Cash, target is the Pman.Cash folder
├── Clipping                  folder, inside
├── Cms                       basename Cms, target is the Pman.Cms folder
├── CmsMigrate                folder, inside
├── Core                      basename Core, target is the Pman.Core folder
├── Crm                       basename Crm, target is the Pman.Crm folder
├── Documents                 basename Documents, points_to_id -1
├── Ftp                       basename Ftp, points_to_id -1
├── Mail                      basename Mail, target is the Pman.Mail folder
├── (one other real folder)   folder, inside
├── PressRelease              folder, inside
└── templates                 basename templates, target is that folder
```

## What the server sends now

- ℹ️ 23 Oct. Installed `/usr/bin/ollmfilesd`, the existing `--rpc-script` harness, skip scan, copy of the file index. 624 rows. The outside project name is not written here.
- ℹ️ A link row is the alias. `path` is the link, so the basename is `Admin`. `points-to` is the nested solid folder. A null `points-to` is omitted. `Builder`, `Documents`, and `Ftp` are in the reply with `points-to-id` -1.
- ℹ️ The solid folder is not also a row. Its child folders stay in the list, and their `parent-id` is the alias. `Ai` is the kept name of that pair, and no child folders came back under it. File aliases such as `I18n.php` are not in this list.

```text
tree, Folder.fetch_children
Pman                          folder, inside the project
├── Admin                     basename Admin, target Pman.Admin, 6 child folders
├── Ai                        basename Ai, target Pman.Ai, no child folders
├── BAdmin                    basename BAdmin, target Pman.BAdmin, 1 child folder
├── Builder                   basename Builder, points_to_id -1
├── Cash                      basename Cash, target Pman.Cash, 7 child folders
├── Clipping                  folder, inside, 11 child folders
├── Cms                       basename Cms, target Pman.Cms, 10 child folders
├── CmsMigrate                folder, inside, no child folders
├── Core                      basename Core, target Pman.Core, 15 child folders
├── Crm                       basename Crm, target Pman.Crm, 11 child folders
├── Documents                 basename Documents, points_to_id -1
├── Ftp                       basename Ftp, points_to_id -1
├── Mail                      basename Mail, target Pman.Mail, 7 child folders
├── (one other real folder)   folder, inside, 3 child folders
├── PressRelease              folder, inside, 21 child folders
└── templates                 basename templates, target that folder, 1 child folder
```

```text
file list, Folder.fetch_dir
├── I18n.php                  alias to a file
├── Images.php                alias to a file
├── Login.php                 alias to a file
└── Roo.php                   alias to a file
```

- ℹ️ `Mail`'s 7 child folders are in the tree reply. Their names are not recorded here. The path of the link is not a folder on the server. A folder listing of the real directory returns the files.
- ℹ️ `Ai` is the inner link. It points at `Pman.Ai` beside `Pman`, and that link points at the outside folder. The reply kept this name. The other name of the pair is not a row.

## Applied

- ✔️ `FileAlias` was checked after `File`. A `FileAlias` is a `File`, so `handle_file_alias` never ran and the linked folder never entered `folder_map`. `update_from_recursive` now matches `FileAlias` first. Before that change a project fetch returned 95 rows and none was the linked folder. After it, the same fetch returned 603 rows and the linked folder was in the reply.
- ✔️ `ProjectFiles.link_parent` maps a target id to the alias's parent id. `Folder.fetch_children` copies the `folder_map` row and sets `parent_id` from that map. The live folder keeps its real parent. `fetch_files_reply` does the same for a linked file. `fetch_dir` does not rewrite `parent_id`.
- ✔️ `FolderTreeStore.load` keeps rows whose parent is not in the map yet and appends them once that parent arrives. The outside parent is not the parent to walk.
- ✔️ 22 Oct 08:18 build, then `/usr/bin/ollmfilesd` (copied 08:51). 09:13 Pixel Tablet: the link is in the tree, and opening it shows that folder's own files and folders.
- 🚫 No flag on the row. The applied reply still sends the solid folder as `path`, so the basename is `Pman.Admin`.

## Proposed fix

- 🔷 The link row is the alias. `path` is the link, so the name is the basename. `points_to` on that row is the solid folder, nested. `parent_id` is the folder where the kept link sits.
- 🔷 A broken link is the same kind of row. `points_to` is empty. `points_to_id` is -1.
- 🚫 No `display_name`, and no second map of paths. The alias already has `path` and `points_to`.
- ℹ️ The bin writer already writes an object property as a nested object. `fetch_children` copies the target folder and the copy drops `points-to`, so neither the alias nor the nested folder is in the reply.
- ℹ️ The list is one type, taken from the first row, which is a `Folder`. Each later row is built as that type. Adding the `FileAlias` writes file properties the `Folder` reader does not have. A `Folder` constructor takes the alias `path` and `points_to`, and the file properties stay off the wire.
- ℹ️ One alias of a pair wins, the one `link_parent` kept. The solid folder is not also sent as its own row. Its children stay in the list. Their `parent_id` is `points_to.id`, so the tree attaches them to the alias row.
- 🚫 No new flag. -1 is the existing `points_to_id`. A null `points_to` is already omitted on the wire.

### `ollmfilesd/Folder.vala` — `fetch_children`

**Why:** The reply sends the folder the alias points at, with `points-to` removed. The alias path never leaves the server. A missing target never enters `folder_map`.

**Where:** The loop that copies each `folder_map` row. Skip a folder that is a link target. Add the alias, with `points_to` set, in its place. `project` is the project `fetch_children` already resolved.

#### Remove

```vala
				row.copy_from(next, {
					"manager", "children", "project-files", "parent",
					"points-to", "buffer"
				});
				if (project.project_files.link_parent.has_key((int) row.id)) {
					row.parent_id = project.project_files.link_parent.get((int) row.id);
				}
				list.add(row);
```

#### Replace with

```vala
				row.copy_from(next, {
					"manager", "children", "project-files", "parent",
					"points-to", "buffer"
				});
				// The alias row stands in for this solid folder.
				if (project.project_files.link_parent.has_key((int) row.id)) {
					continue;
				}
				list.add(row);
```

#### Add — after that loop, before `request.reply`

```vala
			if (project != null) {
				foreach (var item in project.project_files.all_files.values) {
					// File rows and a removed alias are not tree rows.
					if (!(item is FileAlias) || item.delete_id != 0) {
						continue;
					}
					// A resolved alias is sent only for the one
					// link_parent kept. points_to_id -1 is a broken
					// link and has no entry there.
					if (item.points_to_id != -1 &&
						(!project.project_files.link_parent.has_key((int) item.points_to_id) ||
						project.project_files.link_parent.get((int) item.points_to_id) != (int) item.parent_id)) {
						continue;
					}
					// A fetch of one folder only includes a link inside it.
					if (!folder.is_project && !item.path.has_prefix(folder.path + "/")) {
						continue;
					}
					// The list is decoded as Folder. Build one with the
					// alias path and points_to. File properties stay off.
					var link = new Folder(this.manager) {
						id = item.id,
						path = item.path,
						parent_id = item.parent_id,
						points_to_id = item.points_to_id,
						points_to = item.points_to
					};
					list.add(link);
				}
				// A child of the solid folder is parented at that
				// folder. Hang it off the alias row.
				foreach (var row in list) {
					var child = row as Folder;
					if (child == null || child.points_to_id == -1) {
						continue;
					}
					foreach (var other in list) {
						var link = other as Folder;
						if (link == null || link.points_to_id != child.parent_id) {
							continue;
						}
						child.parent_id = link.id;
						break;
					}
				}
			}
```

The tree already attaches a row by `parent_id`. After this, a child of the solid folder hangs off the alias. `FolderTreeStore.load` still drops `points-to` when it copies the requested folder onto a row it already has. The nested folder has to survive that copy.

### `libocfiles/FileBase.vala` — a broken link is red

**Why:** `points_to_id` -1 is on the row. `css_classes` is computed on the client. A folder with no files is grey. A broken link uses GTK's `error` class, which this app's stylesheet colors red.

**Where:** The start of the `css_classes` getter. `resources/style.css`.

#### Add — at the start of the getter, before the `is_show_empty` check

```vala
				if (this.points_to_id == -1) {
					string[] broken = { "error" };
					return broken;
				}
```

#### Add — `resources/style.css`

```css
label.error {
  color: @error_color;
}
```

## Still open

- ✔️ 23 Oct, tablet, after reload. With empty folders hidden, `Pman` shows the four real folders. Showing empty folders reveals the links. Opening one does not list the target.
- ✔️ The alias row is built with `file_count` and `folder_count` left at 0. Those counts stay on `points_to`. The left list hides a row while empty folders are hidden when both counts are 0. `Folder.fetch_dir` of the link path is not a folder row, so the file list is empty.
- 🚫 A hybrid folder-and-link icon. The second line is the target path.

### `ollmfilesd/Folder.vala` — counts on the alias

**Why:** The link is sent as an empty folder. The file list already has `points_to` on that row, so it asks `fetch_dir` for the solid folder. No walk of the projects.

**Where:** The `Folder` built for the alias in `fetch_children`. `FileListStore.load` chooses the path.

#### Replace with — the alias `Folder`

```vala
					var link = new Folder(this.manager) {
						id = item.id,
						path = item.path,
						parent_id = item.parent_id,
						points_to_id = item.points_to_id,
						points_to = item.points_to,
						file_count = item.points_to == null ? 0 : item.points_to.file_count,
						folder_count = item.points_to == null ? 0 : item.points_to.folder_count,
						document_count = item.points_to == null ? 0 : item.points_to.document_count,
						code_count = item.points_to == null ? 0 : item.points_to.code_count
					};
```

### `examples/oc-test-source-diff/FileListStore.vala` — list the solid folder

**Why:** `fetch_dir` looks up a folder by path. The link path is not that folder. The row already holds the target.

**Where:** `load`, the path passed to `Folder.fetch_dir`.

#### Add — before the request

```vala
			var list_path = folder.path;
			if (folder.points_to is OLLMfiles.Folder) {
				list_path = folder.points_to.path;
			}
```

#### Replace with — the request argument

```vala
					args = OLLMrpc.args("s", list_path)
```

### `examples/oc-test-source-diff/FolderBrowse.vala` — second line

**Why:** The second line is the row path. For a link that is `Pman/Admin`, which does not say where it points.

**Where:** `list_box_factory`, the path used for the second line.

#### Add — before the project-prefix trim

```vala
			if (item.points_to != null && item.points_to.path != "") {
				rel = item.points_to.path;
			}
```

## Next

- ✔️ Applied in `ollmfilesd/Folder.vala` and `FolderBrowse.vala`. The daemon has to be rebuilt and restarted before the counts and the file list change. The second line is in the tablet app, so that app has to be rebuilt and installed.
- ⏳ 🔷 The pair of names for one link can lose one side. A broken link stays empty, and red still needs the rebuilt app.
- ✔️ 23 Oct, installed `/usr/bin/ollmfilesd`. `Folder.fetch_children` for this project returns the alias row. The name is the basename of the link. `points-to` is the solid folder. `Builder`, `Documents`, and `Ftp` have `points-to-id` -1.
- ℹ️ The path bar that follows that parent is closed: `docs/bugs/done/2026-10-21-FIXED-tablet-path-bar-not-rendering.md`.
