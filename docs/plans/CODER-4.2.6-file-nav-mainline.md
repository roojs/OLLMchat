# CODER-4.2.6 Coder screen on mainline

**Status:** ⏳ proposed

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
- 🔷 Each step wires the call sites that use the types it lands. A file in `liboccoder` that nothing constructs is not done.
- 🔷 Three steps. Each one leaves the smoke window runnable.
  - Step 1 lands `Folder`, `File`, and the two top-level selectors.
  - Step 2 lands `CoderView` and merges the smoke editor and the review bar into the library.
  - Step 3 points the demo at those library types and deletes the smoke copies.
- 🔷 ⏳ Step 1 is not started.
- 🔷 ⏳ Step 2 is not started. It waits on Step 1.
- 🔷 ⏳ Step 3 is not started. It waits on Step 2.

---

## Homes

The prefix is the directory and the namespace. Same shape as `OLLMcoder.Skill.Runner` and `OLLMcoder.Diff.ReviewBar`: the class does not repeat the prefix.

- 🔷 `namespace OLLMcoder.Folder` in `liboccoder/Folder/`
  - `FolderBrowse` → `Browse` in `Folder/Browse.vala`
  - `FolderTree` → `Tree` in `Folder/Tree.vala`
  - `FolderTreeStore` → `TreeStore` in `Folder/TreeStore.vala`
- 🔷 `namespace OLLMcoder.File` in `liboccoder/File/`
  - `FileList` → `List` in `File/List.vala`
  - `FileListStore` → `ListStore` in `File/ListStore.vala`
  - `FileNav` → `Nav` in `File/Nav.vala`
  - `FileOverlay` → `Overlay` in `File/Overlay.vala`
  - `FilePullout` → `Pullout` in `File/Pullout.vala`
- 🔷 Top level, `namespace OLLMcoder`
  - `SelectorPull` stays `SelectorPull` in `liboccoder/SelectorPull.vala`
  - `ProjectSelector` stays `ProjectSelector` in `liboccoder/ProjectSelector.vala`
- 🔷 `CoderView` stays `CoderView` in `liboccoder/CoderView.vala`
- ℹ️ `SourceView` stays `OLLMcoder.SourceView` in `liboccoder/SourceView.vala`. Step 2 merges the smoke editor into that file, diffs included.
- ℹ️ The review bar stays `OLLMcoder.Diff.ReviewBar` in `liboccoder/Diff/ReviewBar.vala`. Step 2 merges the smoke bar into that file.
- 🔷 `Form` and `Slot` go in `liboccoder/namespace.vala`, inside `namespace OLLMcoder`. `File`, `Folder`, the selectors, and `CoderView` all take `Form`.

---

## Step 1 — `Folder`, `File`, and the selectors

These types have no twin in the library. `CoderView` does not land here. It constructs the smoke editor, and that editor is Step 2.

- 🔷 ⏳ The Homes list for `Folder`, `File`, `SelectorPull`, `ProjectSelector`, and `Form` is in `liboccoder`, and `liboccoder/meson.build` lists those files.
- ℹ️ The smoke executable keeps compiling the example copies until Step 3. `--selectors`, `--phone`, and `--tablet` do not change in this step.

### Wiring

The moved files call each other. The demo does not call them until Step 3.

#### `liboccoder/meson.build` — compile the new files

**Why:** the library build is what makes `OLLMcoder.Folder`, `OLLMcoder.File`, and the selectors exist.

**Where:** `occoder_src`, after `'SourceView.vala'`. `namespace.vala` is not in that list today. The enums will not compile unless it is added.

**Depends on:** none.

#### Add

```meson
  'namespace.vala',
  'SelectorPull.vala',
  'ProjectSelector.vala',
  'Folder/TreeStore.vala',
  'Folder/Tree.vala',
  'Folder/Browse.vala',
  'File/ListStore.vala',
  'File/List.vala',
  'File/Nav.vala',
  'File/Overlay.vala',
  'File/Pullout.vala',
```

#### `docs/meson.build` — same files for valadoc

