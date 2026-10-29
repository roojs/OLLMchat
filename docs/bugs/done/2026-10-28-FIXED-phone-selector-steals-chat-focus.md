# Phone selector and folder browse steal focus to the chat entry

**Status:** ✅ User verified on the phone, 2026-10-29. Focus stays off the chat entry.

## Problem

- 🔷 Phone SM-S9380, wireless debugging, `org.roojs.ollmchat.androidpoc` pid 13993, launch 2026-10-28 12:43:51.
- 🔷 Expected: selecting a project in Agent Pi opens the file pull-over (`SelectorPull`) without focusing the chat entry or raising the on-screen keyboard. Drilling down into folders inside the file pull-over also keeps focus off the chat entry and keeps the keyboard down.
- 🔷 Actual: selecting the `OLLMchat` project opens the file pull-over, and at the same time focus moves to the chat `Gtk.TextView` (`ChatInput`) and raises the Android keyboard (`InsetsController: show(ime())`). Tapping a folder that has no child folders (`Folder.Browse`) also moves focus to the chat entry and raises the keyboard.

## Evidence

- ℹ️ `adb -s adb-R5CY134DA0W-LrNhQc._adb-tls-connect._tcp logcat -d --pid=13993`
- ✔️ 12:44:11.150: touch release on the `OLLMchat` project row in `ProjectSelector.selector_list_box`.
- ✔️ 12:44:11.158: `ProjectManager.vala:232: opening project path=/home/alan/gitlive/OLLMchat`, `id=3 method=ProjectManager.rpc_activate_project`.
- ✔️ 12:44:11.167 (9 ms later, on the next frame clock after-paint): `InsetsController: show(ime())`, `CLIP: IME onCreateInputConnection kind=GtkTextView inputType=0x1`. The surface shrinks from `384x750` to `384x466` as the keyboard covers the bottom of the screen.
- ✔️ 12:45:37.852: touch release on a folder row in `Folder.Browse.folders` that has child folders. Focus moves to that `Gtk.ListBoxRow`, so the `Gtk.TextView` loses focus (`CLIP: bubble hide reason=focus-out widget=TextView`, `InsetsController: hide(ime())`).
- ✔️ 12:46:22.472 and 12:46:24.878: taps on folders that have child folders keep focus on the new `Gtk.ListBoxRow` and the keyboard stays hidden.
- ✔️ 12:46:26.600: touch release on a folder that has no child folders (`id=9 method=Folder.fetch_dir`). At 12:46:26.621, `InsetsController: show(ime())` fires again and the surface shrinks back to `384x466`.

## Root cause

- ✔️ In GTK 4 (`gtkwindow.c`), hiding or unparenting the currently focused widget calls `_gtk_window_unset_focus_and_default`, which sets `priv->move_focus = TRUE` and schedules `maybe_unset_focus_and_default` for `GDK_FRAME_CLOCK_PHASE_AFTER_PAINT`.
- ✔️ On `after_paint`, `maybe_unset_focus_and_default` walks up the ancestors of `move_focus_widget` calling `gtk_widget_grab_focus(parent)`. `GtkBox` and `GtkOverlay` do not override `grab_focus`, so their default `gtk_widget_grab_focus_self` returns `FALSE` (`focusable` is `FALSE`). The walk reaches the `GtkWindow` with `parent == NULL` and falls back to `gtk_widget_child_focus(GTK_WIDGET(window), GTK_DIR_TAB_FORWARD)`.
- ✔️ Because `old_focus_child` on the window was cleared when focus left the hidden/unparented row, `gtk_window_focus` starts tab navigation from the top of the window (`focus_sort_up_down`), skips the header buttons (`can_focus = false`), skips `SelectorPull.search` (`can_focus = false`), and lands on the first focusable text widget in the window below the pane: `ChatInput.text_view`. That focuses the chat `Gtk.TextView` and raises the Android IME.
- ✔️ This happens in three places:
  - `ProjectSelector.choose`: tapping a project row in `selector_list_box` focuses that `Gtk.ListBoxRow`. `choose` sets `this.selector.visible = false`, hiding `selector`, then `chosen` immediately sets `this.selector.visible = true` for the file pull-over. The hide call already armed `priv->move_focus = TRUE` on the window, and nothing focused a visible widget before `after_paint`.
  - `Folder.Browse.refresh_folder`: tapping a folder row in `this.folders` focuses that `Gtk.ListBoxRow`. `refresh_folder` sets `this.folders.visible = false` and `this.folders.bind_model(null, null)`, which unparents the focused row and arms `priv->move_focus = TRUE`. When the target folder has no child folders (`shown.get_n_items() == 0`), `this.folders` stays hidden and no row takes focus, so `after_paint` tabs into `ChatInput.text_view`.
  - `File.Nav.choose`: after a file is activated, `choose` ends with `next.child_focus(Gtk.DirectionType.TAB_FORWARD)` on the sibling after the coder header. On Android, `SourceView.source_view` has `can_focus = false`, and when `SelectorPull` or `File.Overlay` closes on idle, any focus left inside the closing sheet also triggers `move_focus` to the chat entry.

## Proposed fix

