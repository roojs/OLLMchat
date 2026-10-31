# Phone file and project chrome

**Status:** ✅ 2026-10-31. Phone check passed with the folder tree.

Phone only, unless an item says otherwise. Tablet keeps the pane on the right, so the footer item does not apply there.

Related, closed: [`2026-10-28-FIXED-phone-project-click-does-nothing.md`](done/2026-10-28-FIXED-phone-project-click-does-nothing.md), [`2026-10-28-FIXED-phone-selector-steals-chat-focus.md`](done/2026-10-28-FIXED-phone-selector-steals-chat-focus.md).

## Problem

- 🔷 With a file open, the file-name button does not need an icon. The icon uses width on that bar.
- 🔷 The gap between the project button and the file button should be tighter on every form, so the name has more room.
- 🔷 Open a markdown file. Two icons sit to the right of the file name. Both glyphs are broken. The near one is save. The far one is the markdown toggle, and that control stays. Both names need to be added to the Android icon collection.
- 🔷 The expanded project list shows a subtext for the project that is selected. That line is not useful on the phone or the tablet. Hide it on both.
- 🔷 Recent and All have no visible difference for which one is selected.
- 🔷 In the file list, a file or folder that is down a directory shows the path as subtext. Files should not show that path. Folders keep the path. A file's subtext is the modified date, then ` - `, then the size, as in `14:32 - 24K`.
- 🔷 Tree and Recent have no distinct mark for which one is active.
- 🔷 While the file list is open, the chat composer and the model bar (the two footer rows) should be covered. The bottom of that sheet is the file search. The same cover applies while choosing a project. Tablet does not need this.

## Where the controls are

- ℹ️ The file-name button always draws `text-x-generic` beside the label. `liboccoder/File/Nav.vala`.
- ℹ️ The header is a horizontal box with spacing 6. An expanding spacer sits between the project button and the file button, and that spacer is hidden while the file button is visible. `liboccoder/CoderView.vala`.
- ℹ️ Save asks for `media-floppy`. `liboccoder/SourceView.vala`. That name is not in `android/icons/manifest`. Adwaita has no colour file for it, only `symbolic/devices/media-floppy-symbolic.svg`. Humanity ships a colour `devices/48/media-floppy.svg`. The phone theme index has no `scalable/devices` directory. `android/icons/Adwaita/index.theme`.
- ℹ️ 2026-10-29: the markdown glyph is broken too, not only save. The toggle asks for `document-print-symbolic`, and for `format-justify-left-symbolic` when source is showing. `liboccoder/CoderView.vala`. Neither name is in the manifest. Adwaita ships both under `symbolic/actions/`. The control stays.
- ℹ️ Opening the project page sets `SelectorPull.current` visible and sets its text to the selected project. `liboccoder/ProjectSelector.vala`. The label is the line under the title. `liboccoder/SelectorPull.vala`.
- ℹ️ Recent and All are toggle buttons inside the pull-over. `liboccoder/ProjectSelector.vala`. Tree and Recent are a stack switcher on the file page. `liboccoder/File/Pullout.vala`.
- ℹ️ `.selector-pull button` paints every button in the pull-over with the window background. The checked style that exists is on `.project-sheet` and `.file-sheet`, which are the desktop and tablet sheets. `resources/style.css`.
- ℹ️ Phone file and folder rows are built in `Folder.Browse.list_box_factory`. The second line is the path relative to the project, and only when that path contains a slash. `liboccoder/Folder/Browse.vala`. Size and modified text already exist as `display_size` and `display_modified` on `libocfiles/File.vala`. `display_size` is the digits, then `K`, `M`, `G`, `T`, or `P` with no space.
- ℹ️ On the phone the pull-over is an overlay on the coder column only. `liboccoder/CoderView.vala`. The composer and the model bar are the chat widget's lower box, under the coder, class `chat-composer-strip`. `libollmchatgtk/ChatWidget.vala`. The phone pane replaces the transcript and leaves that lower box in place. `ollmapp/android/OllmchatWindow.vala`.

## Proposed fix

- ✔️ Each item below is applied. Desktop `ninja` of `liboccoder`, `libollmchatgtk`, and `ollmchat` succeeded. `AgentManager.vala` is Android-only, so that file was not in the desktop link. Host icon sources for the three new manifest rows are present.
- 🔷 2026-10-29: the file button has no icon on desktop, tablet, or phone.

