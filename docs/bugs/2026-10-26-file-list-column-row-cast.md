# File list aborts on folder load

**Status:** ⏳ root cause confirmed; fix applied — await device check

## Problem

- 🔷 Opening a folder in the file grid aborts.
- 🔷 Log: `invalid cast from 'GtkColumnViewRow' to 'GtkWidget'`, then `ApplicationInterface.vala:208` treats that critical as fatal.
- 🔷 Expected: the folder's files show, and the open file keeps the `selector-mark` paint.

## Evidence

- ✔️ Bind handler `liboccoder/File/List.vala:268` casts the row-factory object to `Gtk.Widget` and calls `remove_css_class`.
- ✔️ Stack: `Folder.fetch_dir` reply → `ListStore.load` `items_changed` → column-view row bind → that cast → `SIGABRT`.
- ℹ️ GTK 4.18 `GtkColumnViewRow` subclasses `GObject`. It has no widget methods. The painted node is the private row widget, CSS name `row`, parent of each cell.
- ℹ️ Cell bind runs after that cell is parented to the row. `row.selector-mark` in `resources/style.css` matches a CSS class on that row widget.
- ℹ️ `docs/bugs/done/2026-10-21-FIXED-file-sheet-return-to-open-file.md` added the cast because `ColumnViewRow` is not a `Gtk.Widget`.

## Root cause

- ✔️ `selector-mark` is applied by casting `GtkColumnViewRow` to `GtkWidget`. That cast is invalid. The row factory object is not the widget the stylesheet paints.

## Proposed fix

- 🔷 Row factory only sets `selectable` and `activatable`.
- 🔷 Name-cell bind walks from the name box to the widget whose CSS name is `row`, then adds or removes `selector-mark` there, including the `is-active` watch.
- 🚫 Do not cast `ColumnViewRow` to `Gtk.Widget`. Do not read the private `owner` field.

### `liboccoder/File/List.vala` — name cell paints the row

**Why:** The name box is parented under the cell, and the cell is parented under the row widget, before this bind runs.

**Where:** `name_factory.bind`, after the tooltip binding. New `name_factory.unbind`.

#### Add

```vala
				var host = (!) line.get_parent();
				while (host.css_name != "row") {
					host = (!) host.get_parent();
				}
				host.remove_css_class("selector-mark");
				if (file.is_active) {
					host.add_css_class("selector-mark");
				}
				host.set_data("active-watch", file.notify["is-active"].connect(() => {
					if (file.is_active) {
						host.add_css_class("selector-mark");
						return;
					}
					host.remove_css_class("selector-mark");
				}));
			});
			name_factory.unbind.connect((obj) => {
				var row = (Gtk.ListItem) obj;
				var host = (!) ((!) row.child).get_parent();
				while (host.css_name != "row") {
					host = (!) host.get_parent();
				}
				((OLLMfiles.File) row.item).disconnect(host.get_data<ulong>("active-watch"));
				host.remove_css_class("selector-mark");
```

### `liboccoder/File/List.vala` — row factory stops casting

**Why:** `selectable` and `activatable` belong on `ColumnViewRow`. The CSS class does not.

**Where:** `row_factory.bind` and its `unbind`.

#### Remove

```vala
			row_factory.bind.connect((obj) => {
				var view_row = (Gtk.ColumnViewRow) obj;
				var shown = (OLLMfiles.File) view_row.item;
				var openable = shown.points_to_id != -1;
				view_row.selectable = openable;
				view_row.activatable = openable;
				((Gtk.Widget) view_row).remove_css_class("selector-mark");
				if (shown.is_active) {
					((Gtk.Widget) view_row).add_css_class("selector-mark");
				}
				var active_watch = shown.notify["is-active"].connect(() => {
					if (shown.is_active) {
						((Gtk.Widget) view_row).add_css_class("selector-mark");
						return;
					}
					((Gtk.Widget) view_row).remove_css_class("selector-mark");
				});
				view_row.set_data("active-watch", active_watch);
			});
			row_factory.unbind.connect((obj) => {
				var view_row = (Gtk.ColumnViewRow) obj;
				var shown = (OLLMfiles.File) view_row.item;
				shown.disconnect(view_row.get_data<ulong>("active-watch"));
				((Gtk.Widget) view_row).remove_css_class("selector-mark");
			});
```

#### Replace with

```vala
			row_factory.bind.connect((obj) => {
				var view_row = (Gtk.ColumnViewRow) obj;
				var openable = ((OLLMfiles.File) view_row.item).points_to_id != -1;
				view_row.selectable = openable;
				view_row.activatable = openable;
			});
```

## Attempts / changelog

- ✔️ Removed the widget cast from the row factory. Mark follows the name cell up to the `row` CSS node.

## Next

- ⏳ Reopen a folder in the file grid. The process should stay up, and the open file should still show `selector-mark`.
