# CODER-4.2.6 Coder screen on mainline

**Status:** ✔️ agent-complete — ready for user review

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan** until it is done and archived.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala code must follow `docs/coding-standards.md`.

**Related:**

- ℹ️ Parent smoke behavior is [`CODER-4.2.5-project-file-selector.md`](CODER-4.2.5-project-file-selector.md).
- ℹ️ Why the smoke editor is a copy: [`docs/bugs/done/2026-10-10-FIXED-folder-list-blocked-by-file-dropdown.md`](../bugs/done/2026-10-10-FIXED-folder-list-blocked-by-file-dropdown.md).
- ℹ️ 4.2.4 and 4.2.5 left the product on the dropdown header. This plan replaces that with `CoderView`.
- ℹ️ 4.2.4 still names `examples/oc-test-source-diff/CoderView.vala`. After Step 2 that screen is `liboccoder/CoderView.vala`.

---

## Purpose

- 🔷 This is the whole coder screen from the smoke app, not only the file nav. The diffs are part of the merge.
- 🔷 It lands in `liboccoder`. The smoke demo then uses that library code.
- ℹ️ Mainline here is `liboccoder` on this branch. `origin/main` already contains the smoke copies. There is no second git branch to merge.
- 🔷 The `Folder` prefix becomes `liboccoder/Folder/` and `namespace OLLMcoder.Folder`. The class is the rest of the name.
- 🔷 The `File` prefix becomes `liboccoder/File/` and `namespace OLLMcoder.File`. The class is the rest of the name.
- 🔷 `SelectorPull` and `ProjectSelector` stay at the top of `liboccoder`, in `namespace OLLMcoder`.
- 🔷 `CoderView` stays the class `CoderView` in `namespace OLLMcoder`, at `liboccoder/CoderView.vala`. Same top level as the selectors.
- 🔷 Each major step eventually wires the call sites that use the types it lands. A file in `liboccoder` that nothing constructs is not done.
- 🔷 Three steps. Each one leaves the smoke window runnable.
  - Step 1 lands `Folder`, `File`, and the two top-level selectors.
    - Step 1A copies the smoke files byte-for-byte to their final `liboccoder` paths and filenames.
    - Step 1B renames the declarations and references inside those files.
    - Step 1C merges the supporting enums and wires the library and valadoc builds.
  - Step 2 lands `CoderView` and merges the smoke editor and the review bar into the library.
  - Step 3 points the demo at those library types and deletes the smoke copies.
- ✔️ Step 1A copied the smoke files byte-for-byte to their final target paths.
- ✔️ Step 1B renamed the declarations and references inside the ten copied files.
- ✔️ Step 1C merged the supporting enums and wired the library and valadoc builds.
- ✔️ Step 1 is agent-complete and ready for user review.
- 🔷 ✔️ Step 2 is agent-complete and ready for user review.
- 🔷 ✔️ Step 3 is agent-complete and ready for user review.
- 🔷 ✔️ The three-step migration is agent-complete and ready for user review.

---

## Homes

Step 1A establishes these paths and filenames. Step 1B changes the declarations to the listed namespaces and class names. The prefix is the directory and the namespace. Same shape as `OLLMcoder.Skill.Runner` and `OLLMcoder.Diff.ReviewBar`: the class does not repeat the prefix.

- ✔️ `namespace OLLMcoder.Folder` in `liboccoder/Folder/`
  - ✔️ `FolderBrowse` → `Browse` in `Folder/Browse.vala`
  - ✔️ `FolderTree` → `Tree` in `Folder/Tree.vala`
  - ✔️ `FolderTreeStore` → `TreeStore` in `Folder/TreeStore.vala`
- ✔️ `namespace OLLMcoder.File` in `liboccoder/File/`
  - ✔️ `FileList` → `List` in `File/List.vala`
  - ✔️ `FileListStore` → `ListStore` in `File/ListStore.vala`
  - ✔️ `FileNav` → `Nav` in `File/Nav.vala`
  - ✔️ `FileOverlay` → `Overlay` in `File/Overlay.vala`
  - ✔️ `FilePullout` → `Pullout` in `File/Pullout.vala`
