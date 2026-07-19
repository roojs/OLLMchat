# Android chat POC — completion batch (verified items)

**Status:** ✅ FIXED — verified / cancelled items archived from the open completion tracker (last archive 2026-07-19).

**Started:** 2026-07-18

**Package:** `org.roojs.ollmchat.androidpoc`

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ [`docs/bugs/2026-07-18-android-poc-completion.md`](../2026-07-18-android-poc-completion.md) — open tracker (remaining work)
- ℹ️ [`docs/plans/done/9.0-DONE-android-poc-summary.md`](../../plans/done/9.0-DONE-android-poc-summary.md) — archived POC summary
- ℹ️ [`docs/bugs/done/2026-07-09-FIXED-android-poc-device-issues.md`](2026-07-09-FIXED-android-poc-device-issues.md) — history / TLS / default model

**Golden rule:** Android-only edits by default (`ollmapp/android/`, Android meson, `android/icons/`). Shared code needs explicit approval.

---

## Summary of what was fixed

| ID | Item | Outcome |
|----|------|---------|
| — | Chat history data retention | ✅ |
| — | Auto-expanding input (`Gtk.TextView` in `ScrolledWindow`) | ✅ |
| — | Send button green + play/triangle icon | ✅ |
| — | Remove tools selector from main viewport config | ✅ |
| **C5** | Flip/return reboot feel (`launchMode=singleTask`) | ✅ |
| **C2** | Markdown header emoji stream hang (ATX gate) | ✅ |
| **C3** | Bullet styling (blue markers + spacing) | ✅ |
| **C4** | Streaming table placeholder (pending + dots) | ✅ |
| **U4** | Code block title click toggles collapse | ✅ |
| **U1** | Input box styling redesign | 🚫 cancelled — already good enough |
| **U2** | Consolidate header (`OLLMchat` + agent) | ✅ |
| **U3** | Code-frame icons on Android (manifest) | ✅ |
| **U5** | Code block soft theme + Copy text link | ✅ |
| **U7** | Chat right margin (`margin-right: 10px`) | ✅ |
| **T2** | Long-press selection / scroll false-select | ✅ |
| **T3** | Autocomplete / IME double-filling | ✅ |
| **T4** | Keyboard delete with selection | ✅ |

**Still open** (see active tracker): C1, T1 (mild), U6, W1–W3, F1.

---

## Early UI (pre-C-series)

- ✅ Fix chat history — data retention working
- ✅ Auto-expanding input — `Gtk.TextView` sizing inside `Gtk.ScrolledWindow`
- ✅ Send button — green styling with play/triangle icon
- ✅ Remove tools selector from main viewport config

---

### C5 — Flip / return restarts app (activity stack)

**Status:** ✅ FIXED (2026-07-18) — user verified `singleTask` resumes instead of reboot-feel

**Expected:** 🔷 Leaving and returning (recents / home / brief flip) should **resume** the same UI state — frozen/paused, not a cold bootstrap.

**Actual (before fix):** 🔷 Flipping frequently went through the **whole reboot flow**, as if the app was killed.

**Evidence / root cause:**

- ✔️ Task had **`sz=3`** — stacked `ToplevelActivity` instances under `launchMode="standard"`
- ✔️ Launcher MAIN intents created a new activity → GTK full startup again (reboot feel) even when process survived
- ℹ️ True OEM process kills under memory pressure remain possible and are **not** this bug

**Fix:**

- ✅ `launchMode` `standard` → `singleTask` on `ToplevelActivity`
- ✅ Patched in `scripts/android/build-pixiewood-apk.sh` `patch_android_manifest` (survives pixiewood regenerate)
- ✅ Device: post-install task `sz=1`; user confirmed flip/return no longer reboots the UI

**Related:** C1 wake lock / FGS is separate — stack resume does not by itself keep SSE if Doze kills the socket.

---

### C2 — Markdown streaming (header icons / emoji)

**Status:** ✅ FIXED (2026-07-18) — desktop parser repro + narrow ATX gate fix; emoji-led headings parse as `<hN>`; user ruled done after tests

**Expected:** 🔷 Streaming continues smoothly when the model emits emoji or icons inside Markdown headers (`#`, `##`); those lines render as headings.

**Actual (before):** 🔷 Rendering hangs — parser/UI appears to block waiting for a text flush. After flush (end of stream), emoji-led ATX lines render as plain paragraphs with a literal `#` / `##` prefix, not as headings.

**Repro fixture:** ℹ️ `tests/markdown/repro-heading-emoji.md`

```bash
build/oc-markdown-test tests/markdown/repro-heading-emoji.md
build/examples/oc-test-gtkmd --stream 30 tests/markdown/repro-heading-emoji.md
```

**Evidence (2026-07-18):**

