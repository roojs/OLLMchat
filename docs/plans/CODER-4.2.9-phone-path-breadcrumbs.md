# CODER-4.2.9 Phone file path breadcrumbs

**Status:** ✔️ implemented — not verified on the phone

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan** until it is done and archived.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala code must follow `docs/coding-standards.md`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

---

## Purpose

- 🔷 ✔️ Replace the phone file page's top row (left arrow plus `title-2` project heading) with the tablet's clickable folder-button path bar (`path_box`).
- 🔷 ✔️ Remove the left arrow (`previous`) on the phone file page; the path row starts with the project name as a clickable button followed by `/` and each folder segment as a clickable button.
- 🔷 ✔️ Abbreviate long paths on the phone the same way as on the tablet: keep the project button, and shorten folder buttons after the project to `...` from the second button onward until the row fits, keeping `/` between them and keeping `...` clickable.
- 🔷 ✔️ Hide the subtext row (`selector.current`) underneath when the full buttoned path is displayed above it; only show `selector.current` when at least one folder button is shortened to `...` (hiding its folder name).
- 🔷 ✔️ Style the path buttons with the file-name text size (`body`, `list-chat-title`) in bold (`font-weight: bold`) instead of the larger `title-2` project heading size.
- 💩 ✔️ Move `path_box`, the crumb-fitting state fields, and `render_crumbs()` from `File.Overlay` to the base class `File.Nav` so `File.Pullout` (phone) and `File.Overlay` (tablet) share one implementation without adding a new helper method.
- 💩 ✔️ Apply the bold `body` / `list-chat-title` crumb button styling to the shared `path_box` so tablet and phone path buttons match.
- ℹ️ Related files: `liboccoder/File/Nav.vala`, `liboccoder/File/Overlay.vala`, `liboccoder/File/Pullout.vala`, `liboccoder/SelectorPull.vala`, `resources/style.css`.

---

## Current behaviour

- ℹ️ On the phone file page (`File.Pullout`), `SelectorPull` shows two top rows:
  - Row 1 (`pull_top`): `selector.previous` (left arrow when below project root), `selector.heading` (project name styled with `title-2`), and `selector.close` (`X` button).
  - Row 2 (`selector.current`): full relative path under the project (`caption`, `dim-label`), shown whenever the open folder is below the project root.
- ℹ️ On the tablet file sheet (`File.Overlay`), `place_row` uses `path_box` and `render_crumbs()` to show the project name and each open folder segment as flat `Gtk.Button`s separated by `/` labels, shortening folders after the project to `...` from the second button onward when the row exceeds `path_box.get_width()`.

---

## Proposed behaviour

- 🔷 `File.Nav` owns `path_box`, `fitted_width`, `fitting_crumbs`, `crumbs_shortened`, `place_gen`, `level`, and `render_crumbs()` as `protected` members for non-desktop forms.
- 🔷 Each crumb button and `/` label in `render_crumbs()` uses `body` and `list-chat-title` CSS classes, and `.path-box button.flat, .path-box label` sets `font-weight: bold` in `resources/style.css`.
- 🔷 `render_crumbs()` sets `this.crumbs_shortened = true` when any folder button is replaced with `...`, and `false` otherwise.
- 🔷 On the phone file page (`File.Pullout`):
  - `this.path_box` sits in `pull_top` before `this.selector.close`.
  - `this.selector.previous` and `this.selector.heading` are hidden while the `"file"` page is active (and `this.selector.heading` is restored when switching back to `"project"`).
  - Clicking a crumb button in `this.path_box` navigates to that folder (`refresh_folder(target)`).
  - `this.selector.current.label` holds the relative path `place`, and `this.selector.current.visible` is `this.crumbs_shortened` (only visible when a path segment above it was hidden as `...`).
- 💩 Hardware Back / Escape key handling on `File.Pullout` stays unchanged so the Android system back gesture still steps up one directory.

---

## Implementation

### 1. `liboccoder/File/Nav.vala` — shared `path_box` and `render_crumbs()`

**Why:** Both `File.Overlay` (tablet) and `File.Pullout` (phone) inherit from `File.Nav` and use the same folder-button path bar and `...` fitting logic.

**Where:** Protected fields after `path_text`, `path_box` creation in `Nav()`, and `render_crumbs()` after `Nav()`.