- ✔️ Top level, `namespace OLLMcoder`
  - ✔️ `SelectorPull` stays `SelectorPull` in `liboccoder/SelectorPull.vala`
  - ✔️ `ProjectSelector` stays `ProjectSelector` in `liboccoder/ProjectSelector.vala`
- ✔️ `CoderView` stays `CoderView` in `liboccoder/CoderView.vala`.
- ✔️ `SourceView` stays `OLLMcoder.SourceView` in `liboccoder/SourceView.vala`; the smoke editor is merged into that file, diffs included.
- ✔️ The review bar stays `OLLMcoder.Diff.ReviewBar` in `liboccoder/Diff/ReviewBar.vala`; it already contained the smoke behavior.
- ✔️ `Form` and `Slot` are in `liboccoder/namespace.vala`, inside `namespace OLLMcoder`. `File`, `Folder`, the selectors, and `CoderView` all take `Form`.

---

## Step 1 — `Folder`, `File`, and the selectors

These types have no twin in the library. `CoderView` does not land here. It constructs the smoke editor, and that editor is Step 2.

- ✔️ Step 1A copied the files to the final target paths without declaration or reference changes.
- ✔️ Step 1B applied the Homes names inside the ten copied files only.
- ✔️ Step 1C merged `Form` and `Slot`, then listed the files in `liboccoder/meson.build` and `docs/meson.build`.
- ℹ️ The smoke executable keeps compiling the example copies until Step 3. `--selectors`, `--phone`, and `--tablet` do not change in these substeps.

### Step 1A — exact copies

- ✔️ Copied these files byte-for-byte from `examples/oc-test-source-diff/` to their final target filenames:
  - `SelectorPull.vala` → `liboccoder/SelectorPull.vala`
  - `ProjectSelector.vala` → `liboccoder/ProjectSelector.vala`
  - `FolderTreeStore.vala` → `liboccoder/Folder/TreeStore.vala`
  - `FolderTree.vala` → `liboccoder/Folder/Tree.vala`
  - `FolderBrowse.vala` → `liboccoder/Folder/Browse.vala`
  - `FileListStore.vala` → `liboccoder/File/ListStore.vala`
  - `FileList.vala` → `liboccoder/File/List.vala`
  - `FileNav.vala` → `liboccoder/File/Nav.vala`
  - `FileOverlay.vala` → `liboccoder/File/Overlay.vala`
  - `FilePullout.vala` → `liboccoder/File/Pullout.vala`
- ✔️ The destination paths and filenames are final. There is no later file move.
- ✔️ Classes, namespaces, members, type references, and constructor calls remained unchanged in Step 1A.
- ✔️ The copies were not added to Meson or valadoc in Step 1A.
- ✔️ All ten destination files were verified byte-identical to their sources.
- ℹ️ `examples/oc-test-source-diff/namespace.vala` is not copied over `liboccoder/namespace.vala`. Step 1C merges `Form` and `Slot` into the existing library namespace file.

### Step 1B — declarations and references

- ✔️ Edited the Step 1A copies in place without moving or renaming their files.
- ✔️ Renamed their namespaces, classes, type references, constructor calls, doc links, and examples.
- ✔️ Step 1B edited only the ten copied files. It did not edit `liboccoder/namespace.vala`, Meson, or valadoc inputs.

#### Renamed library files — declarations and references

**Why:** the target path prefixes become namespaces, and the class does not repeat its prefix.

**Where:** the ten Step 1A copies. The example copies keep the old names until Step 3.

**Depends on:** Step 1A.

