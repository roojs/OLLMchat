# CODER-4.2.6.1 Coder screen mainline — Step 2

**Status:** done — Step 2 merged to mainline

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan** until it is done and archived.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala code must follow `docs/coding-standards.md`.

**Parent:** [`CODER-4.2.6-DONE-file-nav-mainline.md`](CODER-4.2.6-DONE-file-nav-mainline.md) — Step 2.

---

## Purpose

- 🔷 ✔️ Copy the tracked smoke `SourceView.vala` and `CoderView.vala`
  byte-for-byte into `liboccoder`, then adapt both copies in a separate step.
- 🔷 ✔️ Put `CoderView` in the three coder factory tabs and restore the active
  project and file through the selector screen.
- 🔷 ✔️ The application chooses `Form.DESKTOP`, `Form.PHONE`, or
  `Form.TABLET` and passes it into each factory. Factories do not hardcode
  desktop layout.
- 🔷 ✔️ Add `CoderView.vala` to the library and valadoc source lists.
- ℹ️ `liboccoder/Diff/ReviewBar.vala` already contains the smoke behavior plus
  `update_diff_old`; Step 2 does not edit it.
- ℹ️ Step 3 in the parent plan exports the screen and navigation types for the smoke executable through `occoder.vapi`.

Edits below are **Remove** / **Replace with** / **Add** from the current tree.
Verify surrounding context before applying.

---

## Step 1 — exact smoke copies

### 1. `SourceView.vala` and `CoderView.vala` — copy both tracked files unchanged

**Why:** both tracked smoke files are the authoritative promotion baseline.
Manual reconstruction risks omitting behavior or mixing adaptations into the
copy-review checkpoint.

**Where:** copy the complete tracked files to their library destinations:
`examples/oc-test-source-diff/SourceView.vala` to
`liboccoder/SourceView.vala`, and
`examples/oc-test-source-diff/CoderView.vala` to
`liboccoder/CoderView.vala`.

**Depends on:** none.

- 🔷 ✔️ Copy both files byte-for-byte, unchanged. Do not edit namespaces,
  types, fields, methods, or docblocks during Step 1.
- 🔷 ✔️ Verify each destination is byte-identical to its tracked source before
  beginning Step 2.
- 🔷 ✔️ Verified with `cmp -s` and matching SHA-256 for both pairs (2026-10-26).
- 🔷 These are actual file copies, not manually reconstructed or newly
  authored files.
- ℹ️ The copied file already contains public `save_button` and `source_view`;
  `file_changed`, `find`, and `find_again`; screen-owned dropdown/search
  behavior; save-time `show_pending_diff`; and all existing
  diff/gutter/pending-review methods.

## Step 2 — adapt both copied files ✔️

### 2. `liboccoder/SourceView.vala` — apply library namespace and review types

**Why:** after the complete copy, only the namespace and review-bar type names
differ between the smoke app and `liboccoder`.

**Where:** the just-copied `liboccoder/SourceView.vala`, at the namespace,
review-bar field, review-bar construction, and response-list construction.

**Depends on:** §1.

#### Remove

```vala
namespace OLLMapp
```

#### Replace with

```vala
namespace OLLMcoder
```

#### Remove

```vala
			private ReviewBar review_bar;
```

#### Replace with

```vala
			private OLLMcoder.Diff.ReviewBar review_bar;
```

#### Remove

```vala
				this.review_bar = new ReviewBar(this);
```

#### Replace with

```vala
				this.review_bar = new OLLMcoder.Diff.ReviewBar(this);
```

#### Remove

```vala
				this.review_bar.responses(new Gee.ArrayList<ReviewResponse>());
```

#### Replace with

```vala
				this.review_bar.responses(new Gee.ArrayList<OLLMcoder.Diff.ReviewResponse>());
```

- 🔷 ✔️ Applied the four listed substitutions. All other bytes from the
  tracked smoke `SourceView.vala` remain untouched
  in Step 2.

### 3. `liboccoder/CoderView.vala` — apply library namespace and navigation types

**Why:** after the complete copy, only the namespace, renamed `File` types,
and factory-visible editor property differ from the tracked smoke file.

**Where:** the just-copied `liboccoder/CoderView.vala`, at every exact
occurrence listed below.

**Depends on:** §1.

#### Remove

```vala
namespace OLLMapp
```

#### Replace with

```vala
namespace OLLMcoder
```

#### Remove

```vala
	 * The header is {@link ProjectSelector}, {@link FileNav}, and
```

#### Replace with

```vala
	 * The header is {@link ProjectSelector}, {@link File.Nav}, and
```

#### Remove

```vala
		public FileNav files { get; private set; }
```

#### Replace with

```vala
		public File.Nav files { get; private set; }
```

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
```

#### Replace with

```vala
			this.files = new File.Overlay(manager, form);
