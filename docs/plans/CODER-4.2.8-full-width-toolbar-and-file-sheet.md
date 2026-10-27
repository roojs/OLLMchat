# CODER-4.2.8 Full-width coder toolbar and file sheet

**Status:** ⏳ proposed

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan** until it is done and archived.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala code must follow `docs/coding-standards.md`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

---

## Purpose

- 🔷 The coder header spans the right pane only. It has to span the whole content width, chat and editor together.
- 🔷 The application exposes an empty gap. The coder inserts its toolbar into that gap.
- 🔷 The file sheet covers the editor column only. It has to cover the whole content area, including the chat on the left.
- 🔷 The application exposes that overlay. The file picker uses it.
- 💩 ⏳ The application header (history, new chat, agent, settings, about) stays. The new gap is a strip under that header and the banners, above the chat|editor split.
- 💩 ⏳ The history sidebar stays beside that column. The strip and the overlay do not cover the sidebar.
- 💩 ⏳ The project list and its shade stay on the editor column.
- 💩 ⏳ Phone keeps the header inside the coder page. Chat is a different page there, so there is no side-by-side chat to cover.
- 💩 ⏳ The strip is hidden while no coder page is mapped. Browser, a hidden right pane, and another agent take the previous header and file sheet off the slots.
- ℹ️ `CoderView` is the right-pane page. Desktop hosts it from `ollmapp/WindowPane.vala`. Android tablet hosts chat and the pane side by side in `ollmapp/android/OllmchatWindow.vala`.
- ℹ️ The smoke window has no chat pane. It packs the same two widgets around `CoderView` so the constructor has one path.

---

## Current behaviour

- ℹ️ Desktop content is `Adw.ToolbarView`, then `Adw.OverlaySplitView`, then `WindowPane`. The paned start child is the chat. The end child is the right-pane stack. `CoderView` is one page of that stack.
- ℹ️ `CoderView` appends its header, then the editor. Desktop adds the file sheet with `editor_layer.add_overlay`. Tablet builds a second overlay over the coder column and puts the sheet there.
- ℹ️ `ChatDesktopInterface` already returns the right-pane stack as `GLib.Object`. The shell casts it at the call site. The new slots use that same shape.

---

## Proposed behaviour

- 🔷 Desktop `WindowPane` is a vertical box.
  - Top child: empty `Gtk.Box` `coder_toolbar`, hidden until a coder fills it.
  - Bottom child: `Gtk.Overlay` `coder_cover`. Its child is the existing paned (chat | right pane).
- 🔷 Android tablet uses the same two widgets. `coder_toolbar` is the first child of `chat_container`. `coder_cover`'s child is the horizontal chat|pane box.
- 🔷 `ChatDesktopInterface.coder_toolbar()` and `coder_cover()` return those widgets. Factories cast to `Gtk.Box` and `Gtk.Overlay`.
- 🔷 Desktop and tablet `CoderView` do not parent the header or the file sheet themselves.
  - On `map`, the header is the only child of `coder_toolbar`, and that strip is shown. The file sheet is added to `coder_cover`.
  - On `unmap`, that header is removed. The strip hides when it has no child. The file sheet is removed from `coder_cover`.
  - A sheet that was open stays open across a hide and show. `visible` is left alone.
- 🔷 Phone still appends the header to itself. It does not use the two slots. Callers still pass them.
- 💩 The search bar stays on the bottom of the editor.

---

## Phase 1 — Application slots

- 🔷 ⏳ Add the two interface methods.
- 🔷 ⏳ Build the strip and the cover on the desktop window and on the Android window.
- 🔷 ⏳ Pack them on desktop, and on Android tablet.
- 💩 ⏳ Android phone still constructs the two widgets so the interface methods have something to return. Phone does not pack them. `Form.PHONE` never inserts into them.

### 1. `libollmchat/ChatDesktopInterface.vala` — `coder_toolbar` and `coder_cover`

**Why:** Factories already reach the window through this interface. The coder needs a full-width strip and a full-area overlay.

**Where:** interface body, after `window_config()`.

**Depends on:** none.

#### Add — after `window_config()`, before the interface closing brace. Two host slots.