**Depends on:** none.

#### Keep

```vala
		/**
		 * File path shown on the button. A search that is too wide
		 * replaces the label until the text is narrowed or cleared.
		 */
		protected string path_text = "Select file";
```

#### Add — after `path_text`. Shared crumb state and current folder for phone and tablet.

```vala

		/**
		 * Folder-name buttons for the open path on phone and tablet.
		 */
		protected Gtk.Box path_box;

		/**
		 * Width of the path row last used to shorten crumb labels.
		 */
		protected int fitted_width = -1;

		/**
		 * True while crumb labels change, so width notify does not
		 * fit the same row again.
		 */
		protected bool fitting_crumbs = false;

		/**
		 * True when {@link render_crumbs} shortened at least one
		 * folder button to ''...'' to fit the path row.
		 */
		protected bool crumbs_shortened = false;

		/**
		 * Counts phone and tablet folder changes. Width notify on
		 * the path row skips fitting while this is still zero.
		 */
		protected int place_gen = 0;

		/**
		 * Folder shown in the phone or tablet folder list.
		 */
		protected OLLMfiles.Folder level;
```

#### Keep

```vala
			this.file_list = new List(this.form == Form.TABLET);
			this.search_home = this.project;
```

#### Add — in `Nav()`, after `this.search_home = this.project;`. Initialize `level` and build `path_box` for phone and tablet.

```vala
			this.level = this.project;
			if (this.form != Form.DESKTOP) {
				this.path_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
					hexpand = true,
					valign = Gtk.Align.CENTER,
					css_classes = { "horizontal", "path-box" },
				};
			}
```

#### Keep

```vala
			this.notify["project"].connect(() => {
				if (!this.project.is_project) {
					return;
				}
				this.path_text = "Select file";
				this.label.label = this.path_text;
				this.button.tooltip_text = "";
				this.visible = true;
			});
		}
```

#### Add — after `Nav()`, before `load()`. Shared crumb rendering moved from `File.Overlay`, tracking `crumbs_shortened` and styling buttons with bold file-name text classes.

```vala

		/**
		 * Show the phone or tablet location as folder-name buttons
		 * with a slash between them. Each button stores its folder.
		 * A click opens that folder. The walk follows parent and
		 * stops at the open project. Buttons that already match
		 * stay. A step down adds one. A step up removes one.
		 * Once the row has a width, folders after the project show
		 * as ''...'' from the second folder until the buttons and
		 * slashes fit. The project name stays. A tap on ''...''
		 * still opens that folder.
		 */
		protected void render_crumbs()
		{
			if (this.fitting_crumbs) {
				return;
			}
			this.fitting_crumbs = true;
			this.crumbs_shortened = false;
			var above = new Gee.ArrayList<OLLMfiles.Folder>();
			var walk = this.level;
			while (true) {
				above.add(walk);
				if (walk.parent == null || walk.id == this.project.id) {
					break;
				}
				walk = walk.parent;
			}
			var want = above.size - 1;
			var child = this.path_box.get_first_child();
			while (child != null && want >= 0) {
				if (!(child is Gtk.Button)) {
					child = child.get_next_sibling();
					continue;
				}
				var stored = ((Gtk.Button) child).get_data<OLLMfiles.Folder>("folder");
				if (stored != above.get(want)) {
					break;
				}
				want--;
				child = child.get_next_sibling();
			}
			var drop = child;
			if (drop != null) {
				var prev = drop.get_prev_sibling();
				if (prev != null && !(prev is Gtk.Button)) {
					drop = prev;
				}
			}
			while (drop != null) {
				var next = drop.get_next_sibling();
				this.path_box.remove(drop);
				drop = next;
			}
			while (want >= 0) {
				if (this.path_box.get_first_child() != null) {
					this.path_box.append(new Gtk.Label("/") {
						valign = Gtk.Align.CENTER,
						css_classes = { "body", "list-chat-title" },
					});
				}
				var target = above.get(want);
				var crumb = new Gtk.Button.with_label(target.path_basename) {
					can_focus = false,
					valign = Gtk.Align.CENTER,
					css_classes = { "flat", "body", "list-chat-title" },
				};
				crumb.set_data<OLLMfiles.Folder>("folder", target);
				this.path_box.append(crumb);
				want--;
			}
			var avail = this.path_box.get_width();
			if (avail <= 1) {
				this.fitting_crumbs = false;
				return;
			}
			this.fitted_width = avail;
			child = this.path_box.get_first_child();
			while (child != null) {
				if (!(child is Gtk.Button)) {
					child = child.get_next_sibling();
					continue;
				}
				var named = (Gtk.Button) child;
				var folder = named.get_data<OLLMfiles.Folder>("folder");
				if (named.label != folder.path_basename) {
					named.label = folder.path_basename;
				}
				child = child.get_next_sibling();
			}
			var total = 0;
			var n = 0;
			var min_w = 0;
			var nat_w = 0;
			child = this.path_box.get_first_child();
			while (child != null) {
				child.measure(Gtk.Orientation.HORIZONTAL, -1,
					out min_w, out nat_w, null, null);
				total += nat_w;
				n++;
				child = child.get_next_sibling();
			}
			if (n > 1) {
				total += (n - 1) * this.path_box.spacing;
			}
			var index = 0;
			child = this.path_box.get_first_child();
			while (child != null && total > avail) {
				if (!(child is Gtk.Button)) {
					child = child.get_next_sibling();
					continue;
				}
				index++;
				if (index == 1) {
					child = child.get_next_sibling();
					continue;
				}
				var narrow = (Gtk.Button) child;
				narrow.measure(Gtk.Orientation.HORIZONTAL, -1,
					out min_w, out nat_w, null, null);
				var wide = nat_w;
				narrow.label = "...";
				this.crumbs_shortened = true;
				narrow.measure(Gtk.Orientation.HORIZONTAL, -1,
					out min_w, out nat_w, null, null);
				total -= wide - nat_w;
				child = child.get_next_sibling();
			}
			this.fitting_crumbs = false;
		}
```

