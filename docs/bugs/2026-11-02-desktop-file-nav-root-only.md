# Desktop file nav shows only the project folder

**Status:** ⏳ children show; single-folder chains open after the fetch — desktop binary not restarted

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
- ✔️ The project row opens during the fetch, and the child model
  stays attached. When `loading` goes false the filter runs
  again, so the one-folder walk sees the whole chain. A repeated
  path stops the walk. The check logged
  `contrib/seccomp-gir`, `.cursor/rules`, and
  `.github/workflows`. `folders=240`, `shown=48`.

## Next

- 🔷 ⏳ Restart the desktop app from this tree and confirm the
  file browser lists the project’s folders.