- 🔷 Keep list rows in `ProjectSelector.selector_list_box`, `Folder.Browse`, and `File.Pullout.list` from taking focus on tap (`can_focus = false` on those `Gtk.ListBox` widgets, matching `ProjectSelector.list_box` and `File.Overlay.recent_list`). Tapping a project, folder, or file row never places window focus on a transient row that is about to be hidden or unbound.
- 🔷 When `SelectorPull` or `File.Overlay.list` closes while focus is inside it (e.g. after tapping `SelectorPull.search`), clear window focus with `((Gtk.Root) this.get_root()).set_focus(null)` before hiding so `_gtk_window_unset_focus_and_default` sees `priv->focus_widget == NULL` and does not arm `move_focus`.
- 🔷 In `File.Nav.choose`, only advance focus to the sibling when `this.form == Form.DESKTOP`.

### `liboccoder/ProjectSelector.vala`

#### Remove

```vala
			this.selector_list_box = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.NONE,
				activate_on_single_click = true,
				hexpand = true,
				vexpand = true,
			};
```

#### Replace with

```vala
			this.selector_list_box = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.NONE,
				activate_on_single_click = true,
				can_focus = false,
				hexpand = true,
				vexpand = true,
			};
```

#### Remove

```vala
			this.list.visible = false;
			this.selector.visible = false;
			this.chosen(folder);
```

#### Replace with

```vala
			this.get_root().set_focus(null);
			this.list.visible = false;
			this.selector.visible = false;
			this.chosen(folder);
```

### `liboccoder/Folder/Browse.vala`

#### Remove

```vala
			this.folders = new Gtk.ListBox() {
				hexpand = true,
				activate_on_single_click = true,
				selection_mode = Gtk.SelectionMode.NONE,
			};
```

#### Replace with

```vala
			this.folders = new Gtk.ListBox() {
				hexpand = true,
				activate_on_single_click = true,
				can_focus = false,
				selection_mode = Gtk.SelectionMode.NONE,
			};
```

#### Remove

```vala
			var file_box = new Gtk.ListBox() {
				hexpand = true,
				activate_on_single_click = true,
				selection_mode = Gtk.SelectionMode.NONE,
			};
```

#### Replace with

```vala
			var file_box = new Gtk.ListBox() {
				hexpand = true,
				activate_on_single_click = true,
				can_focus = false,
				selection_mode = Gtk.SelectionMode.NONE,
			};
```

### `liboccoder/File/Pullout.vala`

#### Remove

```vala
			this.list = new Gtk.ListBox() {
				hexpand = true,
				vexpand = true,
				activate_on_single_click = true,
			};
```

#### Replace with

```vala
			this.list = new Gtk.ListBox() {
				hexpand = true,
				vexpand = true,
				activate_on_single_click = true,
				can_focus = false,
			};
```

#### Remove

```vala
			this.chosen.connect((file) => {
				this.chosen_path = file.path;
				this.selector.visible = false;
			});
```

#### Replace with

```vala
			this.chosen.connect((file) => {
				this.chosen_path = file.path;
				this.get_root().set_focus(null);
				this.selector.visible = false;
			});
```

### `liboccoder/SelectorPull.vala`

#### Remove

```vala
			this.previous.clicked.connect(() => {
				if (this.back()) {
					return;
				}
				this.visible = false;
			});
			this.close.clicked.connect(() => {
				this.visible = false;
			});
```

#### Replace with

```vala
			this.previous.clicked.connect(() => {
				if (this.back()) {
					return;
				}
				this.get_root().set_focus(null);
				this.visible = false;
			});
			this.close.clicked.connect(() => {
				this.get_root().set_focus(null);
				this.visible = false;
			});
```

### `liboccoder/File/Overlay.vala`

#### Remove

```vala
			close_files.clicked.connect(() => {
				GLib.Idle.add(() => {
					this.list.visible = false;
					return false;
				});
			});
```

#### Replace with

```vala
			close_files.clicked.connect(() => {
				GLib.Idle.add(() => {
					this.get_root().set_focus(null);
					this.list.visible = false;
					return false;
				});
			});
```

#### Remove

```vala
			this.chosen.connect(() => {
				GLib.Idle.add(() => {
					this.list.visible = false;
					return false;
				});
			});
```

#### Replace with

```vala
			this.chosen.connect(() => {
				GLib.Idle.add(() => {
					this.get_root().set_focus(null);
					this.list.visible = false;
					return false;
				});
			});
```

### `liboccoder/File/Nav.vala`

#### Remove

```vala
			this.manager.activate_file(file);
			this.chosen(file);
			var row = this.get_parent();
			if (row == null) {
				return;
			}
			var next = row.get_next_sibling();
			if (next == null) {
				return;
			}
			next.child_focus(Gtk.DirectionType.TAB_FORWARD);
```

#### Replace with

```vala
			this.manager.activate_file(file);
			this.chosen(file);
			if (this.form != Form.DESKTOP) {
				return;
			}
			var row = this.get_parent();
			if (row == null) {
				return;
			}
			var next = row.get_next_sibling();
			if (next == null) {
				return;
			}
			next.child_focus(Gtk.DirectionType.TAB_FORWARD);
```

## Attempts / changelog

- ℹ️ 2026-10-28: captured phone logcat for pid 13993 across project selection and folder navigation.
- ✔️ 2026-10-28: traced `InsetsController: show(ime())` after project selection and leaf-folder selection to GTK's `maybe_unset_focus_and_default` (`after_paint`) tabbing into `ChatInput.text_view` when a focused `Gtk.ListBoxRow` is hidden or unbound.
- ✔️ 2026-10-28: applied proposed fix in `ProjectSelector.vala`, `Folder/Browse.vala`, `File/Pullout.vala`, `SelectorPull.vala`, `File/Overlay.vala`, and `File/Nav.vala`.

## Next

- ✅ 2026-10-29: user confirmed selecting a project and browsing folders no longer raises the keyboard.