### 2. `liboccoder/File/Overlay.vala` — use inherited `path_box` and `render_crumbs()`

**Why:** `path_box`, `fitted_width`, `fitting_crumbs`, `place_gen`, `level`, and `render_crumbs()` now live on `File.Nav`.

**Where:** Field declarations, `Overlay()` tablet setup, and `render_crumbs()` removal.

**Depends on:** §1.

#### Keep

```vala
		private uint search_wait = 0;
		private Folder.Browse browse;
		private Gtk.Button up;
```

#### Remove

```vala
		private Gtk.Box path_box;

		/**
		 * Width of the path row last used to shorten crumb labels.
		 */
		private int fitted_width = -1;

		/**
		 * True while crumb labels change, so width notify does not
		 * fit the same row again.
		 */
		private bool fitting_crumbs = false;

		/**
		 * Counts tablet folder changes. A private property would
		 * not emit notify, so each change calls
		 * {@link render_crumbs} itself. Width notify on the path
		 * row skips fitting while this is still zero.
		 */
		private int place_gen = 0;

		/**
		 * Folder shown in the tablet left pane.
		 */
		private OLLMfiles.Folder level;
```

#### Keep

```vala
			var place_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				margin_start = 6,
				margin_end = 6,
				margin_top = 6,
			};
			if (this.form == Form.TABLET) {
```

#### Remove

```vala
				this.path_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
					hexpand = true,
					valign = Gtk.Align.CENTER,
				};
```

#### Keep

```vala
				var crumb_click = new Gtk.GestureClick() {
					propagation_phase = Gtk.PropagationPhase.CAPTURE,
				};
```

#### Keep

```vala
			this.chosen.connect(() => {
				GLib.Idle.add(() => {
					this.get_root().set_focus(null);
					this.list.visible = false;
					return false;
				});
			});
		}
```

#### Remove

