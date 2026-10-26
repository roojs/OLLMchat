# Opening Pman.Admin leaves the file pane on Loading

**Status:** 🚫 CLOSED. Applied in `ollmfilesd/Folder.vala`. Not verified. `/usr/bin/ollmfilesd` is still the binary that crashed, and the tablet was not opened again.

## Problem

- 🔷 25 Oct, Pixel Tablet `emulator-5556`, source-diff app. A few folder browses, then Pman.Admin. The right-hand file pane stays on loading.
- 🔷 Expected: the file list for that folder appears.
- ℹ️ Separate from `docs/bugs/done/2026-10-24-CLOSED-folder-load-slow.md`. That stall is the tablet applying a large `fetch_children` reply. This one never gets a reply.

## Evidence

- ✔️ Tablet `org.roojs.ollmchat.sourcediff` pid 26119, GTK thread 26169. Logcat folder rebinds at 09:20:56, 09:21:23, 09:21:43, 09:21:52, 09:22:14. No later app line. Every thread is sleeping. The GTK thread is not spinning.
- ✔️ `ollmfilesd` pid 114818 SIGSEGV at 09:22:12. Core is present (36.7M). systemd restarted the unit at 09:22:15, new pid 141078. `~/.cache/ollmchat/ollmfilesd.debug.log` was replaced by that start and only has the listen lines. The pre-crash debug lines are gone.
- ✔️ The faulting request is `Folder.fetch_children` with path `/home/alan/gitlive/Pman.Admin`. Frame 0 is `ollmfilesd/Folder.vala:314`. `project` is null. `folder` is the folder `get_folder_at_path` returned for that path.
- ✔️ Line 292 sets `project` from `folder.is_project`, otherwise `find_project_root()`. The null pointer means that folder is not a project and no parent is a project. Line 295 guards the folder-map walk. Line 314 uses `project.project_files` after that guard has ended.
- ✔️ Journal just before the crash is `g_file_info_get_size` / `GFileInfo created without standard::size`. That is the known scan critical. The process then dies in `fetch_children`, not in the scan.
- ✔️ After the restart nothing is connected to port 8422. The tablet did not open a new session. `FileList.load` sets the label to "Loading files" and leaves it there until `Folder.fetch_dir` returns. On the tablet that call is made from the `fetch_children` callback in `FileOverlay.activate`. The callback never runs.
- ✔️ `files.sqlite`, three live rows for `/home/alan/gitlive/Pman.Admin`. id 16 is `is_project=1`. ids 1662 and 3444 are `is_project=0` with `parent_id` 0. The alias `/home/alan/gitlive/web.MediaOutreach/Pman.Admin` (id 1663) points at 1662.
- ℹ️ `ProjectManager.get_folder_at_path` returns the first `folder_map` hit and does not look at `path_map`. That hit is 1662. `find_project_root` walks a null parent and returns null. id 16 is the project `path_map` holds.

## Root cause

- ✔️ The file pane is waiting because `ollmfilesd` crashed while answering `Folder.fetch_children` for `/home/alan/gitlive/Pman.Admin`. The UI thread is idle.
- ✔️ `fetch_children` dereferences `project` when `get_folder_at_path` returned a non-project folder whose parents are not a project. That is this path: the link target stored inside another project's map.

## Proposed fix

- 🔷 `fetch_children` and `fetch_dir` use the `path_map` project when this path is a project. The link-target copy of the same path stays unused.
- 🔷 The copy loop in `fetch_children` reads `link_parent` only when a project was resolved. A folder with no project still gets a reply of that one folder.

### `ollmfilesd/Folder.vala` — `fetch_children` project path

**Why:** `get_folder_at_path` returns id 1662. id 16 is the project. The tree and the later file list have to be built from id 16.

**Where:** The docblock, then the lookup at the start of `fetch_children`, before the missing-folder reply.

**Depends on:** none.

#### Remove

```vala
		 * set to that folder. Files are left out.
		 * ''path'' is the first row. A deleted folder is left out.
```

#### Replace with

```vala
		 * set to that folder. Files are left out.
		 * A path that is a project uses that project. The same path
		 * stored under another project is not used.
		 * ''path'' is the first row. A deleted folder is left out.
```

#### Remove

```vala
			var folder = this.manager.get_folder_at_path(path);
			if (folder == null) {
```

#### Replace with

```vala
			var folder = this.manager.get_folder_at_path(path);
			if (this.manager.projects.path_map.has_key(path)) {
				folder = this.manager.projects.path_map.get(path);
			}
			if (folder == null) {
```

### `ollmfilesd/Folder.vala` — `fetch_children` link target

**Why:** Line 314 reads `project.project_files` after the `project != null` walk has ended. The core has `project` null for this path. With no project, the reply is the one folder already in `rows`.

**Where:** The copy loop, the `link_parent` test.

**Depends on:** the project-path lookup above.

#### Remove

```vala
				// The alias row stands in for this solid folder.
				if (project.project_files.link_parent.has_key((int) row.id)) {
					continue;
				}
```

#### Replace with

```vala
				// The alias row stands in for this solid folder.
				if (project != null &&
					project.project_files.link_parent.has_key((int) row.id)) {
					continue;
				}
```

### `ollmfilesd/Folder.vala` — `fetch_dir` project path

**Why:** The tablet file pane calls `fetch_dir` with the same path after `fetch_children` returns. That lookup has the same `folder_map` hit, so the file list would be the link-target copy.

**Where:** The docblock, then the lookup at the start of `fetch_dir`, before the missing-folder reply.

**Depends on:** none.

#### Remove

```vala
		 * A symlink to a file is kept. Each row is a copy of the
		 * stored file. Nothing here reads the filesystem. A link is
		 * opened by passing the solid folder's path.
```

#### Replace with

```vala
		 * A symlink to a file is kept. Each row is a copy of the
		 * stored file. Nothing here reads the filesystem. A link is
		 * opened by passing the solid folder's path. A path that is
		 * a project uses that project.
```

#### Remove

```vala
			var folder = this.manager.get_folder_at_path(path);
			if (folder == null) {
```

#### Replace with

```vala
			var folder = this.manager.get_folder_at_path(path);
			if (this.manager.projects.path_map.has_key(path)) {
				folder = this.manager.projects.path_map.get(path);
			}
			if (folder == null) {
```

## Attempts

- ✔️ Applied the three hunks in `ollmfilesd/Folder.vala`. `fetch_children` and `fetch_dir` prefer `path_map`. The copy loop skips `link_parent` when `project` is null.

## Conclusion

- 🚫 Not treated as fixed. The source has the `path_map` lookup and the `project != null` test. The installed daemon does not, and Pman.Admin was not opened again on the tablet.