```

#### Remove

```vala
				this.files = new FilePullout(manager, form, this.selector);
```

#### Replace with

```vala
				this.files = new File.Pullout(manager, form, this.selector);
```

#### Remove

```vala
				((FileOverlay) this.files).list.visible = false;
```

#### Replace with

```vala
				((File.Overlay) this.files).list.visible = false;
```

#### Remove

```vala
				editor_layer.add_overlay(((FileOverlay) this.files).list);
```

#### Replace with

```vala
				editor_layer.add_overlay(((File.Overlay) this.files).list);
```

#### Remove

```vala
				var sheet = ((FileOverlay) this.files).list;
```

#### Replace with

```vala
				var sheet = ((File.Overlay) this.files).list;
```

- 🔷 ✔️ Applied the nine listed substitutions. All other bytes from the
  tracked smoke `CoderView.vala` remain untouched
  in Step 2.

---

## Review bar

### 4. `liboccoder/Diff/ReviewBar.vala` — no edit required

**Why:** the library file already contains the smoke review behavior in
`namespace OLLMcoder.Diff`, with references to `OLLMcoder.SourceView`, plus the
one library-only compatibility method.

**Where:** the complete current file.

**Depends on:** §§2–3.

- ℹ️ A method-by-method comparison with
  `examples/oc-test-source-diff/ReviewBar.vala` shows the smoke constructor,
  signals, response menu, hunk map, pending queue, `update_diff()`, apply, and
  bulk-decision flows are already present.
- ℹ️ `update_diff_old()` is the intentional extra library behavior and must
  remain.
- ℹ️ The baseline/current pair window depends on `update_diff_old()`.
- ℹ️ No `Remove`, `Replace with`, or `Add` fence is published because this file
  requires no implementation edit.
- 🔷 ✔️ Verified smoke parity and `update_diff_old()` presence; no edit applied
  (2026-10-26).

### 5. `liboccoder/ProjectSelector.vala` — `label`: expose restore target

**Why:** restored manager state paints the active project on the selector after
the old `ProjectDropdown` is removed.

**Where:** the `label` field beside `manager`, `form`, and `selector`.

**Depends on:** §3.

#### Remove

```vala
		private Gtk.Label label;
```

#### Replace with

```vala
		public Gtk.Label label { get; private set; }
