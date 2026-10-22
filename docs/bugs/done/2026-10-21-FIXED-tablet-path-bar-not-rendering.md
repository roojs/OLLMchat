# Tablet path bar does not render

**Status:** ✅ User confirmed the location row is fixed. Closed 2026-10-21.

## Problem

- 🔷 On the tablet file sheet, the folder path bar does not render at all.
- 🔷 Expected: the location row shows each folder name as a plain button, with a slash between names. A tap on a name opens that folder.
- 🔷 Actual: that bar is not visible.
- ℹ️ Pixel Tablet emulator `emulator-5554`, source-diff APK built 2026-10-21 21:13 and installed from `.pixiewood/oc-test-source-diff-arm64-v8a-debug.apk`.

## Evidence

- ℹ️ Tablet only. `FileOverlay` builds `path_box` when `form == TABLET` and puts it in a `Gtk.ScrolledWindow` on `place_row`. `examples/oc-test-source-diff/FileOverlay.vala`.
- ℹ️ `render_crumbs` runs from `notify["place-gen"]`. Opening the sheet sets `level` to the project and increments `place_gen`, so the first paint should append one button.
- ℹ️ Each crumb is a `Gtk.Button` with css class `flat`. `.file-sheet button.flat` sets `min-height: 0`, no background, and no border. `resources/style.css`.
- ℹ️ `path_box` and the scrolled window both use `valign = CENTER`. The scrolled window hides the vertical scrollbar and sets `propagate_natural_height`.
- 💩 A scrolled window whose natural height stays 0 would clip every crumb even after `render_crumbs` appends them. Not measured on device.
- 🚫 Do not give the row a hardcoded height to hide a zero allocation.
- 🔷 The path bar was never supposed to sit in a scrolled window.

## Root cause

- 🚫 💩 `path_box` inside `Gtk.ScrolledWindow` clipped the crumbs. The scrolled window is gone. On device the location row is still an empty band with only the close mark. 2026-10-21 22:56 screenshot, `emulator-5554`.
- ✔️ `place_gen` was a private property. Vala does not emit `notify` for a private property, and the setter only stores the int. `notify["place-gen"]` was connected and never ran, so `render_crumbs()` never appended a folder button. The close mark is a separate child of `place_row`, which is why that mark showed and the names did not.

## Proposed fix

- 🔷 Remove `path_scroll`. Append `path_box` on `place_row`. Give `path_box` `hexpand` so the close button stays at the trailing edge.

### `examples/oc-test-source-diff/FileOverlay.vala` — tablet `place_row`

**Why:** The location row is `path_box`. A scrolled window around it was never part of the sheet.
**Where:** Tablet branch that builds `path_box`, in the `FileOverlay` constructor, before `place_row.append(this.up)`.
**Depends on:** none.

#### Remove

```vala
				this.path_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
					valign = Gtk.Align.CENTER,
				};
```

#### Replace with

`path_box` takes the spare width on the row.

```vala
				this.path_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
					hexpand = true,
					valign = Gtk.Align.CENTER,
				};
```

#### Remove

```vala
				var path_scroll = new Gtk.ScrolledWindow() {
					child = this.path_box,
					hexpand = true,
					valign = Gtk.Align.CENTER,
					hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
					vscrollbar_policy = Gtk.PolicyType.NEVER,
					propagate_natural_height = true,
				};
				place_row.hexpand = true;
				place_row.valign = Gtk.Align.CENTER;
				place_row.append(this.up);
				place_row.append(path_scroll);
```

#### Replace with

Append `path_box` itself.

```vala
				place_row.hexpand = true;
				place_row.valign = Gtk.Align.CENTER;
				place_row.append(this.up);
				place_row.append(this.path_box);
```

## Crumb width

- 🔷 After the buttons are in the row, measure them against the row width.
- 🔷 The project name stays. From the second folder, a name that does not fit becomes `...`.
- 🔷 The slash between names stays, so a long path reads `Project / ... / ... /` and then the names that fit.
- 🔷 A tap on `...` still opens that folder.

### `examples/oc-test-source-diff/FileOverlay.vala` — `render_crumbs()`

**Why:** A long location must stay on the row. The project button stays. Later folders shorten from the second one until the measured row fits.
**Where:** End of `render_crumbs()`, after the crumb buttons are appended. Width notify on `path_box` calls `render_crumbs()` again when the allocation changes.
**Depends on:** the path row is `path_box` on `place_row`.

#### Add

After the loop that appends crumb buttons, and before the closing brace of `render_crumbs()`.

```vala
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
```

## Attempts / changelog

- ✔️ Removed `path_scroll` and appended `this.path_box` on `place_row`. `examples/oc-test-source-diff/FileOverlay.vala`.
- ✔️ `render_crumbs()` shortens folders after the project to `...` until the measured buttons and slashes fit the row.
- ✔️ 2026-10-21 21:53 built `.pixiewood/oc-test-source-diff-arm64-v8a-debug.apk`, installed it on `emulator-5554`, and started `org.roojs.ollmchat.sourcediff`.
- 🚫 That build still showed an empty location row. The close mark is at the trailing edge. No folder name is drawn. Screenshot 2026-10-21 22:56.
- ✔️ `place_gen` is a field. Each folder change calls `render_crumbs()` directly. `examples/oc-test-source-diff/FileOverlay.vala`.

## Conclusion

- ✅ 🔷 The location row shows the folder names. Opening Pman shows `web.MediaOutreach / Pman` with the up mark. User closed this bug on 2026-10-21.
- ℹ️ A path longer than the row shortens later names to `...` in `render_crumbs()`. That overflow case was not opened on a deeper folder before this was closed.
