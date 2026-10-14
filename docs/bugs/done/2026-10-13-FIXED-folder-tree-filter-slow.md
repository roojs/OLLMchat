# Folder tree load is too slow

**Status:** ✅ closed 2026-10-14. The 13 Oct open was 2.0s after the store. The same span on the current tree is 74ms.

## Problem

- **🔷** Opening the folder tree for this project takes about two seconds. That is too slow.
- **🔷** The folder reply itself is not the slow part.
- **🚫** The eye button and the type buttons do not freeze the pop-down. That title was wrong.
- **ℹ️** `docs/plans/CODER-4.2.5-project-file-selector.md`.

## Evidence

- **✔️** `./build/examples/oc-test-source-diff --debug --test-flow` against `/usr/bin/ollmfilesd`, project `/home/alan/gitlive/OLLMchat`. Debug lines sat around the store loop, the tree-model build, and each `filter.changed`. The log clock is the gap.

- **✔️** Store, 17:05:42.464 to 17:05:42.473. 307 rows in, 307 stored. 9ms.
- **✔️** First expanded tree, 17:05:42.473 to 17:05:44.449. Hiding was still on. The model reported 197 rows. 2.0s.
- **✔️** Eye open (`hiding false`), 17:05:44.449 to 17:05:46.023. 1.6s. The test then printed `type=off shown=287`.
- **✔️** Code, 17:05:46.049 to 17:05:47.598. 1.5s. `type=code shown=110`.
- **✔️** Documents, 17:05:47.599 to 17:05:49.796. 2.2s. `type=document shown=114`.
- **✔️** Back to every folder, 17:05:49.805 to 17:05:52.460. 2.7s. `type=off shown=287`.
- **✔️** The child callback was timed with the same tree.
  - Returning the stored segment, with no filter and no sort, builds the tree in 24ms. Child rows are not filtered. `Gtk.TreeListModel` only filters its root model.
  - A `Gtk.FilterListModel` on each segment, and no `Gtk.SortListModel`, builds in about 30ms. One filter change is 44ms to 75ms.
  - The current filter plus sort builds in about 50ms. One filter change is 41ms to 78ms.
- **✔️** `tree_factory.bind` ran for every folder on that open, about 200 rows. `FileSelector` puts the page stack in `this.scroll` with `propagate_natural_height = true`, so the list's natural height is the whole tree. The flat-list trial was still several seconds for the same reason: every row was built.
- **✔️** Current `--test-flow`, 09:38:33. `Folder.fetch_children` at .694. 234 rows in hand at .729. Stored at .734. Tree build at .734, ready with 197 rows at .809. That is 35ms for the reply, 5ms for the store, 74ms for the expanded tree. This open is not 2 seconds.

## Root cause

- **✔️** `examples/oc-test-source-diff/FolderTree.vala` builds a `Gtk.TreeListModel` with auto-expand on. The child function makes a new filter model and a new sort model for every folder that has children, and they all share one `Gtk.CustomFilter`.
- **✔️** When loading finishes, that model is built over the whole project. That build is the 2.0s. The later eye and type clicks walk the same tree again. They are the same cost, not a separate freeze.
- **🚫** The daemon reply and `FolderTreeStore.append` are not this wait. 307 rows were stored in 9ms.
- **🚫** Building the same auto-expanded tree a second time does not fix it. The first build was already 2.0s.

## What the store already is

- **ℹ️** `FolderTreeStore.flat` is already the top list. Every folder is in it once. The same folder also sits in `path_map` and in the child segment of its parent. Filling that list was the 9ms.
- **ℹ️** `FolderTree` asks GTK for a child model per folder, and each of those is a new filter and a new sort. The first build of that tree is the 2.0s.
- **🚫** Starting the tree collapsed. That only waits until the user expands it. The whole project open is the case that has to be fast.

## Trial

