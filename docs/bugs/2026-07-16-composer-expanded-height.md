# Composer expanded height wrong; compact needs more top gray

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ A · ✅ C · ✅ B height + classic scrollbar · ✔️ caret-at-end
bottom pin applied (await user verify)

### Proposed fix — caret short of bottom → ✔️ applied

After size settle, if insert at end: `value = upper - page_size`.


### Strict scrolled policy (GTK docs) — historical

- 🚫 Fighting `Gtk.ScrolledWindow` measure/policy — abandoned.
- ✔️ New: `libollmchatgtk/ScrolledView.vala` — viewport height =
  `content_height` only; TextView scrolls via shared adjustments
  (modelled on upstream GTK `gtkscrolledwindow.c` allocate/measure,
  without scrollbar-min floor / NEVER content-sizing).

**Related:**

- ℹ️ Log: `~/.cache/ollmchat/ollmchat.debug.log` (`--debug`) — truncates each run
- ✔️ Height sizing lives in `ScrolledView` when child is `TextView`
  (`buffer.changed` → yrange → `content_height` / bottom pin).
  `ChatWidget` sets `chat_input.scrolled.max_height`.
- 🚫 Do **not** use `stderr.printf` — use `GLib.debug()` only

---

## A / C

- 🔷 ✅ Top gray + focus.

## B — height (✅ from 22:52 log once settled)

```
composer after expect=328 sw_h=328 tv_h=328 match=1 gap=0 upper=566 page=328
```

---

## Scrollbar never appears (🔷) — evidence 22:52

Over cap the shell **does** enable and allocate the bar:

```
scrolledview vbar -> 1
scrolledview allocate … need_bar=1 vbar=1 sb_mapped=1 sb_child_vis=1
scrolledview allocate scrollbar sb_min=11 sb_nat=11 sb_w=11
```

- ✔️ Logic path works (`need_bar=1`, mapped, allocated 11×328).
- ✔️ Under cap correctly flips `vbar -> 0` once `page` catches `upper`.
- 💩 User still sees **no** scrollbar — almost certainly Adwaita
  `overlay-indicator` opacity (fade/hover) on a non-`scrolledwindow`
  parent (`css_name` is `scrolledview`), so the bar stays invisible.

---

## Root cause (height — ✔️ fixed via ScrolledView)

1. ~~`Gtk.ScrolledWindow` measure fights~~ → ScrolledView.
2. ~~CSS border gap=4~~ → outline.
3. Cap path scrolls content (adj value moves) without a **visible** bar.

---

## Proposed fix (💩 — await approval) → ✔️ applied

Drop overlay-indicator; classic scrollbar when `upper > page`; reserve
`sb_w` so TextView does not sit under the bar.

#### Remove

```vala
this.vscrollbar.add_css_class("overlay-indicator");
```

#### Replace with (allocate — when vbar visible, shrink child)

```vala
/* if vbar_visible: measure sb_w; allocate child to width-sb_w; bar on right */
```

---

## Scroll not quite at bottom with caret at end (🔷)

### Evidence (✔️ 22:59 log)

Over cap, caret following end settles **4px short** of max every time:

```
upper=476 page=328 value=144 max=148 short=4
```

(`short = upper - page - value`; matches `TextView.bottom_margin = 4`.)
Manual nudge later hits true bottom: `value=148`.

### Root cause (✔️)

`scroll_to_mark(..., yalign=1.0)` / TextView’s own scroll-on-insert leaves
adjustment at `upper - page - bottom_margin`, not absolute bottom. Last line
sits a few pixels low.

### Proposed fix (✔️ applied — stop asking)

After size settle, if insert is at buffer end and `upper > page`, pin:

```vala
var max = this.scrolled.vadjustment.upper - this.scrolled.vadjustment.page_size;
if (max > 0.0) {
	this.scrolled.vadjustment.value = max;
}
```

---

## Next

1. 🔷 ⏳ Paste over cap; expect `composer pin bottom` with `value == max`
   (`short=0`).