**Why:** valadoc lists `liboccoder` sources itself. A type missing here is missing from the docs build.

**Where:** the `liboccoder` source list. `../liboccoder/namespace.vala` is already there. Do not add a `Form.vala` line.

**Depends on:** the meson list above.

#### Add

```meson
    '../liboccoder/SelectorPull.vala',
    '../liboccoder/ProjectSelector.vala',
    '../liboccoder/Folder/TreeStore.vala',
    '../liboccoder/Folder/Tree.vala',
    '../liboccoder/Folder/Browse.vala',
    '../liboccoder/File/ListStore.vala',
    '../liboccoder/File/List.vala',
    '../liboccoder/File/Nav.vala',
    '../liboccoder/File/Overlay.vala',
    '../liboccoder/File/Pullout.vala',
```

#### Moved files — constructors call the new names

**Why:** `Nav` builds the tree and the file list. `Overlay` and `Pullout` build the folder browser. The stores build their child segments.

**Where:** the library copies, at the existing `new` calls. The example copies keep the old names until Step 3.

**Depends on:** the files existing under Homes.

- 🔷 `File/Nav.vala`: `new FolderTree()` is `new Tree()`. `new FileList(...)` is `new List(...)`. The property type `FolderTree` is `Tree`.
- 🔷 `File/List.vala`: `new FileListStore()` is `new ListStore()`. The property type `FileListStore` is `ListStore`.
- 🔷 `Folder/Tree.vala`: `new FolderTreeStore()` is `new TreeStore()`. The property type `FolderTreeStore` is `TreeStore`.
- 🔷 `Folder/TreeStore.vala`: `new FolderTreeStore.child(this)` is `new TreeStore.child(this)`.
- 🔷 `File/Overlay.vala` and `File/Pullout.vala`: `new FolderBrowse(...)` is `new Folder.Browse(...)`.
- ℹ️ `Form` and `SelectorPull` stay unqualified. They are in the parent namespace `OLLMcoder`.
- ℹ️ `folder_tree` stays the property name on `File.Nav`. Step 3's empty-list check uses it.

### Issues

- ℹ️ `OLLMfiles.Folder` and `OLLMfiles.File` stay fully qualified. Inside `namespace OLLMcoder.Folder`, a bare `Folder` is that namespace. Inside `namespace OLLMcoder.File`, a bare `File` is that namespace. The smoke files already spell `OLLMfiles.Folder` and `OLLMfiles.File`.
- ℹ️ `liboccoder/List/` is already `OLLMcoder.List` (`SortedList`). `File.List` does not go there.
- ℹ️ `FileDropdown` stays `OLLMcoder.FileDropdown` at the top level. It is not `OLLMcoder.File`.
- ℹ️ `FileConnectionAdd.vala` starts with `File` and is `OLLMapp.SettingsDialog`. It is on the Android executable only. It does not join `OLLMcoder.File`.
- ℹ️ Two copies exist from the end of this step until Step 3. The library side uses the new names. The example side still uses `FolderTree`, `FileNav`, and the rest. A fix on one side only will not be the code the demo runs.
- ℹ️ `{@link FolderTree}` and `{@link FileList}` move with the types. From outside the new namespace they are `OLLMcoder.Folder.Tree` and `OLLMcoder.File.List`.

---

## Step 2 — `CoderView`, the editor, and the diffs

`CoderView` is the screen. Project and file selection live on that screen. `SourceView` is the editor: buffer, gutter, diff, review bar, and the save button. There is no second header.

- 🔷 ⏳ `CoderView` lives in `liboccoder/CoderView.vala` and constructs `SourceView`, `File.Overlay`, `File.Pullout`, and `ProjectSelector`.
- 🔷 ⏳ `SourceView` does not build `ProjectDropdown` or `FileDropdown`. Constructing it does not send `Folder.fetch_files`.
- 🔷 ⏳ `AgentFactory`, `AgentPi/Factory`, and `Skill/Factory` put `CoderView` in the tab.
- 🔷 ⏳ The search bar is the one `CoderView` draws, driven by `find` and `find_again`.
- 🔷 ⏳ `save_button` is packed on the `CoderView` top bar. `source_view` can take focus after a search hit. `file_changed` updates the file button.
- 🔷 ⏳ The review bar on the editor is `OLLMcoder.Diff.ReviewBar`.
- ℹ️ The smoke `ReviewBar.vala` and `SourceView.vala` are retired in Step 3.

