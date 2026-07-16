# Composer expanded height wrong; compact needs more top gray

> Pointer: `docs/bug-fix-process.md` (emoji + code fences). Legend:
> `docs/guide-to-writing-plans.md` — Discussion style (emoji prefixes).

**Status:** ✅ A · ✅ C · ✔️ B root cause from logs — ⏳ fix proposed, await apply

**Related:**

- ℹ️ Debug log: `~/.cache/ollmchat/ollmchat.debug.log`
- ℹ️ Code: `libollmchatgtk/ChatInput.vala`

---

## Evidence (2026-07-16 ~10:45 from debug log)

Pattern on every Enter (example **serial=8**, second Enter, `nl=2 ends_nl=1`):

```
apply  … h=62 want_min=62 upper=62 page=44 tv_h=44 sw_h=62
after  … min=62 max=328 sw_h=62 tv_h=44 upper=62 page=44 value=0
```

- Measure is **correct** (`h=62`, `want_min=62`).
- ScrolledWindow grows (`sw_h=62`, `min=62`).
- TextView stays short (`tv_h=44`, `page=44`).
- `upper=62 > page=44` → **scrollbar** + blank band (18px) under the short TextView.

Next character (**serial=9–10**):

```
apply  … tv_h=62 sw_h=66 page=44 value=14   ← still scrolled mid-fix
after  … page=62 value=0                    ← then settles
```

Same pattern at serial=17 (3rd Enter): `want_min=80` but `after` still `tv_h=62 page=62` until the following keystroke.

First expand (serial=1): `h=44` for one line + trailing newline geometry — OK-ish; problem is **growth** Enters.

---

## Root cause (from numbers)

✔️ **Not** “measure one line short.” `get_line_yrange` / `want_min` already match content on Enter.

✔️ **Layout gap:** we set `ScrolledWindow.min_content_height` and the window’s `sw_h` updates, but `TextView` keeps the **previous** allocated height for that frame (`tv_h` lags `h`). With `valign=START` + `vexpand=false`, the TextView does not fill the taller scrolled area → blank below + `page < upper` → scrollbar. Next buffer change forces another allocate and `tv_h` catches up.

---

## Proposed fix (await approval)

1. When applying size, also **`text_view.set_size_request(-1, want_min)`** (or clear request when collapsing) so the child height matches the measured content in the same pass — not only the ScrolledWindow min.
2. Keep `min_content_height = want_min`; keep `max_content_height = cap`.
3. Optionally set `valign = FILL` + `vexpand = true` so the TextView fills the scrolled allocation if request still lags — secondary; try size-request first.
4. Leave debug lines until user ✅.

#### Replace with — size apply (both Idle sites)

After computing `want_min` / `want_max`:

```vala
this.scrolled.min_content_height = want_min;
this.scrolled.max_content_height = want_max;
this.text_view.set_size_request(-1, want_min);
this.scrolled.queue_resize();
```

On flip back to compact: `this.text_view.set_size_request(-1, -1);`

---

## Attempts (height)

| # | Change | Result |
|---|--------|--------|
| 1–6 | Various measure/pin/Idle/Pango | 🚫 failed — were fixing the wrong layer |
| debug | log apply/after | ✔️ showed tv_h lag |

---

## Next

1. 🔷 ⏳ Approve size-request fix above, then test Enter / paste.
2. 💩 ⏳ Remove composer debug after ✅.
)