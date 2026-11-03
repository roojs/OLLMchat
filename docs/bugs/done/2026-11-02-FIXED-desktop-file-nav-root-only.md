# Desktop file nav shows only the project folder

**Status:** ✅ 2026-11-03. Child folders open after the fetch.

## Problem

- 🔷 Desktop starts on Agent Pi with the saved project
  `/home/alan/gitlive/OLLMchat`.
- 🔷 The file browser opens and starts file nav.
- 🔷 Expected: the folder tree lists the folders under that project.
- 🔷 Actual: file nav shows the project folder and no children.
- ℹ️ This is not `docs/bugs/2026-10-27-agent-pi-startup-does-not-open-project.md`.
  That report is the filesystem not opening. This run opens it.

## Evidence

- ✔️ `~/.config/ollmchat/config.2.json` window project is
  `/home/alan/gitlive/OLLMchat`.
- ✔️ SQLite `filebase` has that project as id 1, 46 direct child
  folders, and 2460 folders under the path. The database is not
  empty.
- ✔️ `~/.cache/ollmchat/ollmchat.debug.log` and
  `ollmfilesd.debug.log`, 2026-11-02 08:33, daemon pid 829293:
  - 08:33:14.805 client `opening project path=/home/alan/gitlive/OLLMchat`
  - 08:33:14.807 `Folder.fetch_files` replies `no folders` (before
    activate is sent)
  - 08:33:15.868 daemon `filesystem scan queued` (database load
    finished, reply sent)
  - 08:33:15.873 `Folder.fetch_children` id=5, replied 08:33:15.898
  - 08:33:15.924 `filesystem scan yield returned`
  - 08:33:15.928 client `event.filesystem.scan_end`
  - 08:33:15.929 `Folder.fetch_children` id=6, replied 08:33:15.954
  - 08:33:16.124 daemon `filesystem scan complete` (after both
    fetches and after `scan_end`)
- ℹ️ `read_dir` with `background_recurse` returns before the child
  walk. `activate_project` emits `scan_end` on that return.
  `process_folders` calls `update_from` when the walk finishes and
  does not emit `scan_end` again.
- ✔️ Cold start of the built daemon, then
  `./build/examples/oc-test-source-diff --debug --test-flow`:
  - `folder tree reply path=/home/alan/gitlive/OLLMchat map=240 rows=240`
  - `folder tree stored path=/home/alan/gitlive/OLLMchat rows=240 left=0 id=1`
  - `folders=240` and `type=off shown=1`
- ✔️ The same `rows=240` after the scan had finished. SQLite has
  2461 folder rows; 1721 are under `subprojects` and 510 under
  `build*`. 240 is the in-memory tree the daemon actually sent.
- ✔️ `left=0` means every returned folder was attached in the
  store. The visible tree model still had one row.

## Root cause

- ✔️ `Folder.Tree` asks GTK for a child model as soon as the
  project row exists. `TreeStore.load` puts that row up before
  `Folder.fetch_children` returns, so the segment is empty.
  The create function returned null for an empty segment. GTK
  treats null as a permanent leaf and does not ask again
  (`GtkTreeListModelCreateModelFunc`). The 240 folders are
  stored and never shown.

## Proposed fix

- 🔷 Return the segment's list model even when it is empty. GTK
  then shows rows that arrive after the project row is open.

### `liboccoder/Folder/Tree.vala` — empty segment

**Where:** `child_model`, the `get_n_items() == 0` return.

**Why:** An empty segment is not a leaf. The project row is
created before the fetch fills it.

#### Remove

```vala
				if (this.folders.segments.get(tip.path).get_n_items() == 0) {
					return null;
				}
				return new Gtk.SortListModel(
```

#### Replace with

```vala
				return new Gtk.SortListModel(
```

## Attempts / changelog

- ℹ️ 2026-11-02: bug opened from the desktop startup report.
- ✔️ Debug added, then removed: `ollmfilesd/Folder.vala` logged
  `folder tree reply`. `liboccoder/Folder/TreeStore.vala` logged
  `folder tree stored`.
- ✔️ `liboccoder/Folder/Tree.vala` returned the empty segment
  model. Same test: `rows=240`, `shown=48`.
- 🔷 That open ran while the segment was empty, so a folder that
  holds one child folder stayed the first name.
- ✔️ 2026-11-02 10:06, `oc-test-source-diff --debug --test-flow`.
  The store's longest first-level chain was `.cursor/rules`.
  The open rows still read `contrib`, `.cursor`, and `.github`.
  `filter.changed(DIFFERENT)` did not rewrite those labels.
  GTK keeps the child model from the first call.
- 🚫 Opening the project inside the `loading` notify, while the
  child function returned null for an empty segment, pegged a
  core. That path is not the fix.
- ✔️ The project row stays closed until `loading` is false, then
  it opens. The same test then showed `contrib/seccomp-gir`,
  `.cursor/rules`, and `.github/workflows`. `folders=240`. The
  run finished, it did not spin.
- 🔷 2026-11-02: that open is still one level. The tree has to
  expand every folder, not only the project row.
- ✔️ After the fetch, every collapsed row is expanded.
  `oc-test-source-diff --debug --test-flow` logged
  `tree open rows=202 depth=7`, then `type=off shown=220`.
  The run finished in about 9s.

## Proposed fix — expand every folder after the fetch

- 🔷 When `loading` goes false, walk the tree and expand every
  collapsed row. `autoexpand` stays off during the fetch, then
  turns on so a folder that appears later opens too.

### `liboccoder/Folder/Tree.vala` — bind

**Where:** the project `expanded = true` in `bind`.

**Why:** That bind runs when the row is added, before the
children exist. The child model cached then is one level deep.

#### Replace

```vala
				if (folder.is_project && !tree_row.expanded) {
					tree_row.expanded = true;
				}
```

#### With

```vala
				if (folder.is_project && !this.folders.loading && !tree_row.expanded) {
					tree_row.expanded = true;
				}
```

### `liboccoder/Folder/Tree.vala` — loading notify

**Where:** the `loading` false branch, after `tree_view.opacity = 1`.

**Why:** Opening only row 0 leaves every other folder closed.

#### Replace

```vala
				var model = (Gtk.TreeListModel) this.tree_selection.model;
				if (model.n_items > 0) {
					model.get_row(0).expanded = true;
				}
```

#### With

```vala
				var model = (Gtk.TreeListModel) this.tree_selection.model;
				model.autoexpand = true;
				var index = 0;
				while (index < model.n_items) {
					var row = model.get_row(index);
					index++;
					if (row.expanded) {
						continue;
					}
					row.expanded = true;
				}
```

## Next

- ✅ 2026-11-03 — user confirmed the folder tree lists the children.
