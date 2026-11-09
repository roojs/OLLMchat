# Bash frame header, terminal face, and empty status row

**Status:** ✅ 2026-11-09. User closed it. The command title is 14px, the terminal face is 8pt, and a restored chat hides the empty status row.

**ℹ️** The frame is [`2026-11-08-FIXED-bash-frame-not-in-chat.md`](2026-11-08-FIXED-bash-frame-not-in-chat.md). This file is only type size and the status row.

## Problem

- 🔷 The command in the expander bar is slightly larger than a thinking header or another frame title.
- 🔷 The terminal text is about 2pt too big.
- 🔷 A restored chat has a blank band where the live status line would say "Running command in sandbox".
- 🔷 That band stays on the live frame. A restored chat has no status text, so the band goes away.

## Evidence

- ℹ️ Frame titles use `.oc-code-frame-title` at `14px` in `resources/style.css`.
- ℹ️ `.tool-frame .command-preview` is `1.25em` in the same file, shared with the permission card.
- ℹ️ Terminal text is `10pt` in `resources/style.css` and again in `resources/frame.css`. The frame file is the later provider.
- ℹ️ `RenderToolOutput` always appends `status_label`. Restore never sets `status`. An empty label still takes a row between the header and the body. Live sets `status` from the start notification after the frame is built.

## Root cause

- ✔️ The command title opts into a larger size than the other frame titles. The terminal size is the `10pt` rule. The status label is in the column even when `status` is empty.

## Proposed fix

- 🔷 Tool command title is `14px`, the same size as `.oc-code-frame-title`. The permission card stays `1.25em`.
- 🔷 Terminal text is `8pt` in both stylesheets.
- 🔷 The status label starts hidden. It shows when `status` is not empty.
- 🚫 Dropping the status line from the live frame.

### `resources/style.css` — title size and terminal size

**Why:** The shared rule makes the command larger than a frame title, and the terminal rule is `10pt`.

**Where:** the `.command-preview` rule and the `.tool-frame .tool-output` rule.

#### Remove

```css
.permission-widget .command-preview,
.tool-frame .command-preview {
  font-weight: bold;
  font-size: 1.25em;
}
```

#### Replace with

```css
.permission-widget .command-preview {
  font-weight: bold;
  font-size: 1.25em;
}

.tool-frame .command-preview {
  font-weight: bold;
  font-size: 14px;
}
```

#### Remove

```css
  font-size: 10pt;
```

#### Replace with

```css
  font-size: 8pt;
```

**Where:** inside `.tool-frame .tool-output` in this file only.

### `resources/frame.css` — terminal size

**Why:** This file loads after `style.css` and sets the same `10pt`, so the terminal stays large unless both change.

**Where:** `.oc-frame.tool-frame .tool-output`.

#### Remove

```css
    font-size: 10pt;
```

#### Replace with

```css
    font-size: 8pt;
```

### `libocmarkdowngtk/RenderToolOutput.vala` — hide an empty status

**Why:** Restore never sets `status`. A hidden label takes no row. Live sets `status` after construction, and the notify handler shows the label.

**Where:** the `status_label` construction and its `notify["status"]` handler.

#### Remove

```vala
			this.status_label = new Gtk.Label("") {
				halign = Gtk.Align.START,
				wrap = true
			};
			this.notify["status"].connect(() => {
				this.status_label.label = this.status;
				if (this.status == "Running command as root (sudo)") {
					this.add_css_class("root");
				}
			});
```

#### Replace with

```vala
			this.status_label = new Gtk.Label("") {
				halign = Gtk.Align.START,
				wrap = true,
				visible = false
			};
			this.notify["status"].connect(() => {
				this.status_label.label = this.status;
				this.status_label.visible = this.status != "";
				if (this.status == "Running command as root (sudo)") {
					this.add_css_class("root");
				}
			});
```

## Attempts / changelog

- ✔️ 2026-11-09 — sizes read from `style.css` and `frame.css`. Status row read from `RenderToolOutput.construct`.
- ✔️ 2026-11-09 — command title `14px`, terminal face `8pt`, empty status label hidden. Rebuilt and installed on `emulator-5556`.

## Next

- ✔️ 2026-11-09 — user closed it on the tablet.
