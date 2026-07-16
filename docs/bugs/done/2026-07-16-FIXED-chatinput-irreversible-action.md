# ChatInput: irreversible action while in user action

**Status:** ✅ fixed — measure-only overflow + CAPTURE Enter; debug removed

## Problem

- **🔷** Typing in the composer: irreversible-action warnings; input sticks / does not accept further chars.
- **🔷** Expected: quiet typing; mode from value without rewriting the widget mid-edit.

## Evidence (user `--debug`, compact Entry)

- **✔️** Path is **compact**, not TextView: `compact changed len=1` → `update_entry` → overflow measure → `same-compact match return`.
- **✔️** Warning fires **between** `update_entry` start and overflow measure log — i.e. while executing:
  `this.compact_entry.text = text` under `syncing` (nested `compact changed skipped syncing=true`).
- **✔️** `len=1` repeats across keystrokes — assign-during-`changed` fights the Entry user action.
- **✔️** `layout_w=0` with `alloc_w=605` — overflow measure is wrong (always no-expand); separate from warnings but same block.
- **🚫** Prior “same-mode `set_text` on TextBuffer” theory — not the path in this repro.
- **🚫** CSS `overflow` — unrelated.

## Root cause

- **✔️** Overflow-measure block **rewrites** `compact_entry.text` on every compact `changed` to measure width. GTK Entry treats that as an irreversible undo action inside the typing user action → warnings + broken input.
- **ℹ️** Measure does not need to write the Entry — `text` is already the parameter.

## Proposed fix

- **🔷** In overflow measure: **remove** `this.compact_entry.text = text` (and the syncing wrap around that write). Only `create_pango_layout(text)` + extents vs allocation.
- **🔷** Keep debug lines until verified.
- **💩** `layout_w=0`: after removing the write, recheck; if still 0, next step is measure API (e.g. `get_pixel_size` / font from pango context) — not in this patch unless still broken after repro.

### `libollmchatgtk/ChatInput.vala` — overflow measure only

#### Remove

```vala
			if (!want_expanded && this.compact_entry.get_allocated_width() > 0) {
				this.syncing = true;
				this.compact_entry.text = text;
				/* GTK4 Entry has no get_layout; measure via Widget.create_pango_layout. */
				var layout = this.compact_entry.create_pango_layout(text);
				Pango.Rectangle ink;
				Pango.Rectangle logical;
				layout.get_pixel_extents(out ink, out logical);
				want_expanded = logical.width > this.compact_entry.get_allocated_width();
				GLib.debug("update_entry overflow measure layout_w=%d alloc_w=%d want_expanded=%s",
					logical.width, this.compact_entry.get_allocated_width(),
					want_expanded.to_string());
				this.syncing = false;
			}
```

#### Replace with

```vala
			if (!want_expanded && this.compact_entry.get_allocated_width() > 0) {
				/* Measure only — do not assign Entry.text (fights user action / undo). */
				var layout = this.compact_entry.create_pango_layout(text);
				Pango.Rectangle ink;
				Pango.Rectangle logical;
				layout.get_pixel_extents(out ink, out logical);
				want_expanded = logical.width > this.compact_entry.get_allocated_width();
				GLib.debug("update_entry overflow measure layout_w=%d alloc_w=%d want_expanded=%s",
					logical.width, this.compact_entry.get_allocated_width(),
					want_expanded.to_string());
			}
```

## Attempts / changelog

- **✔️** First fix (TextBuffer same-mode): wrong path for this repro.
- **✔️** Debug lines → compact overflow `Entry.text =` is the warning site; len stuck at 1.

## Attempts / changelog (cont.)

- **✔️** Removed `compact_entry.text =` from overflow measure; debug kept; rebuild OK.

## Compact Enter (follow-on)

- **✔️** Typing OK after measure-only fix; `layout_w` grows (28…56).
- **✔️** Enter log: only `compact Entry activate` — **no** `compact Enter` from `key_pressed`. Entry eats Return before bubble-phase controller.
- **🔷** Do **not** put expand/`update_entry(text+"\n")` on `activate`.
- **🔷** Proposed: `compact_keys.propagation_phase = CAPTURE` so existing `key_pressed` Enter path runs; remove all debug + the temporary `activate` connect.

### `ChatInput.vala` — compact keys + strip debug

#### Add — after `var compact_keys = new Gtk.EventControllerKey();`

```vala
			compact_keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
```

#### Remove — debug-only `activate` connect

```vala
			this.compact_entry.activate.connect(() => {
				GLib.debug("compact Entry activate (Enter may have been eaten here)");
			});
```

#### Remove — all other temporary `GLib.debug(...)` in this file (changed / update_entry / Enter).

## Attempts / changelog (Enter)

- **✔️** CAPTURE on compact keys.
- **✔️** Removed temporary debug / `activate` probe.

## Next

- **✅** Typing + Enter expand verified; debug removed; archived.