- ✔️ `SelectorPull.vala` and `ProjectSelector.vala`: `namespace OLLMapp` became `namespace OLLMcoder`. Class names stayed unchanged.
- ✔️ `Folder/TreeStore.vala`: namespace became `OLLMcoder.Folder`. `FolderTreeStore` became `TreeStore`, including constructors, property types, links, and examples.
- ✔️ `Folder/Tree.vala`: namespace became `OLLMcoder.Folder`. `FolderTree` became `Tree`, `FolderTreeStore` became `TreeStore`, and file-side types became `File.List`.
- ✔️ `Folder/Browse.vala`: namespace became `OLLMcoder.Folder`. `FolderBrowse` became `Browse`, `FolderTree` became `Tree`, and `FileList` became `File.List`.
- ✔️ `File/ListStore.vala`: namespace became `OLLMcoder.File`. `FileListStore` became `ListStore`, including links and examples.
- ✔️ `File/List.vala`: namespace became `OLLMcoder.File`. `FileList` became `List`, `FileListStore` became `ListStore`, and folder-side types became `Folder.FileKind`.
- ✔️ `File/Nav.vala`: namespace became `OLLMcoder.File`. `FileNav` became `Nav`, folder-side types became `Folder.Tree` and `Folder.FileKind`, and `FileList` became `List`.
- ✔️ `File/Overlay.vala`: namespace became `OLLMcoder.File`. `FileOverlay` became `Overlay`, `FileNav` became `Nav`, and `FolderBrowse` became `Folder.Browse`.
- ✔️ `File/Pullout.vala`: namespace became `OLLMcoder.File`. `FilePullout` became `Pullout`, `FileNav` became `Nav`, and `FolderBrowse` became `Folder.Browse`.
- ℹ️ `Form`, `Slot`, and `SelectorPull` stay unqualified because they are in the parent namespace `OLLMcoder`.
- ℹ️ `folder_tree` stays the property name on `File.Nav`. Step 3's empty-list check uses it.

### ✔️ Step 1C — namespace and build wiring

- ✔️ Merged `Form` and `Slot` into `liboccoder/namespace.vala`.
- ✔️ Added the renamed files to `liboccoder/meson.build` and `docs/meson.build`.
- ℹ️ The demo does not call the library copies until Step 3.

#### ✔️ `liboccoder/meson.build` — compile the new files

**Why:** the library build is what makes `OLLMcoder.Folder`, `OLLMcoder.File`, and the selectors exist.

**Where:** `namespace.vala` first in `occoder_src`. Add the ten copied files after `'SourceView.vala'`. Defining files precede their users where the dependency graph allows it.

**Depends on:** Step 1B and its rename review.

#### Add

```meson
  'namespace.vala',
```

After `'SourceView.vala'`:

```meson
  'SelectorPull.vala',
  'ProjectSelector.vala',
  'Folder/TreeStore.vala',
  'Folder/Tree.vala',
  'File/ListStore.vala',
  'File/List.vala',
  'Folder/Browse.vala',
  'File/Nav.vala',
  'File/Overlay.vala',
  'File/Pullout.vala',
```

#### ✔️ `docs/meson.build` — same files for valadoc

**Why:** valadoc lists `liboccoder` sources itself. A type missing here is missing from the docs build.

**Where:** the `liboccoder` source list. `../liboccoder/namespace.vala` is already there. Do not add a `Form.vala` line.

**Depends on:** the meson list above.

#### Add

```meson
    '../liboccoder/SelectorPull.vala',
    '../liboccoder/ProjectSelector.vala',
    '../liboccoder/Folder/TreeStore.vala',
    '../liboccoder/Folder/Tree.vala',
    '../liboccoder/File/ListStore.vala',
    '../liboccoder/File/List.vala',
    '../liboccoder/Folder/Browse.vala',
    '../liboccoder/File/Nav.vala',
    '../liboccoder/File/Overlay.vala',
    '../liboccoder/File/Pullout.vala',
```

### Issues

- ℹ️ `OLLMfiles.Folder` and `OLLMfiles.File` stay fully qualified. Inside `namespace OLLMcoder.Folder`, a bare `Folder` is that namespace. Inside `namespace OLLMcoder.File`, a bare `File` is that namespace. The smoke files already spell `OLLMfiles.Folder` and `OLLMfiles.File`.
- ℹ️ `liboccoder/List/` is already `OLLMcoder.List` (`SortedList`). `File.List` does not go there.
- ℹ️ `FileDropdown` stays `OLLMcoder.FileDropdown` at the top level. It is not `OLLMcoder.File`.
- ℹ️ `FileConnectionAdd.vala` starts with `File` and is `OLLMapp.SettingsDialog`. It is on the Android executable only. It does not join `OLLMcoder.File`.
- ℹ️ Step 3 removed the example copies; the smoke executable uses `liboccoder` through `occoder.vapi`.
- ℹ️ `{@link FolderTree}` and `{@link FileList}` move with the types. From outside the new namespace they are `OLLMcoder.Folder.Tree` and `OLLMcoder.File.List`.