```vala

		/**
		 * Show the tablet location as folder-name buttons with a
		 * slash between them. Each button stores its folder. A
		 * click opens that folder. The walk follows parent and
		 * stops at the open project. Buttons that already match
		 * stay. A step down adds one. A step up removes one.
		 * Once the row has a width, folders after the project show
		 * as ''...'' from the second folder until the buttons and
		 * slashes fit. The project name stays. A tap on ''...''
		 * still opens that folder.
		 */
		private void render_crumbs()
		{
			if (this.fitting_crumbs) {
				return;
			}
			this.fitting_crumbs = true;
			var above = new Gee.ArrayList<OLLMfiles.Folder>();
			var walk = this.level;
			while (true) {
				above.add(walk);
				if (walk.parent == null || walk.id == this.project.id) {
					break;
				}
				walk = walk.parent;
			}
			var want = above.size - 1;
			var child = this.path_box.get_first_child();
			while (child != null && want >= 0) {
				if (!(child is Gtk.Button)) {
					child = child.get_next_sibling();
					continue;
				}
				var stored = ((Gtk.Button) child).get_data<OLLMfiles.Folder>("folder");
				if (stored != above.get(want)) {
					break;
				}
				want--;
				child = child.get_next_sibling();
			}
			var drop = child;
			if (drop != null) {
				var prev = drop.get_prev_sibling();
				if (prev != null && !(prev is Gtk.Button)) {
					drop = prev;
				}
			}
			while (drop != null) {
				var next = drop.get_next_sibling();
				this.path_box.remove(drop);
				drop = next;
			}
			while (want >= 0) {
				if (this.path_box.get_first_child() != null) {
					this.path_box.append(new Gtk.Label("/") {
						valign = Gtk.Align.CENTER,
					});
				}
				var target = above.get(want);
				var crumb = new Gtk.Button.with_label(target.path_basename) {
					can_focus = false,
					valign = Gtk.Align.CENTER,
					css_classes = { "flat" },
				};
				crumb.set_data<OLLMfiles.Folder>("folder", target);
				this.path_box.append(crumb);
				want--;
			}
			var avail = this.path_box.get_width();
			if (avail <= 1) {
				this.fitting_crumbs = false;
				return;
			}
			this.fitted_width = avail;
			child = this.path_box.get_first_child();
			while (child != null) {
				if (!(child is Gtk.Button)) {
					child = child.get_next_sibling();
					continue;
				}
				var named = (Gtk.Button) child;
				var folder = named.get_data<OLLMfiles.Folder>("folder");
				if (named.label != folder.path_basename) {
					named.label = folder.path_basename;
				}
				child = child.get_next_sibling();
			}
			var total = 0;
			var n = 0;
			var min_w = 0;
			var nat_w = 0;
			child = this.path_box.get_first_child();
			while (child != null) {
				child.measure(Gtk.Orientation.HORIZONTAL, -1,
					out min_w, out nat_w, null, null);
				total += nat_w;
				n++;
				child = child.get_next_sibling();
			}
			if (n > 1) {
				total += (n - 1) * this.path_box.spacing;
			}
			var index = 0;
			child = this.path_box.get_first_child();
			while (child != null && total > avail) {
				if (!(child is Gtk.Button)) {
					child = child.get_next_sibling();
					continue;
				}
				index++;
				if (index == 1) {
					child = child.get_next_sibling();
					continue;
				}
				var narrow = (Gtk.Button) child;
				narrow.measure(Gtk.Orientation.HORIZONTAL, -1,
					out min_w, out nat_w, null, null);
				var wide = nat_w;
				narrow.label = "...";
				narrow.measure(Gtk.Orientation.HORIZONTAL, -1,
					out min_w, out nat_w, null, null);
				total -= wide - nat_w;
				child = child.get_next_sibling();
			}
			this.fitting_crumbs = false;
		}
```

### 3. `liboccoder/File/Pullout.vala` — phone path buttons and conditional subtext

**Why:** Phone replaces the left arrow and `title-2` project heading with `path_box` buttons, and only shows `selector.current` when `render_crumbs()` shortened a folder button to `...`.

**Where:** Class docblock, `level` field removal, `Pullout()` constructor, `show_files()`, and `refresh_folder()`.

**Depends on:** §1.

#### Remove

```vala
	 * One folder at a time: its child folders, then its files. The
	 * left arrow and the back key go up one directory. An X closes
	 * the page. Tree and Recent sit above the title. Search stays
	 * at the bottom of the pull-over. Tablet files are
	 * {@link Overlay}.
```

#### Replace with — document the folder-button path bar and conditional subtext line.

