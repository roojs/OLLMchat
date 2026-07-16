# Composer expanded height wrong; compact needs more top gray

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ fixed — custom `OLLMchatGtk.ScrolledView` owns composer height

**Related:**

- ℹ️ Plan: `docs/plans/1.30-chat-input-composer.md`
- ✔️ `libollmchatgtk/ScrolledView.vala` — app-owned scroll shell
- ✔️ `libollmchatgtk/ChatInput.vala` — compact/expanded; height via `scrolled`
- ✔️ `ChatWidget` sets `chat_input.scrolled.max_height`
- 🚫 Do not fight `Gtk.ScrolledWindow` measure/policy for this composer

---

## Problem

- 🔷 Expanded composer height wrong / laggy vs content; compact top gray /
  focus polish.
- 🔷 Over cap: need a visible classic scrollbar and caret flush at bottom.
- 🔷 Expected: viewport height tracks TextView content up to max; scroll
  only when over cap; no measure/snapshot GTK warnings.

---

## Final answer ✅

**Do not use `Gtk.ScrolledWindow` for the expanded composer.** Its
measure/policy loop fights app-owned height (extra gap, EXTERNAL quirks,
overlay scrollbar invisibility).

**Use a custom scroll shell:** `OLLMchatGtk.ScrolledView`

| Piece | Behaviour |
| ----- | --------- |
| Viewport | `content_height` only (min = nat); capped by `max_height` |
| TextView child | `buffer.changed` → Idle → line yrange → `content_height` |
| Scroll | shared `vadjustment` / `hadjustment` (GTK scrollable model) |
| Bar | classic `Gtk.Scrollbar` when `upper > page_size`; reserve `sb_w` |
| Pin end | after allocate, if caret at end: `value = upper - page_size` |
| Focus CSS | outline on `.chat-composer-expanded` (not border — avoided gap=4) |

Allocate/measure for the bar follow upstream `gtkscrolledwindow.c`:
`measure(HORIZONTAL, -1)`, and `set_child_visible` only inside
`size_allocate` (avoids snapshot-without-allocation and height-for-width
warnings).

---

## What was tried / ruled out

- 🚫 Fighting `Gtk.ScrolledWindow` NEVER/EXTERNAL / content-sizing — abandoned.
- 🚫 Overlay-indicator scrollbar on non-`scrolledwindow` parent — invisible.
- 🚫 CSS border for focus — caused `gap=4`; use outline.
- 🚫 Emitting `buffer.changed` to force fit — invalid TextIter warnings;
  use `queue_fit()` / offsets instead of holding iters across mutation.

---

## Historical evidence (settled height)

```
composer after expect=328 sw_h=328 tv_h=328 match=1 gap=0 upper=566 page=328
```

Caret short of bottom was `bottom_margin` (4px); fixed by pin to
`upper - page_size` in `size_allocate`.
