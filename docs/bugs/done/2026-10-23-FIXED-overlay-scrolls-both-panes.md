# Overlay scroll moves both panes

**Status:** ✅ User confirmed the folder list scrolls on its own. Closed 2026-10-24.

## Problem

- 🔷 Scrolling the folders on the left also moves the file list on the right off the screen.
- 🔷 The file list has only a few rows. It should stay put. It has no reason to scroll.

## Evidence

- ℹ️ `FileOverlay` put one `Gtk.ScrolledWindow` around the stack. That stack's tree page is a pane: folders on the left, `FileList` on the right.
- ℹ️ On the tablet the left child is `FolderBrowse`, which has no scroll of its own. Its height is every folder row, so the outer scroll grows to that height and scrolls the pane, including the file list.
- ℹ️ `FileList` already has its own scroll. The phone sheet scrolls only the folder column. `FilePullout`.

## Root cause

- ✔️ The scroll is around both panes. The folder list needs the scroll. The file list does not.

## Proposed fix

### `examples/oc-test-source-diff/FileOverlay.vala`

**Why:** The folder list scrolls inside the pane. The file list keeps the scroll it already has. Recent keeps a scroll of its own.

**Where:** The tablet folder child, the Recent page, and the sheet body.

#### Remove

```vala
			var scroll = new Gtk.ScrolledWindow() {
				child = this.pages,
				hexpand = true,
				vexpand = true,
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				can_focus = false,
			};
			this.list.append(scroll);
```

#### Replace with

```vala
			this.list.append(this.pages);
```

#### Add — tablet folder child

```vala
				folders = new Gtk.ScrolledWindow() {
					child = this.browse,
					hexpand = true,
					vexpand = true,
					hscrollbar_policy = Gtk.PolicyType.NEVER,
				};
```

#### Add — Recent page

```vala
			this.pages.add_titled(new Gtk.ScrolledWindow() {
				child = this.recent_list,
				hexpand = true,
				vexpand = true,
				hscrollbar_policy = Gtk.PolicyType.NEVER,
			}, "history", "Recent");
```

## Next

- ✔️ Applied in `FileOverlay.vala`. The tablet app has to be rebuilt and installed. The daemon is unchanged.

## Conclusion

- ✅ 🔷 The folder list scrolls inside the pane. The file list stays put. User closed this bug on 2026-10-24.