```vala
	 * One folder at a time: its child folders, then its files. The
	 * top row shows the project and open folders as buttons with a
	 * slash between them, shortened to ''...'' when needed, and an X
	 * that closes the page. The full relative path under that row is
	 * shown only when a folder button is shortened to ''...''. The
	 * back key goes up one directory. Tree and Recent sit above the
	 * path row. Search stays at the bottom of the pull-over. Tablet
	 * files are {@link Overlay}.
```

#### Keep

```vala
		private Gtk.Stack filters;
		private Gtk.Box file_bar;
```

#### Remove

```vala
		private OLLMfiles.Folder level;
```

#### Keep

```vala
			var page = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true,
			};
			page.append(body);
			this.selector.pages.add_named(page, "file");
```

#### Remove

```vala
			this.selector.pages.notify["visible-child-name"].connect(() => {
				this.file_bar.visible = this.selector.pages.visible_child_name == "file";
			});
			this.selector.back.connect(() => {
				if (this.selector.kind != "file") {
					return false;
				}
				var up = this.level.parent;
				if (this.level.is_project || up == null) {
					return true;
				}
				this.refresh_folder(up);
				return true;
			});
```

#### Replace with — insert `path_box` into `pull_top` before `close`, wire crumb clicks and width fitting, and toggle `file_bar`, `path_box`, and `heading` with the active page.

```vala
			this.path_box.visible = false;
			this.path_box.insert_before(
				this.selector.close.get_parent(), this.selector.close);
			var crumb_click = new Gtk.GestureClick() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE,
			};
			crumb_click.pressed.connect((n, x, y) => {
				if (n != 1) {
					return;
				}
				var widget = this.path_box.pick(x, y, Gtk.PickFlags.DEFAULT);
				while (widget != null &&
					widget != this.path_box &&
					!(widget is Gtk.Button)) {
					widget = widget.get_parent();
				}
				if (!(widget is Gtk.Button)) {
					return;
				}
				var target = ((Gtk.Button) widget).get_data<OLLMfiles.Folder>("folder");
				if (target == null) {
					return;
				}
				GLib.Idle.add(() => {
					this.refresh_folder(target);
					if (this.search_open) {
						this.browse.query = this.selector.search.text.strip();
					}
					return false;
				});
			});
			this.path_box.add_controller(crumb_click);
			this.path_box.notify["width"].connect(() => {
				if (this.fitting_crumbs) {
					return;
				}
				if (this.place_gen == 0) {
					return;
				}
				if (this.path_box.get_width() == this.fitted_width) {
					return;
				}
				this.render_crumbs();
				this.selector.current.visible = this.crumbs_shortened;
			});
			this.selector.pages.notify["visible-child-name"].connect(() => {
				var on_file = this.selector.pages.visible_child_name == "file";
				this.file_bar.visible = on_file;
				this.path_box.visible = on_file;
				this.selector.heading.visible = !on_file;
			});
```

#### Keep

```vala
		private void show_files()
		{
			this.selector.kind = "file";
			this.selector.pages.visible_child_name = "file";
			this.selector.search.placeholder_text = "Search files";
			this.selector.visible = true;
			this.selector.close.visible = true;
			this.file_bar.visible = true;
```

#### Add — in `show_files()`, after `this.file_bar.visible = true;`. Hide the left arrow and `title-2` heading and show `path_box`.

```vala
			this.selector.previous.visible = false;
			this.selector.heading.visible = false;
			this.path_box.visible = true;
```

#### Remove

```vala
		/**
		 * Refresh the phone page to one folder. The title and the
		 * place line follow that folder. {@link Folder.Browse} shows
		 * the level. The arrow is hidden at the project root.
		 *
		 * @param folder Folder now shown
		 */
		private void refresh_folder(OLLMfiles.Folder folder)
		{
			this.level = folder;
			this.pullout_epoch++;
			var place = folder.path;
			if (this.project.path != "" && place.has_prefix(this.project.path)) {
				place = place.substring(this.project.path.length);
			}
			if (place.has_prefix("/")) {
				place = place.substring(1);
			}
			this.selector.heading.label = this.project.path_basename;
			this.selector.current.label = place;
			this.selector.current.visible = place != "";
			this.selector.previous.visible = place != "";
			this.browse.visible = true;
			if (this.recent_scroll.child != this.list) {
				this.list.unparent();
				this.recent_scroll.child = this.list;
			}
			this.browse.refresh_folder(folder);
		}
```