### `liboccoder/File/Nav.vala` — file button has no icon

**Why:** The file glyph uses width on the header. It is not kept on any form.

**Where:** Class comment, and the button built in the constructor. The label is the button's child. The extra box existed only to hold the icon.

#### Remove

```vala
	 * The resting control is a flat button with a file icon. It stays
```

#### Replace with

```vala
	 * The resting control is a flat button. It stays
```

#### Remove

```vala
			var face = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			face.append(new Gtk.Image.from_icon_name("text-x-generic"));
			face.append(this.label);
			this.button = new Gtk.Button() {
				child = face,
				hexpand = true,
				valign = Gtk.Align.CENTER,
			};
			this.button.add_css_class("flat");
```

#### Replace with

```vala
			this.button = new Gtk.Button() {
				child = this.label,
				hexpand = true,
				valign = Gtk.Align.CENTER,
				css_classes = { "flat" },
			};
```

- ✔️ 2026-10-29: applied in `liboccoder/File/Nav.vala`.

### `liboccoder/CoderView.vala` — tighter header gap

**Why:** With a file open the spacer between the project button and the file button is already hidden. The remaining gap is the header's spacing of 6, plus each button's padding. That spacing is 0 on desktop, tablet, and phone.

**Where:** The header box in the constructor.

#### Remove

```vala
			var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				valign = Gtk.Align.START,
				margin_start = 6,
				margin_end = 6,
				margin_top = 4,
				margin_bottom = 4,
			};
```

#### Replace with

```vala
			var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				valign = Gtk.Align.START,
				margin_start = 6,
				margin_end = 6,
				margin_top = 4,
				margin_bottom = 4,
				css_classes = { "coder-header" },
			};
```

- ✔️ 2026-10-29: applied in `liboccoder/CoderView.vala`.

### `resources/style.css` — header padding

**Why:** Flat buttons still keep theme padding. Less horizontal padding on the coder header gives the file name the rest of that gap. Every form uses this header.

**Where:** After `.selector-pull button.flat`.

#### Add

After the `.selector-pull button.flat` rule.

```css
.coder-header button.flat {
	padding-left: 2px;
	padding-right: 2px;
	min-width: 0;
}
```

- ✔️ 2026-10-29: applied in `resources/style.css`.

### `android/icons/manifest` — save and markdown glyphs

**Why:** Both glyphs beside a markdown file name are missing. Save stays `media-floppy`, the colour icon. Adwaita does not ship that file. Humanity does, at 48 pixels. The markdown toggle is `document-print-symbolic`, and `format-justify-left-symbolic` while source is showing. Those two already live under Adwaita's `symbolic/actions`.

**Where:** End of `android/icons/manifest`. Do not change the icon name in `liboccoder/SourceView.vala`.

#### Add

Append these rows. Columns stay tab-separated.

```
scalable/devices/media-floppy.svg	Humanity	devices/48/media-floppy.svg
symbolic/actions/document-print-symbolic.svg	Adwaita	symbolic/actions/document-print-symbolic.svg
symbolic/actions/format-justify-left-symbolic.svg	Adwaita	symbolic/actions/format-justify-left-symbolic.svg
```

- ✔️ 2026-10-29: applied in `android/icons/manifest`.

### `android/icons/Adwaita/index.theme` — devices directory

**Why:** The colour floppy is only found if `scalable/devices` is listed. The phone index does not have that directory.

**Where:** The `Directories` line, and a new section after `[scalable/places]`.

#### Remove

```
Directories=symbolic/actions,symbolic/categories,symbolic/places,symbolic/status,symbolic/ui,symbolic/mimetypes,symbolic/legacy,scalable/apps,scalable/places,scalable/mimetypes,
```

#### Replace with

```
Directories=symbolic/actions,symbolic/categories,symbolic/places,symbolic/status,symbolic/ui,symbolic/mimetypes,symbolic/legacy,scalable/apps,scalable/places,scalable/devices,scalable/mimetypes,
```

#### Add

After the `[scalable/places]` section.

```
[scalable/devices]
Context=Devices
Size=128
Type=Scalable
MinSize=1
MaxSize=512
```