```vala
		/**
		 * Full-width strip above the chat and the right pane.
		 *
		 * The shell casts this to ''Gtk.Box''. A desktop or tablet
		 * coder inserts its header here while that page is mapped.
		 * The strip is hidden while it has no child.
		 *
		 * @return toolbar slot as {@link GLib.Object}
		 */
		public abstract GLib.Object coder_toolbar();

		/**
		 * Overlay over the chat and the right pane.
		 *
		 * The shell casts this to ''Gtk.Overlay''. The child is the
		 * split. A desktop or tablet file sheet is an overlay child
		 * while that coder page is mapped.
		 *
		 * @return cover as {@link GLib.Object}
		 */
		public abstract GLib.Object coder_cover();
```

### 2. `ollmapp/WindowPane.vala` — vertical strip above the paned

**Why:** This box already wraps the chat|editor paned. The strip and the cover have to be that wide.

**Where:** fields next to `tab_view`, then `WindowPane()`.

**Depends on:** none.

#### Add — fields, after `public Adw.ViewStack tab_view;`. The two slots.

```vala
		/**
		 * Full-width coder header strip. Hidden while empty.
		 */
		public Gtk.Box coder_toolbar { get; private set; }

		/**
		 * Overlay whose child is the chat|editor paned.
		 * The file sheet is added here by the mapped coder.
		 */
		public Gtk.Overlay coder_cover { get; private set; }
```

#### Remove

```vala
			Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
```

#### Replace with — vertical, so the strip sits above the paned.

```vala
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
```

#### Remove

```vala
			// Append paned to this box
			this.append(this.paned);
```

#### Replace with — strip, then a cover whose child is the paned.

```vala
			this.coder_toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				visible = false,
			};
			this.coder_cover = new Gtk.Overlay() {
				hexpand = true,
				vexpand = true,
				child = this.paned,
			};
			this.append(this.coder_toolbar);
			this.append(this.coder_cover);
```

### 3. `ollmapp/Window.vala` — `coder_toolbar()` and `coder_cover()`

**Why:** The desktop window is the `ChatDesktopInterface` the factories cast.

**Where:** after `tab_view()`.

**Depends on:** §2.

#### Add — after `tab_view()`. Return the pane slots.

```vala
		public GLib.Object coder_toolbar()
		{
			return this.window_pane.coder_toolbar;
		}

		public GLib.Object coder_cover()
		{
			return this.window_pane.coder_cover;
		}
```

### 4. `ollmapp/android/OllmchatWindow.vala` — same two slots

**Why:** Tablet chat sits on the left of the pane, same gap as desktop.

**Where:** fields next to `pane_stack`. Construct the widgets next to `pane_stack`. Pack them in the tablet branch of `initialize_client`. Methods after `tab_view()`.

**Depends on:** §1.

#### Add — fields, after `private Adw.ViewStack pane_stack;`.

```vala
		private Gtk.Box coder_toolbar;
		private Gtk.Overlay coder_cover;
```

#### Add — in the constructor, after the `pane_stack` initializer. Widgets exist before the tablet branch packs them.

```vala
			this.coder_toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				visible = false,
			};
			this.coder_cover = new Gtk.Overlay() {
				hexpand = true,
				vexpand = true,
			};
```

#### Remove

```vala
				columns.append(this.pane_stack);
				this.chat_container.append(columns);
```

#### Replace with — tablet packs the strip, then the cover around chat|pane.

```vala
				columns.append(this.pane_stack);
				this.coder_cover.set_child(columns);
				this.chat_container.append(this.coder_toolbar);
				this.chat_container.append(this.coder_cover);
```

#### Add — after `tab_view()`. Phone returns the widgets and does not pack them.

```vala
		public GLib.Object coder_toolbar()
		{
			return this.coder_toolbar;
		}

		public GLib.Object coder_cover()
		{
			return this.coder_cover;
		}
```

---

## Phase 2 — Coder inserts the header and the file sheet

- 🔷 ⏳ `CoderView` takes the strip and the cover.
- 🔷 ⏳ Desktop and tablet parent the header and the file sheet from `map` and `unmap`. Phone still parents the header itself.
- 🔷 ⏳ The three factories pass the host slots.
- 🔷 ⏳ The smoke window packs the strip and the cover for desktop and tablet. Phone smoke keeps today's pull cover.
- 💩 ⏳ No new method. The `map` and `unmap` handlers sit in the constructor, which already owns this wiring.

### 5. `liboccoder/CoderView.vala` — place the header and the file sheet