#### Replace with — render the crumb buttons for `folder` and only show `selector.current` when `render_crumbs()` shortened a folder button to `...`.

```vala
		/**
		 * Refresh the phone page to one folder. The path buttons follow
		 * that folder, and the subtext line is shown only when a button
		 * is shortened to ''...''. {@link Folder.Browse} shows the level.
		 *
		 * @param folder Folder now shown
		 */
		private void refresh_folder(OLLMfiles.Folder folder)
		{
			this.level = folder;
			this.pullout_epoch++;
			var place = folder.path;
			if (this.project.path != "" && place.has_prefix(this.project.path)) {
				place = place.substring(this.project.path.length);
			}
			if (place.has_prefix("/")) {
				place = place.substring(1);
			}
			this.selector.current.label = place;
			this.place_gen++;
			this.render_crumbs();
			this.selector.current.visible = this.crumbs_shortened;
			this.browse.visible = true;
			if (this.recent_scroll.child != this.list) {
				this.list.unparent();
				this.recent_scroll.child = this.list;
			}
			this.browse.refresh_folder(folder);
		}
```

### 4. `liboccoder/SelectorPull.vala` — update docblocks for the phone file page

**Why:** The class and property docblocks still say the phone file page shows `previous` below the project root and hides `current` only at the project root.

**Where:** Class overview and `current` / `previous` property docblocks.

**Depends on:** §3.

#### Remove

```vala
	 * Back arrow, title, the current selection, a page stack, and
	 * search at the bottom. The phone file page adds a close button
	 * and hides the arrow at the project root. Opening it does not
	 * focus search, so the keyboard stays down. Which edge it uses
	 * is still open.
```

#### Replace with — phone file page replaces the arrow and title with path buttons and a close button.

```vala
	 * Back arrow, title, the current selection, a page stack, and
	 * search at the bottom. The phone file page replaces the arrow
	 * and title with path buttons and a close button. Opening it
	 * does not focus search, so the keyboard stays down. Which edge
	 * it uses is still open.
```

#### Remove

```vala
		/**
		 * Line under the top bar. The project page shows the current
		 * selection. The phone file page shows the path relative to
		 * the project, and hides this line at the project root.
		 */
		public Gtk.Label current { get; private set; }

		/**
		 * Left arrow. Hidden on the phone file page at the project
		 * root. Shown again below that root, and on the project page.
		 */
		public Gtk.Button previous { get; private set; }
```

#### Replace with — `current` is only shown on the phone file page when a path button is shortened to `...`, and `previous` is for the project page only.

```vala
		/**
		 * Line under the top bar. The project page shows the current
		 * selection. The phone file page shows the path relative to
		 * the project only when a path button is shortened to ''...''.
		 */
		public Gtk.Label current { get; private set; }

		/**
		 * Left arrow on the project page. Hidden on the phone file
		 * page.
		 */
		public Gtk.Button previous { get; private set; }
```

### 5. `resources/style.css` — flat button padding and bold file-name weight on `.path-box`

**Why:** `.selector-pull button.flat` needs the same compact flat styling as `.file-sheet button.flat`, and the path buttons and slashes use bold weight at the file-name font size (`body`, `list-chat-title`).

**Where:** `.file-sheet button.flat` rule near the bottom of `resources/style.css`.

**Depends on:** §1.

#### Remove

```css
.file-sheet button.flat {
	background: none;
	background-image: none;
	border: none;
	box-shadow: none;
	min-height: 0;
	padding: 4px;
}
```

#### Replace with — share compact flat button styling with `.selector-pull` and bold the `.path-box` buttons and `/` separators.

```css
.selector-pull button.flat,
.file-sheet button.flat {
	background: none;
	background-image: none;
	border: none;
	box-shadow: none;
	min-height: 0;
	padding: 4px;
}

.path-box button.flat,
.path-box label {
	font-weight: bold;
}
```

---

## LLM notes

- 🚫 Do not add a new helper method; move the existing `render_crumbs()` from `File.Overlay` to `File.Nav`.
- 🚫 Do not remove `SelectorPull.previous` or `SelectorPull.heading`; the project page (`ProjectSelector`) still uses both.
- 🚫 Do not remove hardware Back / Escape handling from `File.Pullout`.
