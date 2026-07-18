# ScrolledView scrollbar shows before content hits max

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** FIXED (2026-07-18) — bar only when at `max_height` and `upper > page`

**Related:**

- ℹ️ Prior: `docs/bugs/done/2026-07-16-FIXED-composer-expanded-height.md`
- ℹ️ `libollmchatgtk/ScrolledView.vala` — `size_allocate` / `vadjustment.changed`

---

## Problem

- 🔷 Scrollbar appeared while the composer was still growing (under
  `max_height`) — before scroll was needed.
- 🔷 Expected: bar hidden until content hits the cap and still overflows.

---

## Root cause (✔️)

Visibility used `upper > page_size` alone. While under cap the viewport is
still growing; stale/smaller `page_size` vs new `upper` made the bar flash
on early (and reserved `sb_w` could worsen wrap).

---

## Fix (✔️ applied — user: stop asking, just fix)

#### Replace with

```vala
var over_cap = this.max_height > 0 && this.content_height >= this.max_height;
var need = over_cap
	&& this.vadjustment.upper > this.vadjustment.page_size + 0.5;
```

in `size_allocate` and `vadjustment.changed`.
