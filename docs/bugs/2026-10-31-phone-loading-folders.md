# Phone sits on Loading folders

**Status:** ⏳ fix is on the phone (pid 29652). Sheet not checked.

There is no open bug for this. [`2026-10-24-CLOSED-folder-load-slow.md`](done/2026-10-24-CLOSED-folder-load-slow.md) was closed without a change.

## Problem

- 🔷 On the phone, open a project. The sheet stays on **Loading folders**. The tree never comes up.
- 🔷 Expected: the project row and its first level of folders appear. Deeper folders stay collapsed until they are opened.

## Evidence

- ✔️ The label is `FolderTreeStore.loading`. The phone overlay in `liboccoder/File/Pullout.vala` shows it and sets the sheet opacity to 0 for the whole time that flag is true.
- ✔️ `load` leaves `loading` true while it appends every folder from `Folder.fetch_children`. That call returns the whole project tree, not one level.
- ✔️ The tree model is built with autoexpand on. Every appended folder is expanded, filtered, and sorted before `loading` can go false. `liboccoder/Folder/Tree.vala`, the `Gtk.TreeListModel` in the constructor (`false, true, child_model`).
- ✔️ When `loading` goes false, that same handler builds a second autoexpanded model before the overlay handler hides the label.
- ✔️ 2026-10-31 08:57, phone pid 27020, project `/home/alan/gitlive/OLLMchat`. `Folder.fetch_children` had already returned. The label is not waiting on the file server.
- ℹ️ The project row is forced open in `bind`. First-level folders do not need autoexpand.

## Root cause

- ✔️ **Loading folders** stays up until an autoexpanded model of every folder in the project has been built. That build is on the phone GTK thread. The file server has already answered.

## Proposed fix

- 🔷 Build the tree collapsed. The project row still opens itself. Stop building a second model when loading ends, so the overlay can hide.

### `liboccoder/Folder/Tree.vala` — constructor

**Why:** Autoexpand walks every folder while `loading` is true, so the overlay never clears. The second model does that walk again.

**Where:** The `Gtk.TreeListModel` passed to `this.tree_selection`, and the `loading` notify.

#### Replace

```vala
			var tree_model = new Gtk.TreeListModel(
				new Gtk.SortListModel(new Gtk.FilterListModel(this.folders, this.filter), name_sorter),
				false,
				true,
				child_model
			);
```

#### With

```vala
			var tree_model = new Gtk.TreeListModel(
				new Gtk.SortListModel(new Gtk.FilterListModel(this.folders, this.filter), name_sorter),
				false,
				false,
				child_model
			);
```

#### Replace

```vala
				this.tree_selection.model = new Gtk.TreeListModel(
					new Gtk.SortListModel(new Gtk.FilterListModel(this.folders, this.filter),
							name_sorter),
					false, true, child_model
				);
				this.tree_selection.selected = Gtk.INVALID_LIST_POSITION;
```

#### With

```vala
				this.tree_selection.selected = Gtk.INVALID_LIST_POSITION;
```

## Attempts / changelog

- ✔️ 2026-10-31 — applied both fences in `liboccoder/Folder/Tree.vala`. The tree model is collapsed. Loading no longer builds a second model.
- ✔️ 2026-10-31 — `PIXIEWOOD_PHASE=build` then `adb install -r`. Launched pid 29652. Same signature as the morning install, so the package was updated in place.

## Next

- 💩 ⏳ Open a project on the phone. The sheet leaves **Loading folders** and shows the first level.