**Why:** The header and the file sheet are built here. This is the coder inserting them into the host gap and the host overlay.

**Where:** class doc, constructor signature, then the block that parents `header` and adds the file sheet to `editor_layer`.

**Depends on:** Phase 1.

#### Remove

```vala
	 * var coder = new CoderView(manager, Form.DESKTOP);
	 * window.child = coder;
```

#### Replace with — example matches the new signature. The host owns the strip and the cover.

```vala
	 * var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
	 * var cover = new Gtk.Overlay();
	 * var coder = new CoderView(manager, Form.DESKTOP, toolbar, cover);
	 * cover.child = coder;
```

#### Remove

```vala
		 * @param manager Connected manager whose projects are already loaded
		 * @param form Desktop, phone, or tablet
		 */
		public CoderView(OLLMfiles.ProjectManager manager, Form form)
```

#### Replace with — `toolbar` is the host strip. `cover` is the host overlay. Phone receives both and does not insert into them.

```vala
		 * @param manager Connected manager whose projects are already loaded
		 * @param form Desktop, phone, or tablet
		 * @param toolbar Full-width strip. Desktop and tablet insert
		 *   the header here on map.
		 * @param cover Overlay over the chat and the editor. Desktop
		 *   and tablet add the file sheet here on map.
		 */
		public CoderView(
			OLLMfiles.ProjectManager manager,
			Form form,
			Gtk.Box toolbar,
			Gtk.Overlay cover)
```

#### Remove

```vala
			editor_layer.add_overlay(this.projects.shade);
			editor_layer.add_overlay(this.projects.list);
			if (form == Form.DESKTOP) {
				editor_layer.add_overlay(((File.Overlay) this.files).list);
			}
			if (form == Form.TABLET) {
				var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
					hexpand = true,
					vexpand = true,
				};
				column.append(header);
				column.append(editor_layer);
				var cover = new Gtk.Overlay() {
					hexpand = true,
					vexpand = true,
					child = column,
				};
				var sheet = ((File.Overlay) this.files).list;
				sheet.halign = Gtk.Align.FILL;
				sheet.valign = Gtk.Align.FILL;
				cover.add_overlay(sheet);
				this.append(cover);
			}
			if (form != Form.TABLET) {
				this.append(header);
				this.append(editor_layer);
			}
```

#### Replace with — project shade and list stay on the editor. Desktop and tablet lend the header and the file sheet to the host while mapped. Phone keeps the header.

```vala
			editor_layer.add_overlay(this.projects.shade);
			editor_layer.add_overlay(this.projects.list);
			if (form == Form.PHONE) {
				this.append(header);
			}
			if (form != Form.PHONE) {
				this.map.connect(() => {
					var child = toolbar.get_first_child();
					while (child != null) {
						var next = child.get_next_sibling();
						if (child != header) {
							toolbar.remove(child);
						}
						child = next;
					}
					if (header.parent != toolbar) {
						toolbar.append(header);
					}
					toolbar.visible = true;
					var sheet = ((File.Overlay) this.files).list;
					if (form == Form.TABLET) {
						sheet.halign = Gtk.Align.FILL;
						sheet.valign = Gtk.Align.FILL;
					}
					cover.add_overlay(sheet);
				});
				this.unmap.connect(() => {
					if (header.parent == toolbar) {
						toolbar.remove(header);
					}
					toolbar.visible = toolbar.get_first_child() != null;
					cover.remove_overlay(((File.Overlay) this.files).list);
				});
			}
			this.append(editor_layer);
```

### 6. `liboccoder/namespace.vala` — `Form` example

**Why:** The documented constructor call has to compile against §5.

**Where:** `Form` example.

**Depends on:** §5.

#### Remove

```vala
	 * Desktop draws the lists on the editor. Phone and tablet
	 * use {@link SelectorPull}.
```

#### Replace with

```vala
	 * Desktop draws the project list on the editor. The file
	 * sheet uses the host cover. Phone and tablet project
	 * selection uses {@link SelectorPull}.
```

#### Remove

```vala
	 * var coder = new CoderView(manager, Form.PHONE);
```

#### Replace with

```vala
	 * var coder = new CoderView(manager, Form.PHONE, toolbar, cover);
```

### 7. `liboccoder/File/Overlay.vala` — sheet covers the host overlay

**Why:** The class comment still says the sheet covers the editor.