---

## Step 2 — `CoderView`, the editor, and the diffs

- 🔷 ✔️ Landed `CoderView` in `liboccoder` with `ProjectSelector`, `File.Overlay`, `File.Pullout`, and `SourceView`.
- 🔷 ✔️ Replaced the library `SourceView` with the smoke editor while preserving its editor, gutter, diff, and pending-review behavior.
- 🔷 ✔️ Made `AgentFactory`, `AgentPi/Factory`, and `Skill/Factory` host `CoderView`.
- 🔷 ✔️ Desktop and Android pass their selected form into the factories; factories do not hardcode desktop layout.
- 🔷 ✔️ Search stays on `CoderView`; `save_button`, `source_view`, and `file_changed` provide the required editor integration.
- ℹ️ `liboccoder/Diff/ReviewBar.vala` required no edit because it already contained the smoke behavior plus `update_diff_old`.
- ℹ️ Exact Step 2 changes and verification are in [`CODER-4.2.6.1-coder-screen-mainline-step-2.md`](CODER-4.2.6.1-coder-screen-mainline-step-2.md).

---

## Step 3 — Demo uses the library

- 🔷 ✔️ The smoke window constructs `OLLMcoder.CoderView`.
- 🔷 ✔️ Export the library screen and the navigation type graph used by the external smoke executable.
- 🔷 ✔️ The example copies of the Step 1 types, `CoderView.vala`, `SourceView.vala`, and `ReviewBar.vala` are gone.
- 🔷 ✔️ `--selectors`, `--phone`, and `--tablet` behave as in 4.2.5 (compile-time wiring; runtime smoke not run here).
- 🔷 ✔️ A baseline/current pair with no selector flag still opens `show_diff` and `update_diff_old` through `OLLMcoder.SourceView` (compile-time wiring; runtime smoke not run here).

### ✔️ Export the library types used by the demo

**Why:** the smoke executable links through `occoder.vapi`; the screen and every type exposed through its public navigation properties must therefore be public.

**Where:** the class declarations listed below.

**Depends on:** Step 2.

- ✔️ Applied the ten `public class` declarations below (2026-10-26).
- ✔️ Applied `public enum Slot` in `liboccoder/namespace.vala` so `public class File.Nav` compiles (`Slot` appears on protected `load`).

**`liboccoder/namespace.vala`**

#### Remove

```vala
	enum Slot {
```

#### Replace with

```vala
	public enum Slot {
```

**`liboccoder/CoderView.vala`**

#### Remove

```vala
	class CoderView : Gtk.Box
```

#### Replace with

```vala
	public class CoderView : Gtk.Box
```

**`liboccoder/SelectorPull.vala`**

#### Remove

```vala
	class SelectorPull : Gtk.Box
```

#### Replace with

```vala
	public class SelectorPull : Gtk.Box
```

**`liboccoder/ProjectSelector.vala`**

#### Remove

```vala
	class ProjectSelector : Gtk.Box
```

#### Replace with

```vala
	public class ProjectSelector : Gtk.Box
```

**`liboccoder/File/Nav.vala`**

#### Remove

```vala
	class Nav : Gtk.Box
```

#### Replace with

```vala
	public class Nav : Gtk.Box
```

**`liboccoder/File/Overlay.vala`**

#### Remove

```vala
	class Overlay : Nav
```

#### Replace with

```vala
	public class Overlay : Nav
```

**`liboccoder/File/Pullout.vala`**

#### Remove

```vala
	class Pullout : Nav
```

#### Replace with

```vala
	public class Pullout : Nav
```

**`liboccoder/File/List.vala`**

#### Remove

```vala
	class List : Gtk.Box
```

#### Replace with

```vala
	public class List : Gtk.Box
```

**`liboccoder/File/ListStore.vala`**

#### Remove

```vala
	class ListStore : Object, GLib.ListModel
```

#### Replace with

```vala
	public class ListStore : Object, GLib.ListModel
```

**`liboccoder/Folder/Tree.vala`**

#### Remove

```vala
	class Tree : Gtk.Box
```

