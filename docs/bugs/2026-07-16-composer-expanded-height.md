# Composer expanded height wrong; compact needs more top gray

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ A fixed · ⏳ B still broken · ⏳ C focus ring open ·
🚫 stop repeating failed height tricks · research recorded 2026-07-16

**Related:**

- ℹ️ Plan: [`docs/plans/1.30-chat-input-composer.md`](../plans/1.30-chat-input-composer.md)
- ℹ️ Code: `libollmchatgtk/ChatInput.vala`
- ℹ️ CSS: `resources/style.css` (`.chat-composer*`)
- ℹ️ GTK docs: `Gtk.TextView.scroll_to_iter` / `scroll_to_mark`;
  `GTK_TEXT_VIEW_PRIORITY_VALIDATE`
- ℹ️ GTK issue: [ScrolledWindow + TextView max_content_height #3515](https://gitlab.gnome.org/GNOME/gtk/-/issues/3515)
- ℹ️ Libadwaita: [Linked Controls](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/style-classes.html#linked-controls)

---

## Problem

### A — Compact strip top padding

- 🔷 ✅ Fixed — `.chat-composer` padding top `8` → `13` (+5px gray).
- ℹ️ Bottom gap moved to `ChatBar.margin_top` (8px).

### B — Expanded height / scrollbar (main bug)

- 🔷 Grow with lines until ~half chat height, then scroll; no premature
  scrollbar; no dead blank band.
- 🔷 **Still broken.** Enter → undersize / scrollbar / line off top;
  **next character** corrects. Paste large text → ~**2×** height + bottom
  dead space.

### C — Compact focus ring missing

- 🔷 No usable focus border on the single-line entry (after flip / focus).

---

## Research (2026-07-16) — not guesses

### B — why Timeouts + `get_line_yrange` failed

1. ✔️ **GTK documents that line heights are async.**
   `gtk_text_view_scroll_to_iter` docs (GTK4):

   > Line heights are computed in an **idle handler**; so this function may
   > not have the desired effect if it’s called before the height
   > computations. To avoid oddness, consider using
   > **`gtk_text_view_scroll_to_mark()`** which saves a point to be scrolled
   > to **after line validation**.

   Same constraint applies to **`get_line_yrange` / iter locations**: they
   read the **currently computed** layout. Until validation idle runs,
   Y/height can still reflect the **previous** buffer geometry.

2. ✔️ **That matches our symptom exactly.** Enter inserts `\n` → we measure
   (even 40ms later, twice) → still short → pin `min=max=h` → scrollbar.
   Next character triggers another change **after** validation has caught
   up → measure correct. Double Timeout changed nothing because both passes
   can still see the **same pre-validation** geometry.

3. ✔️ **We also call `scroll_to_iter` on every `buffer.changed`.** Docs say
   that is the unreliable API. Fighting resize + premature scroll is a known
   class of “content jumps / blank under caret” bugs (same pattern reported
   for growing text views elsewhere: scroll runs against stale height, then
   leaves empty space when height catches up).

4. ℹ️ **GTK #3515:** `ScrolledWindow` + `TextView` + `max_content_height` with
   `AUTOMATIC` scrollbar often **refuses to grow** and shows scrollbars
   early; with `NEVER` it expands but can leave cursor above blank.
   Manual `min`/`max` pinning on top of that is fragile.

5. ✔️ **Implication:** Attempt #2–#4 were measuring the **wrong layer**
   (TextView buffer coords before validation). More delays on the same API
   are 🚫.

### C — why hand-rolled square corners fight the focus ring

1. ✔️ **Libadwaita linked controls:** put class **`linked`** on the
   **container** `Gtk.Box` (spacing 0). Officially supports linking
   `Gtk.Entry` + `Gtk.Button` so they read as one control with theme
   focus handling.

2. ✔️ **Opaque / suggested / custom filled buttons break linked chrome**
   (libadwaita style-classes doc). Our play uses `chat-composer-send`
   (solid blue) — similar to `.opaque` / `.suggested-action`. So square
   CSS alone will not get theme focus continuity; may need
   `:focus-within` outline on the **row**, or drop custom radius hacks
   and use `.linked` + a focus ring that we control.

3. 💩 Custom `border-radius: 0` on entry right + `background-color: white`
   on entry without preserving outline / focus-within styles can hide or
   clip Adwaita’s outline-based focus ring.

---

## Attempts / changelog — FAILED paths (do not retry)

| # | Change | Result |
|---|--------|--------|
| 1 | `propagate_natural_height` + `max` only | Too tall / blank |
| 2 | Timeout + `get_line_yrange` + pin min=max | Enter→scrollbar; key fixes |
| 3 | Margins / ChatBar / join CSS | Polish; B unchanged |
| 4 | Double-pass + `size_serial` | 🚫 zero difference; paste ~2× |

**🚫 Do not try again:** longer Timeouts, N remasure passes, `size_serial`
tweaks, or any height fix that still keys off **`get_line_yrange` /
`scroll_to_iter` before line validation**.

---

## Proposed next effort (research-based — await approval)

### B5 — Stop trusting TextView layout coords for height; stop premature scroll

**Step 1 — Revert dead machinery**

Remove Timeout / `size_serial` / `get_line_yrange` pin from
`buffer.changed` and `focus_idle`.

**Step 2 — Stop `scroll_to_iter` on every change**

- Remove `place_cursor` + `scroll_to_iter` from the hot `buffer.changed`
  path (they fight validation and cause scroll-off / blank bottom).
- If end-pinning is still needed after paste/flip: use **`scroll_to_mark`**
  on the insert mark / end mark (GTK’s recommended API), or an idle at
  priority **after** `GTK_TEXT_VIEW_PRIORITY_VALIDATE`
  (`G_PRIORITY_HIGH_IDLE + 15` is validate; schedule lower priority so
  validation finishes first — see GNOME Discourse on scroll-after-render).

**Step 3 — Height from Pango (content model), not buffer Y**

On buffer change / width allocate, **synchronously**:

1. Build a `Pango.Layout` from `text_view.create_pango_layout(text)` (or
   buffer text).
2. Set width to allocated text width (scrolled width − left/right margins)
   with wrap matching `WORD_CHAR`.
3. `h = layout.get_pixel_size().height + top_margin + bottom_margin`
   (and a small fudge only if measured against Entry once — document it).
4. Cap with `expanded_max_height`.
5. Set `min_content_height` / `max_content_height` from that **without**
   waiting for TextView validation.

**Why this is not #2–#4:** height comes from **string + font + wrap width**,
which updates the instant `\n` is in the buffer — same moment a typed
character would. No dependency on TextView’s idle line validation.

**Debug (one line, keep until ✅):** `lines`/`pixel_h`/`h`/`width` via
`GLib.debug` under `--debug`.

### C5 — Use Adwaita `.linked` + focus-within (separate small CSS pass)

1. Add `linked` to `compact_row`; remove hand-squared radius CSS that
   fights the theme (or keep only what `.linked` does not provide).
2. If blue send still breaks linked focus: draw
   `.chat-composer-compact:focus-within { outline: … }` (or border) around
   the **row**, so focus reads as one full-width control.
3. Do **not** mix C into the height algorithm.

---

## Next

1. 🔷 ⏳ User approve **B5** (revert + no scroll_to_iter on change + Pango
   height) for a test build.
2. 🔷 ⏳ User approve **C5** (`.linked` / `:focus-within`) — can ship with
   B5 or right after.
3. 🚫 No more Timeout / `get_line_yrange` patches.
)