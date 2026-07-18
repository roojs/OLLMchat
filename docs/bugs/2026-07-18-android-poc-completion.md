# Android chat POC — completion backlog

**Status:** ⏳ OPEN — tracker for remaining Android POC work after plan 9.0 archive.

**Started:** 2026-07-18

**Package:** `org.roojs.ollmchat.androidpoc`

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ [`docs/plans/done/9.0-DONE-android-poc-summary.md`](../plans/done/9.0-DONE-android-poc-summary.md) — archived POC summary
- ℹ️ [`docs/bugs/done/2026-07-09-FIXED-android-poc-device-issues.md`](done/2026-07-09-FIXED-android-poc-device-issues.md) — history / TLS / default model; § Problem 3 (sleep vs stream) deferred into this log
- ℹ️ Build: `scripts/android/build-chat-poc-apk.sh` → `scripts/android/adb-install-chat-poc.sh`

**Golden rule:** Android-only edits by default (`ollmapp/android/`, Android meson, `android/icons/`). Shared code needs explicit approval.

---

## Completed (archived into this tracker)

- ✅ Fix chat history — data retention working
- ✅ Auto-expanding input — `Gtk.TextView` sizing inside `Gtk.ScrolledWindow`
- ✅ Send button — green styling with play/triangle icon
- ✅ Remove tools selector from main viewport config
- ✅ **C5** flip/return reboot feel — `launchMode=singleTask` (2026-07-18)
- ✅ **C1** sleep / network mid-stream — `PARTIAL_WAKE_LOCK` (2026-07-18)
- ✅ **C2** markdown header emoji stream hang — ATX gate allows non-ASCII (2026-07-18)
- ✅ **C3** bullet styling — blue markers + half-scale spacer gap (2026-07-18)
- ✅ **C4** streaming table placeholder — pending label + 1–10 dots (2026-07-18)
- ✅ **U4** code block title click toggles collapse (2026-07-18)

---

## Critical bugs

### C1 — Sleep / network disconnect (critical blocker)

**Status:** ✅ FIXED (2026-07-18) — user: restore / mid-stream flip working; no further C1 failures observed

**Expected:** 🔷 Long replies keep the SSE pipe alive across screen-off and brief backgrounding when flipping apps.

**Actual (before):** 🔷 Screen idle / lock or app flip mid-stream → network drops → SSE dies → “Network error”.

**Fix:** ✅ Android `PARTIAL_WAKE_LOCK` via `agent_status_change` while `session.is_running` (Java `PartialWakeLock` + C JNI + `WAKE_LOCK` permission). Keep-screen-on was tried and reverted (does not help background). **C5** `singleTask` was a separate stack bug that had masked C1 testing.

**Caveats (unchanged):** ℹ️ OEM/Doze may still kill sockets under pressure; wake lock is a spike, not a guarantee. Foreground service remains a heavier fallback if needed later.

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

**Related:** C1 wake lock is separate — stack resume does not by itself keep SSE if Doze kills the socket.

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

## Android touch & input

### T1 — Input text area expansion flakiness

**Status:** ⏳ 🔷 open — see dedicated log (desktop + Android)

**Expected:** 🔷 Composer natural height expands reliably to fit wrapped / multiline content.

**Actual:** 🔷 Height calculation is flaky — sometimes fails to expand (e.g. after **+** fill from a prior chat).

**ℹ️** Dedicated investigation: [`done/2026-07-18-FIXED-composer-plus-no-resize.md`](done/2026-07-18-FIXED-composer-plus-no-resize.md) — peer only when measured height ≤ peer; refit on allocate width change. ✅

**ℹ️** Related prior work: composer / `ScrolledView` height bugs under `docs/bugs/done/` (2026-07-16).

**Next:** ⏳ 🔷 Approve/apply proposed `ScrolledView` fix in that log; verify **+** multiline fill on desktop (and Android)

---

### T2 — Chat view selection during scroll

**Status:** ⏳ 🔷 open

**Expected:** 🔷 Drag-scroll does not start text selection; selection only after a strict long-press threshold.

**Actual:** 🔷 Selection routines fire during active drag-scroll in the main text container.

**Next:** ⏳ 🔷 Identify gesture / GtkSourceView or TextView selection path on Android

---

### T3 — Voice input double-filling

**Status:** ⏳ 🔷 open

**Expected:** 🔷 Speech-to-text inserts the spoken text once.