- ✔️ 2026-10-29: applied in `android/icons/Adwaita/index.theme`.

### `liboccoder/SelectorPull.vala` — project line

**Why:** The project page hides the line under the title on the phone and the tablet. The phone file page still uses it for a shortened path.

**Where:** The `current` property comment.

#### Remove

```vala
		 * Line under the top bar. The project page shows the current
		 * selection. The phone file page shows the path relative to
```

#### Replace with

```vala
		 * Line under the top bar. The project page hides this line.
		 * The phone file page shows the path relative to
```

- ✔️ 2026-10-29: applied in `liboccoder/SelectorPull.vala`.

### `liboccoder/ProjectSelector.vala` — hide that line

**Why:** Opening the project page is what shows the selected project under the title. Desktop does not use this pull-over.

**Where:** `button.clicked`, the phone and tablet branch.

#### Remove

```vala
						this.selector.current.visible = true;
						this.selector.current.label = this.label.label;
						if (this.form != Form.PHONE && this.button.tooltip_text != "") {
							this.selector.current.label = this.button.tooltip_text;
						}
```

#### Replace with

```vala
						this.selector.current.visible = false;
```

- ✔️ 2026-10-29: applied in `liboccoder/ProjectSelector.vala`.

### `resources/style.css` — which toggle is selected

**Why:** `.selector-pull button` paints every button in the pull-over with the window background, so Recent, All, Tree, and Recent look the same. One checked rule covers both pairs. The toggles are inside the pull-over. The stack switcher is too.

**Where:** After the `.selector-pull` background rule.

#### Add

After the rule that sets `.selector-pull button` to the window background.

```css
.selector-pull button:checked {
	background-color: @theme_selected_bg_color;
	background-image: none;
	color: @theme_selected_fg_color;
}
```

- ✔️ 2026-10-29: applied in `resources/style.css`.

### `liboccoder/Folder/Browse.vala` — file subtext is date and size

**Why:** A file drops the path. The second line is the modified time, then ` - `, then the size from `display_size` (`24K`). A folder keeps the path.

**Where:** `list_box_factory` comment, and the block that appends the path label.

#### Remove

```vala
		 * second line is the path relative to the project, including
		 * the item name. A link uses the target path, so the line
		 * shows where it points. That line is absent at the project
		 * root. A long path drops the item name first, then keeps
		 * the first folder.
```

#### Replace with

```vala
		 * second line for a folder is the path relative to the
		 * project, including the folder name. A link uses the target
		 * path, so the line shows where it points. That line is
		 * absent at the project root. A long path drops the folder
		 * name first, then keeps the first folder. A file's second
		 * line is the modified time, then '' - '', then the size.
```

#### Remove

```vala
			var rel = item.path;
			if (item.points_to != null && item.points_to.path != "") {
				rel = item.points_to.path;
			}
			if (this.project.path != "" && rel.has_prefix(this.project.path)) {
				rel = rel.substring(this.project.path.length);
			}
			if (rel.has_prefix("/")) {
				rel = rel.substring(1);
			}
			var below = rel.contains("/");
			if (below && rel.length > 36) {
				var cut = rel.last_index_of_char('/');
				if (cut > 0) {
					rel = rel.substring(0, cut);
				}
			}
			if (below && rel.contains("/") && rel.length > 36) {
				var first = rel.index_of_char('/');
				if (first > 0) {
					rel = rel.substring(0, first) + "/…";
				}
			}
			if (below) {
				column.append(new Gtk.Label(rel) {
					xalign = 0,
					halign = Gtk.Align.START,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END,
					css_classes = { "caption", "dim-label" },
				});
			}
```

#### Replace with

