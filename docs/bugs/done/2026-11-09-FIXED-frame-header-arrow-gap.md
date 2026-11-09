# Frame header title sits too far from the collapse arrow

**Status:** ✅ 2026-11-09. User closed it. The title sits against the collapse arrow.

## Problem

- 🔷 On a frame header, the title sits wide of the expand or collapse arrow.
- 🔷 The button's own padding is enough. The extra gap can go.

## Evidence

- ℹ️ `RenderSourceView` gives the collapse button `margin_end = 4`.
- ℹ️ `RenderToolOutput` uses a horizontal box spacing of 6 between the arrow and the command.
- ℹ️ `.oc-frame button` is `transform: scale(0.7)` with `transform-origin: center`. The layout box stays full width, so the unused right side reads as more gap before the title.

## Root cause

- ✔️ The title is pushed off the arrow by that margin and spacing, and by the centered scale.

## Proposed fix

- 🔷 Drop the collapse button's end margin and the tool header spacing.
- 🔷 Scale that first header button from its right edge so the arrow sits against the title. The button box remains the padding. Other header buttons stay centered.

### `libocmarkdowngtk/RenderSourceView.vala` — collapse button

**Why:** `margin_end` is the extra gap before the title.

**Where:** the `collapse_toggle_button` construction.

#### Remove

```vala
				hexpand = false,
				margin_end = 4,
				can_focus = false,
```

#### Replace with

```vala
				hexpand = false,
				can_focus = false,
```

### `libocmarkdowngtk/RenderToolOutput.vala` — header row

**Why:** The box spacing is the extra gap before the command.

**Where:** the header `Gtk.Box` construction.

#### Remove

```vala
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
```

#### Replace with

```vala
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
```

### `resources/frame.css` — pin the arrow to the title

**Why:** A centered 0.7 scale leaves empty layout space between the glyph and the title.

**Where:** after the `.oc-frame button` rule that sets `transform-origin: center`.

#### Add

After `transform-origin: center` on `.oc-frame button`, scale the first header button from the side next to the title.

```css
.oc-frame .oc-frame-header > button:first-child {
    transform-origin: right center;
}
```

## Attempts / changelog

- ✔️ 2026-11-09 — dropped the collapse end margin and the tool header spacing. The first header button scales from its right edge. Installed on `emulator-5556`.

## Next

- ✔️ 2026-11-09 — user closed it on the tablet.
