# Markdown: digit-leading links not parsed; GTK links

## Problem

- **Symptom (historical):** Digit-led link text did not parse as a link in some traces; later, **`oc-test-gtkmd`** showed **plain text and no hover** for **both** the digit-led and letter-led links in `tests/markdown/link-digit-start.md`, even when **`oc-markdown-test`** already showed **`<a>`** for both — so GTK did not match the parser output.
- **Repro:** `tests/markdown/link-digit-start.md` — `build/oc-markdown-test …` vs `build/oc-test-gtkmd …`.
- **Expected:** Parser emits links; GTK shows blue/underline, pointer + tooltip, activatable `link_clicked`. **Actual (before fixes):** parser gap for digit lead; then GTK showed **no** link chrome for spans the parser had already accepted.

## Attempts / changelog

_(See **`docs/bug-fix-process.md`** § DEBUG first — issue log.)_


1. **FormatMap** — Registered explicit LINK map keys `[1.` and `[1?` (in addition to `[??`) so digit/path-style leads could match without broad MarkerMap wildcard changes.
2. **MarkerMap** — Reverted experimental wildcard expansion (`./_-`, digits); user asked to prefer explicit map entries over wildcard changes.
3. **FormatMap `[11`** — Present in tree as `FormatType.LINK` (verify intent; may interact with sequence matching).
4. **Debug logging (`libocmarkdown/FormatMap.vala`)** — On existing failure paths only, single `GLib.debug` per branch:
   - `eat_link` returns `-1` → log `eat_link need more input …`
   - `eat_link` returns `0` → log `eat_link no match …`
   - No extra locals beyond what fits one line; messages omit class/method names (per project rules).
5. **Runs:** `build/oc-markdown-test --debug tests/markdown/link-digit-start.md` — **no** `eat_link` debug lines for the digit line.
6. **Runs:** Minimal repro where LINK matches but `eat_link` rejects (`[ab]x`) — **debug line appears** on stderr; confirms `--debug` + `GLib.debug` path works.
7. **Fixture:** `tests/markdown/links-issues/test.md` — history repro for GTK (`oc-test-gtkmd --thinking`); consider renaming to a more descriptive name (pending).
8. **`libocmarkdowngtk/Render.vala` (GTK):** **`on_a`** used a **shared** `"link"` tag for blue/underline and a **nested** inner `style-N` tag for **`href`/`title`**. **`State.add_text`** only applies the **inner** tag, so the shared `"link"` tag never covered the inserted text → **plain appearance**. **`tag_at_iter`** required **`iter.has_tag(lookup("link"))`** before reading `href` → **no pointer, tooltip, or hit-test**. **Fix:** one **`Gtk.TextTag` per link** with appearance + `href` + `title`, single `add_state` / `close_state`; **`tag_at_iter`** scans tags for **`href`** (no dependency on the global `"link"` name).

## Conclusions

- **Root cause (parser):** In `MarkerMap.eat()`, the sequence `[` maps to **`FormatType.INVALID`** (prefix, not `NONE`). After consuming `[1`, the map still had no key; the fallback branch treated **`matched_type != LINK && != NONE`** as “done” and **`return max_match_length`** (often `0`). That exited **before** the next character could extend the sequence to **`[1.`**, so the explicit `FormatMap` LINK keys for `[1.` never applied. A **`NONE`-only** “keep reading” fix was insufficient because **`INVALID` was still taking the early-return path. **Change in code:** exclude **`INVALID`** from that early return and **`continue`** the loop when `matched_type` is **`NONE` or `INVALID`** (still building a longer key).
- **Confirmed:** With `[ab]x`, `eat_link` returns `0` and (when present) debug prints — toolchain OK.
- **`is_end_of_chunks`:** Not required for this parser path; `oc-markdown-test` can show `<a>` for the digit link when the fix is present.
- **Root cause (GTK):** Shared `"link"` tag + inner tag split (see attempt **8** above). **Fix in tree:** `Render.on_a` + `Render.tag_at_iter` as described.
- **Verify:** Run **`oc-test-gtkmd`** on `tests/markdown/link-digit-start.md` — both lines should look like links with hover; **`link_clicked`** fires for `http(s)` in the test harness.

## What was tried (short)

| Idea | Result |
|------|--------|
| Explicit `[1.` / `[1?` map keys | Needed so `[1.` resolves to LINK once sequence is formed |
| MarkerMap: continue on `NONE` **or** `INVALID` | **Fix:** digit-leading links parse; `oc-markdown-test` shows `<a>` for `[5.1…](…)` |
| **`Render`:** one tag per link + `tag_at_iter` by `href` | **Fix:** GTK applies link styling and hover/click for parsed links |
| Wildcard-only MarkerMap change | Reverted earlier; user preferred map keys |
| `GLib.debug` on `eat_link` fail | Confirmed `eat_link` was not the failure site for digit line |
| `oc-markdown-test --debug` | Valid for `TestAppBase`; stderr shows DEBUG lines |

## Follow-ups

- [x] Parser: **`MarkerMap.eat()` INVALID early-return** (see above).
- [x] Temporary `GLib.debug` in `FormatMap` — removed during diagnosis.
- [x] **GTK renderer:** per-link tag + `tag_at_iter` (`libocmarkdowngtk/Render.vala`).
- [ ] **Manual check:** `oc-test-gtkmd` + main app on real content — confirm hover/click in your environment.
- [ ] Rename `tests/markdown/links-issues/test.md` to a descriptive name; update internal command line (optional).