### Wiring

#### `liboccoder/SourceView.vala` — the editor, nothing else

**Why:** the library file still builds the old project dropdown and file dropdown, and connects `active_project_changed` to `apply_manager_state`. That is the other design. The smoke `examples/oc-test-source-diff/SourceView.vala` is this editor.

**Where:** `liboccoder/SourceView.vala`. Namespace stays `OLLMcoder`. `new ReviewBar(this)` in the smoke file is `new OLLMcoder.Diff.ReviewBar(this)`.

**Depends on:** none.

- 🔷 Drop `project_dropdown`, `file_dropdown`, the header box, `apply_manager_state`, `on_project_selected`, `on_file_selected`, and `open_project`'s dropdown update.
- 🔷 Drop `create_search_bar` and the search fields. Ctrl+F emits `find`. Ctrl+G emits `find_again`.
- 🔷 `save_button` and `source_view` are public. `file_changed` fires after `this.current_file = file`.
- ℹ️ The scroll blocker that reads `project_dropdown.popup` goes away with the dropdowns.
- ℹ️ `update_diff_old` stays on `OLLMcoder.Diff.ReviewBar`. The pair window still calls it. The editor still calls `show_diff`.

#### `liboccoder/CoderView.vala` — one screen

**Why:** this joins the project button, the file button, and the editor.

**Where:** the constructor copied from `examples/oc-test-source-diff/CoderView.vala`. `namespace OLLMapp` becomes `namespace OLLMcoder`.

**Depends on:** the editor above, and Step 1.

#### Remove

```vala
		private SourceView editor;
```

#### Replace with

```vala
		public SourceView editor { get; private set; }
```

#### Remove

```vala
			this.files = new FileOverlay(manager, form);
			if (form == Form.PHONE) {
				this.files = new FilePullout(manager, form, this.selector);
			}
			this.editor = new SourceView(manager) {
```

#### Replace with

```vala
			this.files = new File.Overlay(manager, form);
			if (form == Form.PHONE) {
				this.files = new File.Pullout(manager, form, this.selector);
			}
			this.editor = new SourceView(manager) {
```

The field type `FileNav` becomes `File.Nav`. The casts to `FileOverlay` become `File.Overlay`. `chosen` → `open_file`, `file_changed`, `find`, and `find_again` stay connected as they are.

#### `ProjectSelector` — the restored project name

**Why:** a chat restore used to paint the project name on `ProjectDropdown`. That dropdown is gone. The project button is `ProjectSelector`.

**Where:** `label` on `ProjectSelector`.

**Depends on:** `CoderView`.

#### Remove

```vala
		private Gtk.Label label;
```

#### Replace with

```vala
		public Gtk.Label label { get; private set; }
```

#### The three factories — host `CoderView`

**Why:** the tab is the coder screen. `apply_manager_state` only updated the dropdowns.

**Where:** `liboccoder/AgentFactory.vala`, `liboccoder/AgentPi/Factory.vala`, and `liboccoder/Skill/Factory.vala`. The same two edits in each. `AgentFactory` is shown.

**Depends on:** `CoderView` and the public `editor` and `label`.

#### Remove

```vala
		private OLLMcoder.SourceView? widget = null;
```

#### Replace with

```vala
		private CoderView? widget = null;
```

#### Remove

```vala
				this.widget = new OLLMcoder.SourceView(this.project_manager);
```

#### Replace with

```vala
				this.widget = new CoderView(this.project_manager, Form.DESKTOP);
```

#### Remove

```vala
				yield this.widget.apply_manager_state();
```

#### Replace with

