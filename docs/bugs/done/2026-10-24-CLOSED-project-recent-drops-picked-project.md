# Picking a project from Recent removes it

**Status:** 🚫 CLOSED. The tablet list no longer selects the picked row. Not checked on the device.

## Problem

- 🔷 Open `web.MediaOutreach`. It is a project.
- 🔷 Open the project list again, on Recent, and pick that same project.
- 🔷 After it is picked, that row is still in Recent. The title is white on a light grey background, so the name cannot be read.

## Evidence

- 🔷 24 Oct, tablet, source-diff app. The active project is highlighted that way.
- ℹ️ The tablet project list selects the activated row and keeps that selection. `examples/oc-test-source-diff/ProjectSelector.vala` (`selector_list_box`, `Gtk.SelectionMode.SINGLE`). The desktop list does not select rows (`list_box`, `Gtk.SelectionMode.NONE`).
- ℹ️ `.selector-pull row` paints every pull-over row with `@theme_bg_color`. `resources/style.css`.
- ℹ️ The theme still sets the selected row's text to `@theme_selected_fg_color`, which is white. The pull-over rule does not set a text color, so the white title sits on the light background.
- 🚫 The folder is not removed. Recent's `last_viewed` filter is not what hides the name.

## Root cause

- ✔️ Picking the project selects its row. The pull-over forces a light row background and leaves the selected title white, so the active project looks gone.

## Proposed fix

- 💩 Stop selecting a row on the tablet project list. The desktop list already uses `Gtk.SelectionMode.NONE`. Nothing reads the pull list's selected row. `row_activated` still fires. The theme then has no selected title to paint white.
- 🚫 Do not restyle the selected text. The open list does not highlight a row.

### `examples/oc-test-source-diff/ProjectSelector.vala` — `selector_list_box`: no selection

**Why:** A selected pull-over row keeps white title text on the light `@theme_bg_color` background.
**Where:** The `selector_list_box` constructor, the `selection_mode` line.
**Depends on:** none.

#### Remove

```vala
			this.selector_list_box = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.SINGLE,
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
				hexpand = true,
				vexpand = true,
			};
```

## Attempts / changelog

- ✔️ `examples/oc-test-source-diff/ProjectSelector.vala` — `selector_list_box` `selection_mode` is `NONE`, same as the desktop list.

## Next

- 🚫 Closed by request. The tablet check was not done.