**Actual:** 🔷 Intermittent double-fill / duplicated strings in the input.

**Next:** ⏳ 🔷 Reproduce with IME / Android speech; check insert vs commit handlers

---

### T4 — Keyboard delete with selection

**Status:** ⏳ 🔷 open

**Expected:** 🔷 Backspace/delete with an active selection removes the selection.

**Actual:** 🔷 Delete removes text before the selection instead of the highlighted range.

**Next:** ⏳ 🔷 Trace key handler / IME delete on Android TextView

---

## Core backend & feature integration

### W1 — Migrate existing WebKit search code

**Status:** ⏳ 🔷 open

- 🔷 Port the functional WebKit / webview search wrapper and DOM extraction utility from the other project into this repo.

### W2 — Integrate as tool replacement / alternative

**Status:** ⏳ 🔷 open

- 🔷 Refactor tool execution so the migrated WebKit process is the primary web-search method (replacing API-key search).

### W3 — Verify prompt context flow

**Status:** ⏳ 🔷 open

- 🔷 Search results format as Markdown context and prepend into the LLM system/user prompt pipeline before streaming.

### F1 — Media upload

**Status:** ⏳ 🔷 open

- 🔷 File / attachment pipeline on the input component.

---

## Frontend & UI styling

### U1 — Redesign input box styling

**Status:** 🚫 cancelled (2026-07-18) — user: already done what was wanted; no further work

- ~~🔷 White background, moderately rounded corners (not a full pill)~~
- ~~🔷 Remove default borders / text decorations so option controls stay text- or icon-based~~

### U2 — Consolidate header

**Status:** ⏳ 🔷 open — ✔️ Android-only override applied; awaiting device verify

**Expected:** 🔷 One title string combining app name + agent (e.g. `"OLLMchat Chatter"`), not a separate window title plus bare agent name.

**Fix (Android only):**

- ✅ Shared `AgentDropdown.row_title()` virtual; Android `AndroidAgentDropdown` overrides to `"OLLMchat " + title`
- ✅ `OllmchatWindow` uses `set_title_widget(new AndroidAgentDropdown(…))`
- 🚫 Desktop still uses `AgentDropdown` unchanged in behaviour

**Next:** ⏳ 🔷 User confirm header shows e.g. `OLLMchat Chatter` as the title control

### U3 — Fix icon loading

**Status:** ⏳ 🔷 open — ✔️ view-source (+ related code-frame) icons added to manifest; rebuild APK to verify

**Expected:** 🔷 Code-frame header icons (view source, copy, collapse chevrons, pan) render on Android.

**Actual:** 🔷 View-source control shows no / broken icon — asset not shipped in the APK icon theme subset.

**Root cause:** ✔️ `RenderSourceView` uses `object-flip-horizontal-symbolic` / `x-office-document-symbolic` (and related frame icons). Those names were missing from `android/icons/manifest`, so Pixiewood never staged them under `assets/share/icons/Adwaita/`.

**Fix:** ✔️ Added manifest rows (from host Adwaita):

- `object-flip-horizontal-symbolic`, `x-office-document-symbolic` (view source / rendered)
- also missing from same frame: `edit-copy-symbolic`, `go-next-symbolic`, `go-up-symbolic`, `pan-up-symbolic`

**Next:** ⏳ 🔷 Rebuild/install APK; confirm view-source icon appears on a ` ```markdown ` block

### U4 — Code block collapse / expand

**Status:** ✅ FIXED (2026-07-18) — user: expand/collapse works well

**Expected:** 🔷 Click/tap on the code-block header title area toggles expand/collapse when the frame is collapsible. Copy (and other header action buttons) stay isolated.

**Fix (shared `libocmarkdowngtk/RenderSourceView.vala`):** ✅ Always connect title/spacer `GestureClick`; handler no-ops unless `collapse_toggle_button.visible`. Action `button_box` is not covered, so Copy does not fold.

### U5 — Redesign code blocks

**Status:** ⏳ 🔷 open — ✔️ soft theme CSS applied in `resources/frame.css`; verify on device / desktop

**Expected:** 🔷 Soft ~5%-over-white fills per theme; no outer borders; header + body + SourceView same fill; flat header buttons (no hover recolor) using theme foreground.

**Palette (Background Hex / Foreground Text Hex):** Primary `#f3f8ff`/`#052c65`, Secondary `#f8f8f9`/`#2b2f32`, Success `#f4f9f6`/`#0a3622`, Danger `#fdf5f6`/`#58151c`, Warning `#fffcf3`/`#664d03`, Info `#f3fcfe`/`#055160`, Light `#fefeff`/`#495057`, Dark `#f4f4f4`/`#495057`.