```vala
				if (this.project_manager.active_project != null) {
					this.widget.projects.label.label =
						this.project_manager.active_project.path_basename;
					this.widget.projects.button.tooltip_text =
						this.project_manager.active_project.path;
					this.widget.files.project = this.project_manager.active_project;
				}
				if (this.project_manager.active_file != null) {
					yield this.widget.editor.open_file(this.project_manager.active_file);
				}
```

`AgentPi/Factory.vala` and `Skill/Factory.vala` use `OLLMcoder.SourceView` the same way. `Skill/Factory.vala` keeps `ProgressView` where it is.

#### `liboccoder/meson.build` and `docs/meson.build` — `CoderView.vala`

**Why:** Step 1 did not list the screen.

**Where:** both source lists, after `ProjectSelector.vala`.

**Depends on:** `CoderView.vala` existing.

#### Add

`liboccoder/meson.build`:

```meson
  'CoderView.vala',
```

`docs/meson.build`:

```meson
    '../liboccoder/CoderView.vala',
```

### Issues

- ℹ️ The smoke editor is the library `SourceView`. It has no dropdown header. `save_button` and `source_view` are already public on that copy. `file_changed`, `find`, and `find_again` are already there.
- ℹ️ The library constructor today connects `active_project_changed` to `apply_manager_state`, and that calls `FileDropdown.update_project` (`Folder.fetch_files`). That connection is dropped with the dropdowns. That is the 2026-10-10 bug if it stays.
- ℹ️ Ignoring whitespace, the smoke `ReviewBar` is the library `ReviewBar` minus `update_diff_old`. `update_diff_old` stays on `OLLMcoder.Diff.ReviewBar` because the pair window calls it.

---

## Step 3 — Demo uses the library

- 🔷 ⏳ The smoke window constructs `OLLMcoder.CoderView`.
- 🔷 ⏳ The example copies of the Step 1 types, `CoderView.vala`, `SourceView.vala`, and `ReviewBar.vala` are gone.
- 🔷 ⏳ `--selectors`, `--phone`, and `--tablet` behave as in 4.2.5.
- 🔷 ⏳ A baseline/current pair with no selector flag still opens `show_diff` and `update_diff_old`.

### Wiring

The smoke window is `namespace OLLMapp`. After this step the screen and the selectors are `namespace OLLMcoder`, so the calls are qualified.

#### `examples/oc-test-source-diff.vala` — construct the library screen

**Why:** this is the demo entry. `--selectors`, `--phone`, and `--tablet` go through `CoderView`. A run that also has file pairs builds the selector row itself.

**Where:** the field types, the selector setup, and the pair-path casts. The `new OLLMcoder.SourceView(...)` call in the pair window is not in this edit.

**Depends on:** Step 2.

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

`this.coder.files.folder_tree.folders.flat` stays. `folder_tree` was not renamed.

Delete `examples/oc-test-source-diff/namespace.vala`. `Form` and `Slot` now live in `liboccoder/namespace.vala`.

#### `examples/meson.build` — stop compiling the copies

**Why:** two copies of `CoderView` and `SourceView` in one binary will not compile. Both executables list the same smoke files.

**Where:** the Android `oc-test-source-diff` `sources` array, and the desktop `test_source_diff` `sources` array.

**Depends on:** the `oc-test-source-diff.vala` edits above.

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

- ℹ️ `examples/meson.build` lists those sources twice. The Android `oc-test-source-diff` executable and the desktop `test_source_diff` executable both drop the moved files in this step. `FileConnectionAdd.vala` stays on the Android list.
- ℹ️ Deleting the example `SourceView.vala` while `CoderView.vala` still says `new SourceView` inside `namespace OLLMapp` binds the wrong type. The type change and the delete are one step.
- ℹ️ `Form` in `examples/oc-test-source-diff/namespace.vala` goes away once the screen uses the library enum. Leaving both `Form` enums compiles, and they will drift.
- ℹ️ The pair window constructs `OLLMcoder.SourceView` and calls `show_diff` and `update_diff_old`. After Step 2 that editor has no dropdown header.
- ℹ️ `scripts/android/build-source-diff-apk.sh` packages this same smoke window. The Android list and the desktop list have to match apart from `FileConnectionAdd.vala` and the Android C sources.

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