```vala
			if (item is OLLMfiles.File) {
				var when = ((OLLMfiles.File) item).display_modified;
				var size = ((OLLMfiles.File) item).display_size;
				var shown = size;
				if (when != "") {
					shown = when + " - " + size;
				}
				column.append(new Gtk.Label(shown) {
					xalign = 0,
					halign = Gtk.Align.START,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END,
					css_classes = { "caption", "dim-label" },
				});
			}
			if (!(item is OLLMfiles.File)) {
				var rel = item.path;
				if (item.points_to != null && item.points_to.path != "") {
					rel = item.points_to.path;
				}
				if (this.project.path != "" && rel.has_prefix(this.project.path)) {
					rel = rel.substring(this.project.path.length);
				}
				if (rel.has_prefix("/")) {
					rel = rel.substring(1);
				}
				var below = rel.contains("/");
				if (below && rel.length > 36) {
					var cut = rel.last_index_of_char('/');
					if (cut > 0) {
						rel = rel.substring(0, cut);
					}
				}
				if (below && rel.contains("/") && rel.length > 36) {
					var first = rel.index_of_char('/');
					if (first > 0) {
						rel = rel.substring(0, first) + "/…";
					}
				}
				if (below) {
					column.append(new Gtk.Label(rel) {
						xalign = 0,
						halign = Gtk.Align.START,
						hexpand = true,
						ellipsize = Pango.EllipsizeMode.END,
						css_classes = { "caption", "dim-label" },
					});
				}
			}
```

- ✔️ 2026-10-29: applied in `liboccoder/Folder/Browse.vala`.

### `libollmchatgtk/ChatWidget.vala` — overlay over the composer

**Why:** The composer and the model bar are the lower box in this widget. An overlay around the stack and that box is tall enough for the phone sheet to cover both. Nothing walks the widget tree looking for `chat-composer-strip`.

**Where:** The public properties, and the line that appends `main_box`.

#### Add

Next to `view_stack`. The phone coder's pull-over is placed on this overlay.

```vala
		/**
		 * Overlay over the transcript and the composer.
		 *
		 * The child is the stack plus the lower box. The phone
		 * project and file sheet is added here.
		 */
		public Gtk.Overlay cover { get; private set; }
```

#### Remove

```vala
			this.append(main_box);
```

#### Replace with

```vala
			this.cover = new Gtk.Overlay() {
				hexpand = true,
				vexpand = true,
				child = main_box,
			};
			this.append(this.cover);
```

- ✔️ 2026-10-29: applied in `libollmchatgtk/ChatWidget.vala`.

### `liboccoder/CoderView.vala` — phone sheet is not parented here

**Why:** The phone pull-over has to sit on the chat overlay, which is outside this column. This branch only builds the header and the editor. Tablet still overlays its own sheet, beside the chat.

**Where:** The `if (form == Form.PHONE)` branch.

#### Remove

```vala
			if (form == Form.PHONE) {
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
				cover.add_overlay(this.selector);
				this.append(cover);
			}
```

#### Replace with

```vala
			if (form == Form.PHONE) {
				var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
					hexpand = true,
					vexpand = true,
				};
				column.append(header);
				column.append(editor_layer);
				this.append(column);
			}
```

- ✔️ 2026-10-29: applied in `liboccoder/CoderView.vala`.

### `ollmapp/android/AgentManager.vala` — place the phone sheet

**Why:** This is the phone window code that already has the chat widget and, after activate, the coder. The first time Agent Pi's page is created, its pull-over goes on `cover`. Later opens leave it there. `visible` stays false until the project or file button opens it, so the composer shows through until then.

**Where:** `on_editor`.

#### Remove

```vala
			factory.activate.begin(this.shell, (obj, res) => {
				factory.activate.end(res);
				this.schedule_pane_update(true);
			});
```

#### Replace with

```vala
			factory.activate.begin(this.shell, (obj, res) => {
				factory.activate.end(res);
				if (!this.is_phone || factory.name != "agent-pi") {
					this.schedule_pane_update(true);
					return;
				}
				var tabs = (Adw.ViewStack) ((OLLMchat.ChatDesktopInterface) this.shell).tab_view();
				var coder = (OLLMcoder.CoderView) tabs.get_visible_child();
				if (coder.selector.get_parent() != null) {
					this.schedule_pane_update(true);
					return;
				}
				this.shell.chat_widget.cover.add_overlay(coder.selector);
				this.schedule_pane_update(true);
			});
```

- ✔️ 2026-10-29: applied in `ollmapp/android/AgentManager.vala`. The callback returns before the overlay when this is not the phone Agent Pi page, and again when the pull-over already has a parent. Not in the desktop link.

## Next

- ✅ 2026-10-31 — user closed this on the phone with the folder tree.
- 🚫 None. Fixed.