**Fix:** ✔️ `frame.css` — drop border/shadow; theme classes set only `--frame-bg` + `--frame-text-emphasis`; body text/SourceView/nested markdown inherit fill; buttons stay on `--frame-bg` for hover/active/focus.

**Still open (original U5):** ⏳ 🔷 Copy as bare icon + `"Copy"` text link (no button chrome) — not in this CSS pass

**Next:** ⏳ 🔷 Visual check themed frames (primary/success/info/danger/thinking)

### U6 — Global copy button

**Status:** ⏳ 🔷 open

- 🔷 Append a “Copy output” control at the end of completed chat cycles

### U7 — Chat right margin too tight (no scrollbar gutter)

**Status:** ⏳ 🔷 applied — `margin-right: 10px`; verify with/without scrollbar

**Expected:** 🔷 Chat body / frames have comfortable side margins (~10px) on **both** sides whether or not a vertical scrollbar is visible.

**Actual:** 🔷

- 🔷 **Right-hand** margin is too tight (content hugs the edge)
- 🔷 **Desktop:** usually masked because a classic vertical scrollbar reserves gutter space and “rejigs” the layout; **without** a scrollbar, the same tight right edge appears
- 🔷 **Android:** overlay / hidden scrollbar layout does **not** reserve that gutter, so the tight right edge shows all the time

**Evidence / layout:**

- ℹ️ Shared CSS (`resources/style.css`) — was `margin-right: 5px`, left `10px`
- ℹ️ `ChatView` content box: `margin_start = 2`, `margin_end = 0` (`libollmchatgtk/ChatView.vala`)
- ✔️ User (2026-07-18): desktop repro when chat does **not** need a vertical scrollbar; Android always feels like that case

**Fix applied:**

- ✔️ Shared: viewport `margin-right: 10px` (matches left)
- 🔷 User: may look off once classic scrollbar appears (double gutter); possible follow-up is footer/overlay scrollbar — try this first

**Next:** ⏳ 🔷 Restart app; check short chat (no bar) and long chat (with bar) on desktop + Android

---

## Suggested order

1. ✅ **C1** sleep / network — FIXED (`PARTIAL_WAKE_LOCK`)
2. ✅ **C2** markdown header emoji stream — FIXED
3. ✅ **C3** bullet styling — FIXED
4. ✅ **C4** streaming table placeholder — FIXED
5. ✅ **C5** flip/return reboot feel — FIXED (`singleTask`)
6. ⏳ 🔷 **U7** chat right margin when no scrollbar gutter
7. ⏳ 🔷 **T1**–**T4** touch / input (mobile usability)
8. 🚫 **U1** input styling — cancelled (done enough)
9. ⏳ 🔷 **U2** consolidate header — Android override applied; verify on device
10. ⏳ 🔷 **U3** icon loading — manifest rows added; verify after APK rebuild
11. ⏳ 🔷 **U5**–**U6** styling polish
12. ⏳ 🔷 **W1**–**W3** / **F1** search + media (feature track; may need shared-code approval)

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
| 2026-07-18 | C1 — ✅ user: working fine / no further failures observed |
| 2026-07-18 | U1 — 🚫 cancelled (user: input styling already done) |
| 2026-07-18 | U2 — Android `AgentDropdown` override + `set_title_widget` (`ollmchat ` + agent) |
| 2026-07-18 | U2 — replaced full Android copy with `AndroidAgentDropdown` + `row_title()` virtual |
| 2026-07-18 | U4 — title/spacer click fires collapse toggle (shared RenderSourceView) |
| 2026-07-18 | U4 — ✅ user: expand/collapse works well |
| 2026-07-18 | U3 — view-source + related code-frame icons missing from `android/icons/manifest`; rows added |
| 2026-07-18 | U5 — soft 5%-over-white frame fills; no borders; unified header/body; flat theme-colored buttons |
| 2026-07-18 | U7 — tight right margin = no scrollbar gutter (desktop short chat + Android overlay); propose shared `margin-right: 10px` |
| 2026-07-18 | U7 — applied `margin-right: 10px`; user will check scrollbar interaction |