- ✔️ Full-file `oc-markdown-test` (before): `# 🚀 …` → `START: <p>` with literal `#`
- ✔️ After fix: emoji-led lines → `START: <h1>` / `<h2>` / `<h3>`
- ✔️ Gate in `libocmarkdown/BlockMap.vala`: ATX required `isalnum()`; mid-stream failure → `-1` leftover until flush
- ℹ️ Introduced in `404ab34f` (“Fix #8894”)

**Root cause:** ✔️ Emoji-led ATX failed `isalnum` → mid-stream `-1` hang; at flush → paragraph.

**Fix:** ✅ Narrow only — ATX gate also accepts first char `>= 0x80` (emoji). No shared helper.

**Emoji on bullets (smoke):** ✔️ `tests/markdown/repro-list-emoji.md` — not this hang class (see C3 for visual list issues).

---

### C3 — Markdown bullet points

**Status:** ✅ FIXED (2026-07-18) — user accepted blue markers + half-scale spacer + `"  "` after bullet

**Expected:** 🔷 Colored bullets and moderate vertical spacing between items.

**Actual (before):** 🔷 Black `●` / numbers, tight single-newline spacing.

**Fix:** ✅ Shared `libocmarkdowngtk/Render.vala` `on_li` only:

- Marker color `#3584E4` (unordered + ordered)
- Bullet→text: two spaces (was tab)
- Item gap: `\n` + half-scale `" \n"` spacer (`pixels_below_lines` did not show; full `\n\n` too heavy)
- Font face unchanged

---

### C4 — Streaming table placeholder (shared, not Android-only)

**Status:** ✅ FIXED (2026-07-18) — user verified placeholder + oscillating dots look good

**Expected:** 🔷 While a Markdown table is still streaming in, show “A table being created” with ellipsis oscillating on each chunk (1–10 dots, bounce).

**Actual (before):** 🔷 Nothing visible until BlockMap has 3 complete table lines and `on_table(true)` builds the grid.

**Root cause:** ✔️ `BlockMap` TABLE peek returns `-1` until 3 full lines; no renderer callbacks in that window.

**Fix:** ✅

- `RenderBase.on_table_pending(bool)` — default no-op
- `BlockMap` TABLE wait (`-1`) → `on_table_pending(true)`; reject/end → `false`
- `MarkdownGtk.Render`: `"A table being created "` + fixed-width 1–10 dot bounce (pad spaces, no GTK ellipsis); only when `is_streaming`; cleared on `on_table(true)` / `clear`
- Repro: `tests/markdown/repro-table-pending.md` with `oc-test-gtkmd --stream 0`

---

### U1 — Redesign input box styling

**Status:** 🚫 cancelled (2026-07-18) — user: already done what was wanted; no further work

- ~~🔷 White background, moderately rounded corners (not a full pill)~~
- ~~🔷 Remove default borders / text decorations so option controls stay text- or icon-based~~

---

### U4 — Code block collapse / expand

**Status:** ✅ FIXED (2026-07-18) — user: expand/collapse works well

**Expected:** 🔷 Click/tap on the code-block header title area toggles expand/collapse when the frame is collapsible. Copy (and other header action buttons) stay isolated.

**Fix (shared `libocmarkdowngtk/RenderSourceView.vala`):** ✅ Always connect title/spacer `GestureClick`; handler no-ops unless `collapse_toggle_button.visible`. Action `button_box` is not covered, so Copy does not fold.

---

### U2 — Consolidate header

**Status:** ✅ FIXED (2026-07-19) — user ruled done

**Fix:** ✅ Android-only `AndroidAgentDropdown` + `row_title()` virtual → `"OLLMchat " + title`. Desktop `AgentDropdown` unchanged.

---

### U3 — Code-frame icons missing on Android

**Status:** ✅ FIXED (2026-07-19) — user ruled done

**Fix:** ✅ Added to `android/icons/manifest`: `object-flip-horizontal-symbolic`, `x-office-document-symbolic`, `edit-copy-symbolic`, `go-next-symbolic`, `go-up-symbolic`, `pan-up-symbolic`.

---

### U5 — Redesign code blocks

**Status:** ✅ FIXED (2026-07-19) — user ruled done (soft theme + Copy as text link)

**Fix:** ✅ `frame.css` soft ~5%-over-white fills; no outer borders; unified header/body; flat theme-colored buttons; Copy as bare icon + text link.

---

### U7 — Chat right margin too tight

**Status:** ✅ FIXED (2026-07-19) — user ruled done

**Fix:** ✅ Shared viewport `margin-right: 10px` (matches left) so Android overlay scrollbar / desktop short-chat cases are not edge-hugging.

---

### T2 — Long-press selection / scroll false-select

**Status:** ✅ FIXED (2026-07-19) — user ruled done

**Expected:** 🔷 Scroll without selecting; long-press selects.

**Actual (before):** 🔷 Scroll often false-selected; sticky `in_long_press` across gestures.

**Fix:** ✅ long-press gate (`android-bugs.patch` v6→**v7**). Do not set `in_long_press` until iter resolve succeeds; clear flag on each new touch press.

**Device:** ✅ Knowles `org.gtk.entrypopuptest` — scroll-without-select ~90–95%; long-press selects. Rare residual false-select accepted as done.

---

### T3 — Autocomplete / IME double-filling

**Status:** ✅ FIXED (2026-07-19) — user ruled done

**Expected:** 🔷 Typing + autocomplete inserts once; leaving the field does not re-append.

**Actual (before):** 🔷 Autocomplete then focus elsewhere duplicated the whole string.

**Root cause:** ✔️ `ImContext.finishComposingText` committed the **entire** Android Editable; field already held committed text.

**Fix:** ✅ Commit only the composing span (or `updatePreedit(null)` if none). `setComposingText` updates preedit from the `text` argument only (`android-bugs.patch` v8).

---

### T4 — Keyboard delete with selection

**Status:** ✅ FIXED (2026-07-19) — user ruled done

**Expected:** 🔷 Backspace/delete with selection removes the selection; touch selection bubble disappears.

**Actual (before):** 🔷 Delete removed text before the selection; bubble could stay visible.

**Root cause:** ✔️ IME always `deleteSurrounding(-1,1)`; IME delete path skipped key-controller bubble unset.

**Fix:** ✅ `deleteBackwardOrSelection()` (v7); `gtk_text_delete_surrounding_cb` / TextView IM delete unset bubble + handles (v8).

---

## Changelog

| Date | Change |
|------|--------|
| 2026-07-18 | Opened from user Android POC completion list; C1 inherits deferred sleep/SSE from archived device-issues § Problem 3 |
| 2026-07-18 | C1 — keep-screen-on via `agent_status_change` + Android C/Java helper (desktop untouched) |
| 2026-07-18 | C4 — streaming table placeholder with oscillating dots (shared markdown UX) |
| 2026-07-18 | C1 — app-switch mid-stream: keep-screen-on will **not** help; same symptom, different trigger |
| 2026-07-18 | C1 — **reverted** keep-screen-on; switched to `PARTIAL_WAKE_LOCK` spike |
| 2026-07-18 | C1 device: brief flip sometimes keeps stream; **C5** opened — stacked `ToplevelActivity` + `launchMode=standard` likely “reboot” feel |
| 2026-07-18 | C5 — user approved `launchMode=singleTask`; build script patches manifest after pixiewood generate |
| 2026-07-18 | C5 — ✅ user verified fixed |
| 2026-07-18 | C2 — repro fixture `tests/markdown/repro-heading-emoji.md`; root cause: `BlockMap` ATX `isalnum` → mid-stream `-1` leftover until flush |
| 2026-07-18 | C2 — narrow fix: ATX gate also accepts first char `>= 0x80` (emoji); no general helper |
| 2026-07-18 | C2 adjacent — emoji on bullets OK (`repro-list-emoji.md`); not the ATX hang |
| 2026-07-18 | C2 — ✅ user ruled done after tests |
| 2026-07-18 | C3 — opened investigation: shared `Render.on_li` uses tabs + `●`, no `set_tabs`; likely styling vs Android metrics |
| 2026-07-18 | C3 — user mock: blue bullets + more line spacing; applied `#3584E4` + `\n\n` between items |
| 2026-07-18 | C3 — spacing dialed back: `\n` + `pixels_below_lines=6` (no font-face change) |
| 2026-07-18 | C3 — `pixels_below_lines` not visible; half-scale spacer line + `"  "` after bullet |
| 2026-07-18 | C3 — ✅ user accepted bullet styling |
| 2026-07-18 | C4 — root cause: BlockMap holds 3 table lines before any `on_table`; placeholder proposed |
| 2026-07-18 | C4 — implemented `on_table_pending` + streaming label with chunk-tied oscillating dots |
| 2026-07-18 | C4 — ✅ user verified fixed |
| 2026-07-18 | C1 — ✅ briefly marked fixed after wake-lock testing |
| 2026-07-18 | C1 — 🔷 **reopened**: network disconnect still happens; expand recommendation → **foreground service** while `session.is_running` |
| 2026-07-18 | C1 — ✔️ Java `StreamingForegroundService` (`dataSync`) + JNI + Vala hook + manifest/build install |
| 2026-07-18 | U1 — 🚫 cancelled (user: input styling already done) |
| 2026-07-18 | U2 — Android `AgentDropdown` override + `set_title_widget` (`ollmchat ` + agent) |
| 2026-07-18 | U2 — replaced full Android copy with `AndroidAgentDropdown` + `row_title()` virtual |
| 2026-07-18 | U4 — title/spacer click fires collapse toggle (shared RenderSourceView) |
| 2026-07-18 | U4 — ✅ user: expand/collapse works well |
| 2026-07-18 | U3 — view-source + related code-frame icons missing from `android/icons/manifest`; rows added |
| 2026-07-18 | U5 — soft 5%-over-white frame fills; no borders; unified header/body; flat theme-colored buttons |
| 2026-07-18 | U7 — tight right margin = no scrollbar gutter (desktop short chat + Android overlay); propose shared `margin-right: 10px` |
| 2026-07-18 | U7 — applied `margin-right: 10px`; user will check scrollbar interaction |
| 2026-07-19 | Archived verified C2–C5 / U1 / U4 (+ early UI) into this done log |
| 2026-07-19 | T2 / T3 / T4 — ✅ user ruled done; moved here. Active tracker slimmed to remaining open items only |
| 2026-07-19 | U2 / U3 / U5 / U7 — ✅ user ruled done; only U6 (global copy) left among U-series |