#### Replace with

```vala
	public class Tree : Gtk.Box
```

**`liboccoder/Folder/TreeStore.vala`**

#### Remove

```vala
	class TreeStore : Object, GLib.ListModel
```

#### Replace with

```vala
	public class TreeStore : Object, GLib.ListModel
```

### ✔️ Wiring

The smoke window is `namespace OLLMapp`. After this step the screen and the selectors are `namespace OLLMcoder`, so the calls are qualified.

#### ✔️ `examples/oc-test-source-diff.vala` — construct the library screen

**Why:** this is the demo entry. `--selectors`, `--phone`, and `--tablet` go through `CoderView`. A run that also has file pairs builds the selector row itself.

**Where:** the field types, the selector setup, and the pair-path casts. The `new OLLMcoder.SourceView(...)` call in the pair window is not in this edit.

**Depends on:** Step 2.

- ✔️ Applied every Remove/Replace fence below, including the five `OLLMcoder.Folder.FileKind` qualifications (2026-10-26).

#### Remove

```vala
		private SelectorPull selector_pull;
		private CoderView coder;
```

#### Replace with

```vala
		private OLLMcoder.SelectorPull selector_pull;
		private OLLMcoder.CoderView coder;
```

#### Remove

```vala
				var form = Form.DESKTOP;
				if (opt_phone) {
					form = Form.PHONE;
				}
				if (opt_tablet) {
					form = Form.TABLET;
				}
```

#### Replace with

```vala
				var form = OLLMcoder.Form.DESKTOP;
				if (opt_phone) {
					form = OLLMcoder.Form.PHONE;
				}
				if (opt_tablet) {
					form = OLLMcoder.Form.TABLET;
				}
```

#### Remove

```vala
				this.show_pull = form != Form.DESKTOP;
				if (this.pair_baselines.length == 0) {
					var coder = new CoderView(manager, form);
```

#### Replace with

```vala
				this.show_pull = form != OLLMcoder.Form.DESKTOP;
				if (this.pair_baselines.length == 0) {
					var coder = new OLLMcoder.CoderView(manager, form);
```

#### Remove

```vala
					this.selector_pull = new SelectorPull(form);
					this.selector_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
```

#### Replace with

```vala
					this.selector_pull = new OLLMcoder.SelectorPull(form);
					this.selector_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
```

#### Remove

```vala
					var projects = new ProjectSelector(manager, form, this.selector_pull);
					var files = (FileNav) new FileOverlay(manager, form);
					if (form == Form.PHONE) {
						files = new FilePullout(manager, form, this.selector_pull);
```

#### Replace with

```vala
					var projects = new OLLMcoder.ProjectSelector(manager, form, this.selector_pull);
					var files = (OLLMcoder.File.Nav) new OLLMcoder.File.Overlay(manager, form);
					if (form == OLLMcoder.Form.PHONE) {
						files = new OLLMcoder.File.Pullout(manager, form, this.selector_pull);
```

#### Remove

```vala
						if (form == Form.PHONE) {
							return;
						}
						((FileOverlay) files).list.visible = false;
```

#### Replace with

```vala
						if (form == OLLMcoder.Form.PHONE) {
							return;
						}
						((OLLMcoder.File.Overlay) files).list.visible = false;
```

#### Remove

```vala
				var projects = (ProjectSelector) this.selector_row.get_first_child();
```

#### Replace with

```vala
				var projects = (OLLMcoder.ProjectSelector) this.selector_row.get_first_child();
```

#### Remove

```vala
						((FileOverlay) this.selector_row.get_last_child()).list);
```

#### Replace with

```vala
						((OLLMcoder.File.Overlay) this.selector_row.get_last_child()).list);
```

#### Remove

```vala
				if (this.coder.files.folder_tree.kind != FileKind.ANY) {
```

#### Replace with

```vala
				if (this.coder.files.folder_tree.kind != OLLMcoder.Folder.FileKind.ANY) {
```

#### Remove

```vala
				if (this.coder.files.folder_tree.kind != FileKind.CODE ||
					this.coder.files.file_list.kind != FileKind.CODE) {
```

#### Replace with

