# Selector search focus and file-search bar height

**Status:** ⏳

**Started:** 2026-10-09

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ Plan: `docs/plans/CODER-4.2.5-project-file-selector.md`
- ℹ️ Desktop run: `./build/examples/oc-test-source-diff --selectors`
- ℹ️ Working pattern: `liboccoder/SearchableDropdown.vala` (`autohide = false`, `can_focus = false`, focus stays in the entry)

---

## Problem

🔷 User, desktop `--selectors`, after the project pop-down height and alphabetical order:

- 🔷 Project search, on click, does not focus the cursor in the text entry.
- 🔷 The user cannot type in that text entry. It is non-functional.
- 🔷 The file selector turns the height of the left button to maximum height.
- 🔷 Selecting file search expands the top bar to about fifty percent of the screen.
- 🔷 The project pop-down height (inside the window) and the project order were the parts that landed. These two did not.
- 🔷 Enter and Tab should accept the highlighted row on every tab and move to the next control. Tested: they do not.
- 🔷 The file selector is not searching files.
- 🔷 The file pop-down is slightly wider than the window.

Reproduce:

- ℹ️ `ninja -C build examples/oc-test-source-diff`
- ℹ️ `./build/examples/oc-test-source-diff --selectors`
- 🔷 Click the project control. The pop-down can show. The caret is not in the search entry. Keystrokes do nothing.
- 🔷 Choose a project, then click the file control so it becomes file search. The left button grows, and the top bar grows to about half the window.

---

## Evidence

- ✔️ GTK 4.18.5 `gtk_popover_show`: when `autohide` is true (the default), show moves focus to the first focusable child inside the popover.
- ✔️ `gtk_popover_map`: that same `autohide` adds a grab on the popover. Keys go to the popover, not to a widget outside it.
- ℹ️ The search entry is the button's replacement in the top row. It is not inside the popover.
- ✔️ `ProjectSelector` calls `grab_focus()` and then `popover.popup()`. The popup runs after that grab, so the caret does not stay in the entry.
- ℹ️ `SearchableDropdown` sets `autohide = false` and `can_focus = false` on the popover and the list so the entry keeps the keyboard.
- ✔️ File search calls `place()`, which sets the file scrolled window `min_content_height` and `max_content_height` to the space under the row. That scrolled window, its page stack, and its lists are `vexpand`. The file control starts with `min_content_height = 240`, about half of the 520px test window.
- ℹ️ A `Gtk.Popover` is a native. A box does not include natives in its own measure. The bar growth is still tied to that file-search open: it is the only path that forces this control to the leftover window height, and the left button shares the row so it stretches with it.

---

## Root cause

- ✔️ Project entry: default popover `autohide` steals focus and the keyboard on `popup()`. The grab runs before the caret is put back.
- ✔️ File bar: file search forces the popover contents to the leftover window height (`min_content_height = room`) and those contents `vexpand`. The row then lays out that tall, and the left button fills it.

---

## Proposed fix

### Project entry — `examples/oc-test-source-diff/ProjectSelector.vala`

#### Replace with

```vala
		this.popover = new Gtk.Popover() {
			has_arrow = false,
			position = Gtk.PositionType.BOTTOM,
			halign = Gtk.Align.START,
			autohide = false,
			can_focus = false,
			child = this.scroll,
		};
```

```vala
		this.scroll.can_focus = false;
		this.rows.can_focus = false;
```

```vala
			GLib.Idle.add(() => {
				this.place();
				this.entry.text = "";
				this.popover.popup();
				this.entry.grab_focus();
				this.entry.set_position(-1);
				this.entry.select_region(-1, -1);
				return false;
			});
```

#### Add

Focus leave on the entry pops the list down unless focus moved inside the popover. Same rule as `SearchableDropdown`.

### File bar — `examples/oc-test-source-diff/FileSelector.vala`

#### Replace with

The file popover uses the same `autohide = false` / `can_focus = false` / focus-after-popup path.

`place()` sets `max_content_height` only. It does not set `min_content_height` to the leftover window height.

The file scrolled window, page stack, and lists do not `vexpand`. The file control and the row use `valign = START`. The left button uses `valign = CENTER` so it stays one line.

---

## Attempts / changelog

- ✔️ 2026-10-09 — Recorded the two reports above. Earlier edits fixed project pop-down height and basename sort only.
- ✔️ 2026-10-09 — Applied the proposal in `ProjectSelector.vala` and `FileSelector.vala`.
- ✔️ 2026-10-09 — Recorded Enter, Tab, file search, and file pop-down width. Those were not in this log.

## Next

- ⏳ 🔷 User checks `--selectors`: project click leaves a caret in the entry and typing filters the list.
- ⏳ 🔷 User checks file search: the left button and the top bar stay one row.
- ⏳ 🔷 User checks Enter and Tab: the highlighted row is accepted and focus moves to the next control.
- ⏳ 🔷 User checks file search: typed text shows matching files.
- ⏳ 🔷 User checks the file pop-down stays inside the window.