- **ℹ️** The screen list was swapped off `Gtk.TreeListModel` onto one flat list filled from `flat`. That swap is not what the GTK docs describe, and it was not in the write-up, so it was reverted. `FolderTree` is a `Gtk.TreeListModel` again.
- **ℹ️** The trial's shown counts still matched: 197, then 287, 110, 114, and 287.
- **ℹ️** The log clock between the end of each refill was still several seconds: 17:23:10.576, 17:23:15.299, 17:23:18.823, 17:23:22.627, 17:23:29.463.

## What GTK documents

Checked against the GTK 4 docs and the GTK list-model posts. This tree is about 300 folders. The docs do not describe replacing `Gtk.TreeListModel` with one flat screen list.

- **ℹ️** [`gtk_tree_list_model_new`](https://docs.gtk.org/gtk4/ctor.TreeListModel.new.html) builds the tree with every row collapsed. The child callback runs when a row is expanded ([`GtkTreeListModelCreateModelFunc`](https://docs.gtk.org/gtk4/callback.TreeListModelCreateModelFunc.html)). A leaf returns `NULL`. A folder that may gain children later returns an empty model and fills that model when the children arrive.
- **ℹ️** [`autoexpand`](https://docs.gtk.org/gtk4/method.TreeListModel.set_autoexpand.html) turns that off. If it is true, every row that gets added is expanded, and that walks into the child model the callback just returned. `gtk_tree_list_model_init_node` in [`gtktreelistmodel.c`](https://gitlab.gnome.org/GNOME/gtk/-/blob/4.22.4/gtk/gtktreelistmodel.c) calls `gtk_tree_list_model_expand_node` for each item when `autoexpand` is set. `FolderTree` passes `true`. The callback then allocates a `Gtk.FilterListModel` and a `Gtk.SortListModel` per folder.
- **ℹ️** [`GtkListView`](https://docs.gtk.org/gtk4/class.ListView.html) builds one row widget per visible item. The 2.0s is not a widget per folder. The model is still the expanded tree.
- **ℹ️** [`g_list_store_splice`](https://docs.gtk.org/gio/method.ListStore.splice.html) is the documented bulk fill: one `items-changed` for the batch. The store here was already 9ms. That is not this wait.
- **ℹ️** [`GtkFilterListModel` incremental](https://docs.gtk.org/gtk4/method.FilterListModel.set_incremental.html) and [`GtkSortListModel` incremental](https://docs.gtk.org/gtk4/method.SortListModel.set_incremental.html) are for about 10,000 to 100,000 items. Incremental sort is documented as making the total time slower. The [list-model post](https://blogs.gnome.org/gtk/2020/09/08/on-list-models/) shows that path on a list of 500,000 words. It is not the documented fix for 300 folders.
- **ℹ️** [`GtkCustomFilter.set_filter_func`](https://docs.gtk.org/gtk4/method.CustomFilter.set_filter_func.html) says to call `gtk_filter_changed` when the match function starts answering differently. [`GTK_FILTER_CHANGE_DIFFERENT`](https://docs.gtk.org/gtk4/enum.FilterChange.html) is documented as always a correct choice. The eye and the type buttons do that. `LESS_STRICT` and `MORE_STRICT` only help when the new match is strictly wider or stricter. They do not apply to the first build.
- **ℹ️** GTK's own directory model is [`GtkDirectoryList`](https://blogs.gnome.org/gtk/2020/09/08/on-list-models/): one directory, filled asynchronously. The file chooser does not expand a whole project in one go.

## Ruled out

- **🚫** A second backing tree. `flat` and the parent segments are already that.
- **🚫** Editing each child segment from the button. That is still a walk of the tree, one list per folder, which is the wait we measured.
- **🚫** `LESS_STRICT` / `MORE_STRICT` on the shared filter. The first build is already 2.0s before any button.
- **🚫** Returning the raw child segment from `child_model`. The tree builds in 24ms and the child rows are no longer filtered.
- **🚫** `propagate_natural_height = false` on `FileSelector.scroll`. Tested with `--test-flow`. With the flag on, the open bound 198 rows for 197 shown, the list was 406px tall, and its natural height was 4334. With the flag off, the same numbers: 198 binds, height 406, natural height 4334. It does not stop the list building every row. `place()` had already set min and max content height to 406 in both runs.