```vala
				if (this.coder.files.folder_tree.kind != OLLMcoder.Folder.FileKind.CODE ||
					this.coder.files.file_list.kind != OLLMcoder.Folder.FileKind.CODE) {
```

#### Remove

```vala
				if (this.coder.files.folder_tree.kind != FileKind.DOCUMENT ||
					this.coder.files.file_list.kind != FileKind.DOCUMENT) {
```

#### Replace with

```vala
				if (this.coder.files.folder_tree.kind != OLLMcoder.Folder.FileKind.DOCUMENT ||
					this.coder.files.file_list.kind != OLLMcoder.Folder.FileKind.DOCUMENT) {
```

#### Remove

```vala
					this.coder.files.folder_tree.kind != FileKind.ANY) {
```

#### Replace with

```vala
					this.coder.files.folder_tree.kind != OLLMcoder.Folder.FileKind.ANY) {
```

`this.coder.files.folder_tree.folders.flat` stays. `folder_tree` was not renamed.

- ✔️ Deleted `examples/oc-test-source-diff/namespace.vala` and the other thirteen superseded smoke copies; `Form` and `Slot` live in `liboccoder/namespace.vala`. `FileConnectionAdd.vala` remains.

#### ✔️ `examples/meson.build` — stop compiling the copies

**Why:** two copies of `CoderView` and `SourceView` in one binary will not compile. Both executables list the same smoke files.

**Where:** the Android `oc-test-source-diff` `sources` array, and the desktop `test_source_diff` `sources` array.

**Depends on:** the `oc-test-source-diff.vala` edits above.

- ✔️ Removed the moved sources from both Android and desktop `oc-test-source-diff` source arrays (2026-10-26).

#### Remove

```meson
      'oc-test-source-diff/namespace.vala',
      'oc-test-source-diff/SelectorPull.vala',
      'oc-test-source-diff/ProjectSelector.vala',
      'oc-test-source-diff/FolderTreeStore.vala',
      'oc-test-source-diff/FolderTree.vala',
      'oc-test-source-diff/FolderBrowse.vala',
      'oc-test-source-diff/FileListStore.vala',
      'oc-test-source-diff/FileList.vala',
      'oc-test-source-diff/FileNav.vala',
      'oc-test-source-diff/FileOverlay.vala',
      'oc-test-source-diff/FilePullout.vala',
      'oc-test-source-diff/ReviewBar.vala',
      'oc-test-source-diff/SourceView.vala',
      'oc-test-source-diff/CoderView.vala',
```

The same `Remove` applies to the desktop list. The desktop entries are indented four spaces. The Android entries are indented six. `FileConnectionAdd.vala` is only on the Android list and stays.

### Issues

- ℹ️ `examples/meson.build` lists the smoke entry twice. Android keeps `FileConnectionAdd.vala` and the Android C sources; desktop does not.
- ℹ️ The pair window constructs `OLLMcoder.SourceView` and calls `show_diff` and `update_diff_old`. After Step 2 that editor has no dropdown header.
- ℹ️ `scripts/android/build-source-diff-apk.sh` packages this same smoke window. The Android list and the desktop list match apart from `FileConnectionAdd.vala` and the Android C sources.

---

## LLM notes

- 🚫 Do not add `namespace OLLMcoder.Coder`, a `liboccoder/Coder/` directory, or a class named `View`. `CoderView` stays `CoderView`.
- 🚫 Do not add a `header` argument to `SourceView`. Do not build `ProjectDropdown` or `FileDropdown` inside it.
- 🚫 Do not move `FileDropdown` into `OLLMcoder.File`. Do not put `File.Nav` inside `SourceView`.
- 🚫 Do not keep `apply_manager_state` on the factories. It only updates the dropdowns.
- 🚫 Do not remove `update_diff_old`. The pair-diff path calls it.
- 🚫 Do not move `FileConnectionAdd.vala` into `liboccoder`.
- 🚫 Do not put `File.List` in `liboccoder/List/`.
- 🚫 Do not edit one of the two copies and leave the other. Step 3 is what deletes the example side.
- 🚫 Do not rewrite 4.2.4 in this plan. Its `CoderView` path is stale after Step 2.
- 🚫 No second smoke app, and no return of `examples/oc-test-source-diff-selectors.vala`.