**Where:** class overview, first sentence and the example.

**Depends on:** §5.

#### Remove

```vala
	 * Desktop file sheet. Covers the editor.
```

#### Replace with

```vala
	 * Desktop file sheet. Covers the host overlay.
```

#### Remove

```vala
	 * var files = new Overlay(manager);
	 * editor_layer.add_overlay(files.list);
```

#### Replace with

```vala
	 * var files = new Overlay(manager, Form.DESKTOP);
	 * cover.add_overlay(files.list);
```

### 8. Factories — pass the host slots

**Why:** Each coder page is built in `activate`, which already has the host.

**Where:** the `new CoderView` / `new OLLMcoder.CoderView` call.

**Depends on:** §1 and §5.

#### `liboccoder/AgentFactory.vala`

##### Remove

```vala
				this.widget = new CoderView(this.project_manager, this.form);
```

##### Replace with

```vala
				this.widget = new CoderView(
					this.project_manager,
					this.form,
					(Gtk.Box) host.coder_toolbar(),
					(Gtk.Overlay) host.coder_cover());
```

#### `liboccoder/AgentPi/Factory.vala`

##### Remove

```vala
				this.widget = new OLLMcoder.CoderView(
					this.project_manager, this.form);
```

##### Replace with

```vala
				this.widget = new OLLMcoder.CoderView(
					this.project_manager,
					this.form,
					(Gtk.Box) ui.coder_toolbar(),
					(Gtk.Overlay) ui.coder_cover());
```

#### `liboccoder/Skill/Factory.vala`

##### Remove

```vala
				this.widget = new OLLMcoder.CoderView(
					this.project_manager, this.form);
```

##### Replace with

```vala
				this.widget = new OLLMcoder.CoderView(
					this.project_manager,
					this.form,
					(Gtk.Box) host.coder_toolbar(),
					(Gtk.Overlay) host.coder_cover());
```

### 9. `examples/oc-test-source-diff.vala` — smoke packs the same slots

**Why:** The constructor now requires the strip and the cover. Desktop and tablet smoke have no application window, so the example owns the two widgets and packs them around the coder. Phone smoke still uses the pull cover. It passes the widgets and does not pack them.

**Where:** fields next to `coder`. Construction where `CoderView` is created. Window child where `show_pull` chooses the root.

**Depends on:** §5.

#### Add — fields, after `private OLLMcoder.CoderView coder;`.

```vala
		private Gtk.Box coder_toolbar;
		private Gtk.Overlay coder_cover;
```

#### Remove

```vala
					var coder = new OLLMcoder.CoderView(manager, form);
```

#### Replace with — build the strip and the cover, then the coder.

```vala
					this.coder_toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
						hexpand = true,
						visible = false,
					};
					this.coder_cover = new Gtk.Overlay() {
						hexpand = true,
						vexpand = true,
					};
					var coder = new OLLMcoder.CoderView(
						manager, form, this.coder_toolbar, this.coder_cover);
```

#### Remove

```vala
				if (!this.show_pull) {
					this.window.child = host;
				}
				if (this.show_pull) {
					var cover = new Gtk.Overlay() {
						hexpand = true,
						vexpand = true,
					};
					cover.set_child(host);
					cover.add_overlay(this.selector_pull);
					this.window.child = cover;
				}
```

#### Replace with — desktop and tablet put the strip above the cover. Phone keeps the pull cover. `host` is still the coder, or the Android column that wraps it.

```vala
				if (!opt_phone) {
					this.coder_cover.set_child(host);
					if (opt_tablet) {
						this.coder_cover.add_overlay(this.selector_pull);
					}
					var screen = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
						hexpand = true,
						vexpand = true,
					};
					screen.append(this.coder_toolbar);
					screen.append(this.coder_cover);
					this.window.child = screen;
				}
				if (opt_phone) {
					var cover = new Gtk.Overlay() {
						hexpand = true,
						vexpand = true,
					};
					cover.set_child(host);
					cover.add_overlay(this.selector_pull);
					this.window.child = cover;
				}
```

---

## LLM notes

- 🚫 Do not pack the coder header into `Adw.HeaderBar`.
- 🚫 Do not move the project shade or the project list onto `coder_cover` unless the user promotes that suggestion.
- 🚫 Do not reparent the phone header or the phone pull-over.
- 🚫 Do not move the editor search bar.