```

- 🔷 ✔️ Applied (2026-10-26).

### 6. `liboccoder/namespace.vala` — export the application-selected form

**Why:** public factory constructors accept the layout selected by desktop or
Android application code. Their parameter type must be present in
`occoder.vapi`.

**Where:** the `Form` enum declaration.

**Depends on:** parent Step 1.

#### Remove

```vala
	enum Form {
```

#### Replace with

```vala
	public enum Form {
```

- 🔷 ✔️ Applied (2026-10-26).

---

## Factory wiring

### 7. `liboccoder/AgentFactory.vala` — host and restore `CoderView`

**Why:** the code-assistant tab must host the complete screen and restore its
selector/file/editor state.

**Where:** the form and cached widget fields, constructor, lazy construction
in `activate()`, and the three manager-state calls in
`initialize_widget()`.

**Depends on:** §§3–6.

#### Remove

```vala
		private OLLMcoder.SourceView? widget = null;
```

#### Replace with

```vala
		private Form form;
		private CoderView? widget = null;
```

#### Add — document the application-selected layout after `@param project_manager`

```vala
		 * @param form Layout selected by the application
```

#### Remove

```vala
		public AgentFactory(OLLMfiles.ProjectManager project_manager)
```

#### Replace with

```vala
		public AgentFactory(OLLMfiles.ProjectManager project_manager, Form form)
```

#### Add — store the layout immediately after assigning `project_manager`

```vala
			this.form = form;
```

#### Remove

```vala
				this.widget = new OLLMcoder.SourceView(this.project_manager);
```

#### Replace with

```vala
				this.widget = new CoderView(this.project_manager, this.form);
```

#### Remove

```vala
				yield this.widget.manager.rpc_load_projects_from_db();
				yield this.widget.manager.restore_active_state(
					win_cfg.project,
					win_cfg.file
				);
				yield this.widget.apply_manager_state();
```

#### Replace with — restore selector, navigation, and editor at the same location

```vala
				yield this.project_manager.rpc_load_projects_from_db();
				yield this.project_manager.restore_active_state(
					win_cfg.project,
					win_cfg.file
				);
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

- 🔷 ✔️ Applied (2026-10-26).

### 8. `liboccoder/AgentPi/Factory.vala` — host and restore `CoderView`

**Why:** Agent Pi keeps its queue setup and error/notification flow while its
tab changes from the editor alone to the complete coder screen.

**Where:** the form and cached widget fields, constructor, and the existing
first-activation block in `activate()`.

**Depends on:** §§3–6.

#### Remove

```vala
		private OLLMcoder.SourceView? widget = null;
```

#### Replace with

```vala
		private OLLMcoder.Form form;
		private OLLMcoder.CoderView? widget = null;
```

#### Add — document the application-selected layout after `@param project_manager`

```vala
		 * @param form Layout selected by the application
```

#### Remove

```vala
		public Factory(OLLMfiles.ProjectManager project_manager)
		{
```

#### Replace with

```vala
		public Factory(
			OLLMfiles.ProjectManager project_manager,
			OLLMcoder.Form form
		) {
```

#### Add — store the layout immediately after assigning `project_manager`

```vala
			this.form = form;
```

#### Remove

```vala
				this.widget = new OLLMcoder.SourceView(this.project_manager);
```

#### Replace with

```vala
				this.widget = new OLLMcoder.CoderView(
					this.project_manager, this.form);
```

#### Remove

```vala
					yield this.widget.manager.rpc_load_projects_from_db();
					yield this.widget.manager.restore_active_state(
						win_cfg.project,
						win_cfg.file
					);
					yield this.widget.apply_manager_state();
```

#### Replace with — preserve Agent Pi's in-place first-activation flow

```vala
					yield this.project_manager.rpc_load_projects_from_db();
					yield this.project_manager.restore_active_state(
						win_cfg.project,
						win_cfg.file
					);
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

- 🔷 ✔️ Applied (2026-10-26).

### 9. `liboccoder/Skill/Factory.vala` — host and restore `CoderView`

**Why:** the Skills tab keeps `ProgressView`, `done_init`, and its separate
initializer while replacing only the editor surface and manager-state restore.

**Where:** the form and cached widget fields, constructor, lazy construction
in `activate()`, and the three manager-state calls in
`initialize_widget()`.

**Depends on:** §§3–6.

#### Remove

```vala
		private OLLMcoder.SourceView? widget = null;
```

#### Replace with

```vala
		private OLLMcoder.Form form;
		private OLLMcoder.CoderView? widget = null;
```

#### Add — document the constructor immediately before `public Factory(`

```vala
		/**
		 * Build the skill factory for one application layout.
		 *
		 * @param project_manager Shared project and file manager
		 * @param skills_directories Directories containing skills
		 * @param form Layout selected by the application
		 * @param skill_name Initial skill name, or empty for task creator
		 */
```

#### Remove

```vala
		public Factory(OLLMfiles.ProjectManager project_manager,
			 Gee.ArrayList<string> skills_directories, string skill_name = "")
		{
```

#### Replace with

```vala
		public Factory(
			OLLMfiles.ProjectManager project_manager,
			Gee.ArrayList<string> skills_directories,
			OLLMcoder.Form form,
			string skill_name = ""
		) {
```

#### Add — store the layout immediately after assigning `project_manager`

```vala
			this.form = form;
```

#### Remove

```vala
				this.widget = new OLLMcoder.SourceView(this.project_manager);
```

#### Replace with

```vala
				this.widget = new OLLMcoder.CoderView(
					this.project_manager, this.form);
```

#### Remove

```vala
				yield this.widget.manager.rpc_load_projects_from_db();
				yield this.widget.manager.restore_active_state(
					win_cfg.project,
					win_cfg.file
				);
				yield this.widget.apply_manager_state();
```

#### Replace with — preserve the Skills initializer and progress flow

```vala
				yield this.project_manager.rpc_load_projects_from_db();
				yield this.project_manager.restore_active_state(
					win_cfg.project,
					win_cfg.file
				);
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

- 🔷 ✔️ Applied (2026-10-26).

### 10. `ollmapp/Window.vala` — desktop application selects desktop form

**Why:** layout belongs to the application. The desktop window explicitly
passes desktop form into every coder factory.

**Where:** the three factory constructions in agent registration.

**Depends on:** §§7–9.

#### Remove

```vala
			var code_assistant = new OLLMcoder.AgentFactory(this.project_manager);
```

#### Replace with

```vala
			var code_assistant = new OLLMcoder.AgentFactory(
				this.project_manager, OLLMcoder.Form.DESKTOP);
```

#### Remove

```vala
			var agent_pi = new OLLMcoder.AgentPi.Factory(this.project_manager);
```

#### Replace with

```vala
			var agent_pi = new OLLMcoder.AgentPi.Factory(
				this.project_manager, OLLMcoder.Form.DESKTOP);
```

#### Remove

```vala
			var skill_runner = new OLLMcoder.Skill.Factory(this.project_manager, skills_dirs, "");
```

#### Replace with

```vala
			var skill_runner = new OLLMcoder.Skill.Factory(
				this.project_manager, skills_dirs, OLLMcoder.Form.DESKTOP, "");
```

- 🔷 ✔️ Applied (2026-10-26).

### 11. `ollmapp/android/OllmchatWindow.vala` — Android application selects phone or tablet form

**Why:** `android_is_tablet()` has already set `this.is_tablet` before Agent Pi
is registered. The Android application therefore owns the phone/tablet choice.

**Where:** `initialize_client()`, inside the missing-`agent-pi` registration
branch.

**Depends on:** §8.

#### Remove

```vala
				var agent_pi = new OLLMcoder.AgentPi.Factory(this.project_manager);
```

#### Replace with

```vala
				var agent_pi = new OLLMcoder.AgentPi.Factory(this.project_manager,
					this.is_tablet ? OLLMcoder.Form.TABLET : OLLMcoder.Form.PHONE);
```

- 🔷 ✔️ Applied (2026-10-26).

### 12. `examples/oc-test-skill-agent.vala` — test host selects desktop form

**Why:** the standalone skill-agent test is a desktop GTK host and must satisfy
the new explicit factory contract.

**Where:** the `OLLMcoder.Skill.Factory` construction after `skills_dirs`.

**Depends on:** §9.

#### Remove

```vala
		var factory = new OLLMcoder.Skill.Factory(project_manager, skills_dirs, "");
```

#### Replace with

```vala
		var factory = new OLLMcoder.Skill.Factory(
			project_manager, skills_dirs, OLLMcoder.Form.DESKTOP, "");
```

- 🔷 ✔️ Applied (2026-10-26).

### 13. `liboccoder/AgentPi/namespace.vala` — document the required form argument

**Why:** the namespace usage example must match the public factory
constructor.

**Where:** the `Register` example.

**Depends on:** §8.

#### Remove

```vala
 * var factory = new OLLMcoder.AgentPi.Factory(project_manager);
```

#### Replace with

```vala
 * var factory = new OLLMcoder.AgentPi.Factory(
 *     project_manager, OLLMcoder.Form.DESKTOP);
```

- 🔷 ✔️ Applied (2026-10-26).

---

## Build wiring

### 14. `liboccoder/meson.build` — compile `CoderView.vala`

**Why:** the library factories use `CoderView`.

**Where:** `occoder_src`, immediately after `'ProjectSelector.vala'`.

**Depends on:** §3.

#### Add — compile the screen after its top-level selector dependencies

```meson
  'CoderView.vala',
```

- 🔷 ✔️ Applied (2026-10-26).

### 15. `docs/meson.build` — include `CoderView.vala` in valadoc

**Why:** valadoc lists library source files independently.

**Where:** the `liboccoder` source group, immediately after
`'../liboccoder/ProjectSelector.vala'`.

**Depends on:** §§3 and 14.

#### Add — document the screen before the factories that use it

```meson
    '../liboccoder/CoderView.vala',
```

- 🔷 ✔️ Applied (2026-10-26).

---

## Verification

- 🔷 ✔️ Run the library/application build with `ninja -C build`.
- 🔷 ✔️ Run the valadoc build with `ninja -C build docs/valadoc`.

- 🔷 ✔️ Confirm `liboccoder/SourceView.vala` differs from the tracked smoke
  source only by the four substitutions in §2.
- 🔷 ✔️ Confirm `liboccoder/CoderView.vala` differs from the tracked smoke
  source only by the substitutions in §3.
- 🔷 ✔️ Confirm `liboccoder/SourceView.vala` contains no
  `ProjectDropdown`, `FileDropdown`, `project_dropdown`, `file_dropdown`,
  `search_bar`, `search_entry`, `search_context`, `create_search_bar`,
  `perform_search`, `update_search_settings`, `update_search_results`,
  `forward_search`, or `backward_search`.
- 🔷 ✔️ Confirm `SourceView()` no longer connects
  `active_project_changed`, refreshes a dropdown, or installs a dropdown
  scroll blocker.
- 🔷 ✔️ Confirm `SourceView` still constructs
  `OLLMcoder.Diff.ReviewBar`, still uses
  `OLLMcoder.Diff.ReviewResponse`, and retains all diff/gutter/pending-review
  methods.
- 🔷 ✔️ Confirm all three factory tabs construct `CoderView`, restore the
  selector/file navigation, and open the active file through `widget.editor`.
- 🔷 ✔️ Confirm no factory hardcodes `Form.DESKTOP`; desktop, Android, and the
  standalone skill test pass their selected form into factory constructors.
- 🔷 ✔️ Confirm Android passes `Form.TABLET` when `this.is_tablet` is true and
  `Form.PHONE` otherwise.

---

## Next step

- ℹ️ Step 2 is complete.
- 🔷 ✔️ Step 3 in the parent plan is agent-complete: the smoke executable uses library types and the duplicate example files are deleted.
