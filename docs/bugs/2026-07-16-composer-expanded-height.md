# Composer expanded height wrong; compact needs more top gray

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ A · ✅ C · ✅ B grow · ✅ size Idle · ⏳ shrink on delete ·
🚫 ScrolledWindow still out

### DIAG updates

- 🔷 ✅ TextView alone — height grows.
- 🔷 Sync size without Idle — 🚫; Idle required.
- 🔷 Shrink on delete — `measure()` floors to current `size_request`, so
  target never falls. ✔️ Fix: clear request (`-1,-1`), size from
  `get_line_yrange` (+ margins), not `measure()`.
- 🚫 ScrolledWindow not restored yet.

**Related:**

- ℹ️ Log: `~/.cache/ollmchat/ollmchat.debug.log` (`--debug`)
- ℹ️ Code: `libollmchatgtk/ChatInput.vala` — **no** ScrolledWindow (temp)
- ℹ️ GTK source: `gtkscrolledwindow.c` measure floors to scrollbar height
  when `AUTOMATIC`
- ℹ️ GTK [#3515](https://gitlab.gnome.org/GNOME/gtk/-/issues/3515)

---

## A / C

- 🔷 ✅ Top gray + focus.

## B — evidence

### Inspector (🔷)

- TextView did not fill ScrolledWindow — blank under TextView.

### Debug (✔️)

```
target=44 tv_h=44 upper=44 page=44 sw_h=62
```

### Theme A/B (🔷)

- `GTK_THEME=Default` → **just as bad**. 🚫 Not libadwaita stylesheet.

### DIAG — no ScrolledWindow (🔷 requested, ✔️ applied)

- Expanded mode: `TextView` is a **direct** child of `ChatInput`.
- Height via `text_view.set_size_request(-1, target)` only.
- Cap still applied; **no scroll** while over cap (expected for this test).
- Watch debug: `composer size` / `composer after` — `tv_h` vs `target`.
- 🔷 Reverted to plain `Gtk.TextBuffer` (SourceBuffer fudge 🚫 ruled out).

---

## Root cause (provisional)

- ✔️ ScrolledWindow + `AUTOMATIC` measure floors natural height to scrollbar
  widget height → blank under TextView. Theme ruled out.
- ⏳ Confirm TextView-alone height tracks content; then restore scroll only
  when over cap (`NEVER` under cap / `AUTOMATIC` when capped).

---

## Next

1. 🔷 ⏳ Rebuild, Enter-per-line — does blank go away / does height track?
2. ⏳ If yes → reintroduce ScrolledWindow with policy switch; if no → TextView
   measure/request next.


### TextView fudge (✔️ applied, 🚫 insufficient)

- `GtkSource.Buffer` + `implicit_trailing_newline=false` +
  `pixels_below_lines=0` — gap unchanged.

### GTK measure (✔️ from source)

When `vscrollbar_policy` **may be visible** (`AUTOMATIC`), measure does:

```c
minimum_req = MAX (minimum_req, min_scrollbar_height + sborder…);
natural_req = MAX (natural_req, nat_scrollbar_height + sborder…);
```

So ScrolledWindow natural height is **floored by the scrollbar widget’s
height** even when content is shorter and no bar is shown. That matches
`tv_h=44` / `sw_h=62` (~one scrollbar min height).

`set_size_request(-1, 44)` only raises the **minimum**; parent can still
allocate the **natural** (~62).

---

## Root cause (✔️ provisional — theme ruled out; GTK measure matches numbers)

- Expanded composer uses `vscrollbar_policy = AUTOMATIC` always.
- Short content → ScrolledWindow still requests ≥ scrollbar natural height
  → blank under TextView (`valign=START`, `vexpand=false`).

---

## Proposed fix (💩 — await approval)

Keep scroll only when content exceeds the cap:

1. While `nat_h <= cap` (or no cap): `vscrollbar_policy = NEVER`, pin
   `min_content_height = max_content_height = nat_h` (or use
   `set_size_request(-1, nat_h)` with NEVER so measure uses child min).
2. When `nat_h > cap`: `vscrollbar_policy = AUTOMATIC`,
   `min_content_height = max_content_height = cap`.

Do not rely on Adwaita/theme tweaks. Keep debug until ✅.

#### Replace with (size Idle — both paths; sketch)

```vala
var cap = this.expanded_max_height;
var target = nat_h;
if (cap > 0 && nat_h > cap) {
	target = cap;
	this.scrolled.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
} else {
	this.scrolled.vscrollbar_policy = Gtk.PolicyType.NEVER;
}
this.scrolled.min_content_height = target;
this.scrolled.max_content_height = target;
this.scrolled.set_size_request(-1, -1);
this.text_view.set_size_request(-1, -1);
this.scrolled.queue_resize();
```

---

## Next

1. 🔷 ⏳ Approve scrollbar-policy switch → apply → rebuild → repro.
2. ⏳ Confirm `sw_h == tv_h` in debug when under cap.
