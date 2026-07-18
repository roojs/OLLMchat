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

---

## Critical bugs

### C1 — Sleep / network disconnect (critical blocker)

**Status:** ⏳ 🔷 partial wake lock installed — user testing

**Expected:** 🔷 Long replies keep the SSE pipe alive across screen-off and brief backgrounding when flipping apps.

**Actual:** 🔷

- 🔷 Screen idle timeout / lock while streaming → network drops → SSE dies → “Network error”
- 🔷 Same class of symptom when flipping to another app mid-stream

**Design:**

- 🔷 **Android only** — desktop does not need this
- 🔷 Reuse `History.Manager.agent_status_change` → acquire/release `PowerManager.PARTIAL_WAKE_LOCK` while `session.is_running`
- 🔷 App Java `PartialWakeLock` + C JNI (`gdk_android_toplevel_get_activity`) + `WAKE_LOCK` in AndroidManifest (install-time permission)
- 🚫 **Reverted** `FLAG_KEEP_SCREEN_ON` — only stops display timeout while our window is focused; does **not** help app switch / true background

**Device feedback (2026-07-18):**

- 🔷 Brief flip in/out **sometimes** lets the stream continue — wake lock may be helping for short backgrounding
- 🔷 Separately, flip often looks like a full **app reboot** (see **C5**) — that masks C1 results and is not the same bug

**Caveats:**

- ℹ️ OEM/Doze may still kill sockets; wake lock is a spike, not a guarantee
- ℹ️ Foreground service remains heavier / Play-policy if wake lock is insufficient

**Next:** ⏳ 🔷 Keep testing C1 only on short flips where the process/activity clearly stays alive; treat full “reboot UI” as **C5**

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

**Status:** ⏳ 🔷 open — ✔️ narrow fix applied; awaiting device verify

**Expected:** 🔷 Streaming continues smoothly when the model emits emoji or icons inside Markdown headers (`#`, `##`); those lines render as headings.

**Actual (before):** 🔷 Rendering hangs — parser/UI appears to block waiting for a text flush. After flush (end of stream), emoji-led ATX lines render as plain paragraphs with a literal `#` / `##` prefix, not as headings.

**Repro fixture:** ℹ️ `tests/markdown/repro-heading-emoji.md`

```bash
build/oc-markdown-test tests/markdown/repro-heading-emoji.md
build/examples/oc-test-gtkmd --stream 30 tests/markdown/repro-heading-emoji.md
```

**Evidence (2026-07-18):**

- ✔️ Full-file `oc-markdown-test`: `# 🚀 …`, `## ✅ …`, `## ⚠️ …`, `### 🔧 …` → `START: <p>` with `TEXT: "#"` / `"##"` then emoji text — **not** `<hN>`
- ✔️ Control `## Plain header (control)` → `START: <h2>` (works)
- ✔️ Control `## Header with trailing 🚀 emoji` → heading (first char after `#` is alphanumeric)
- ✔️ Gate in `libocmarkdown/BlockMap.vala` (~209–220): ATX match requires `heading_stripped.get_char(0).isalnum()`; on failure:
  - `is_end_of_chunks` → `return 0` (not a heading → paragraph)
  - else → `return -1` → `handle_block_result` stashes `leftover_chunk` and **stops processing** until flush
- ℹ️ Introduced in `404ab34f` (“Fix #8894”) with comment “require … starting with alphanumeric”

**Root cause:** ✔️ Mid-stream, an emoji-led ATX line (`# 🚀…`) matches `#`/`##` then fails `isalnum`, so `peek` returns **-1** forever (more chunks never make 🚀 alphanumeric). Parser holds the rest of the reply in `leftover_chunk` until end-of-stream flush — matches “waiting for a text flush”. At flush, same line is rejected as heading (`return 0`) and shown as a paragraph.

**Proposed / applied fix:** 🔷 Narrow only — in this ATX gate, treat non-ASCII (`>= 0x80`, covers emoji) like alphanumeric. No shared `is_emoji` helper, no other call sites.

#### Remove
```vala
			// ATX heading: require non-empty stripped content starting with alphanumeric; include leading space in byte_length
			if (matched_block >= FormatType.HEADING_1 && matched_block <= FormatType.HEADING_6) {
				var rest_start = chunk_pos + byte_length;
				var rest_len = (line_end != -1) ? line_end - rest_start : (int)chunk.length - rest_start;
				var rest = rest_len > 0 ? chunk.substring(rest_start, rest_len) : "";
				var heading_stripped = rest.strip();
				if (heading_stripped.length == 0 || !heading_stripped.get_char(0).isalnum()) {
```

#### Replace with
```vala
			// ATX heading: non-empty content starting with alphanumeric or non-ASCII (emoji); include leading space in byte_length
			if (matched_block >= FormatType.HEADING_1 && matched_block <= FormatType.HEADING_6) {
				var rest_start = chunk_pos + byte_length;
				var rest_len = (line_end != -1) ? line_end - rest_start : (int)chunk.length - rest_start;
				var rest = rest_len > 0 ? chunk.substring(rest_start, rest_len) : "";
				var heading_stripped = rest.strip();
				if (heading_stripped.length == 0 || !(heading_stripped.get_char(0).isalnum() || heading_stripped.get_char(0) >= 0x80)) {
```

**Next:** ⏳ 🔷 Rebuild / re-run `oc-markdown-test` on repro; user verify on device stream

**Emoji on bullets (smoke, 2026-07-18):** ✔️ `tests/markdown/repro-list-emoji.md` — unordered, nested, and ordered items starting with 🚀/✅/⚠️/🔧/📦/🔹 all emit proper `<li>` (no `isalnum` gate on list content; marker is `- `/`* `/`1. ` only). Not the C2 hang class. C3 (alignment/spacing) remains separate.

---

### C3 — Markdown bullet points

**Status:** ⏳ 🔷 open

**Expected:** 🔷 List items render with correct alignment, spacing, and structure.

**Actual:** 🔷 Broken list items in rendering (alignment / spacing / structural parse).

**Next:** ⏳ 🔷 Capture a failing session JSON or screenshot; narrow parser vs CSS vs widget

---

### C4 — Streaming table placeholder (shared, not Android-only)

**Status:** ⏳ 🔷 open

**Expected:** 🔷 While a Markdown table is still streaming in, show a visible placeholder such as “a table being created …” with an animated ellipsis that oscillates as chunks arrive:

- 🔷 Dot count cycles: `…` → `..` → `.` → `..` → `…` (3 → 2 → 1 → 2 → 3), hovering back and forth
- 🔷 Advance the animation on incoming stream data (not only a wall-clock timer), so progress feels tied to tokens

**Actual:** 🔷 During table stream, nothing useful is visible until the table is complete / flushed.

**ℹ️** Shared markdown/chat rendering path — desktop benefits too; listed here because it hurts POC readability during long replies.

**Next:** ⏳ 🔷 Find where incomplete table nodes are held back in the stream renderer; propose placeholder widget + dot cycle

---

## Android touch & input

### T1 — Input text area expansion flakiness

**Status:** ⏳ 🔷 open

**Expected:** 🔷 Composer natural height expands reliably to fit wrapped content on mobile.

**Actual:** 🔷 Height calculation is flaky — sometimes fails to expand for wrapped lines.

**ℹ️** Related prior work: composer / `ScrolledView` height bugs under `docs/bugs/done/` (2026-07-16).

**Next:** ⏳ 🔷 Reproduce steps + whether desktop shares the glitch

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

**Status:** ⏳ 🔷 open

- 🔷 White background, moderately rounded corners (not a full pill)
- 🔷 Remove default borders / text decorations so option controls stay text- or icon-based

### U2 — Consolidate header

**Status:** ⏳ 🔷 open

- 🔷 Combine app name and agent selector into one title string (e.g. `"ollmchat chatter v"`)

### U3 — Fix icon loading

**Status:** ⏳ 🔷 open

- 🔷 Audit assets; fix pathing / Pango icon mapping for missing interface icons

### U4 — Code block collapse / expand

**Status:** ⏳ 🔷 open

- 🔷 Click/tap anywhere on the code-block header/title toggles expand/collapse
- 🔷 Copy action stays isolated — copy must not fold/unfold

### U5 — Redesign code blocks

**Status:** ⏳ 🔷 open

- 🔷 Soft light backgrounds; no distinct outer borders
- 🔷 Copy: bare icon + `"Copy"` text link (soft color), no button chrome

### U6 — Global copy button

**Status:** ⏳ 🔷 open

- 🔷 Append a “Copy output” control at the end of completed chat cycles

---

## Suggested order

1. ⏳ 🔷 **C1** sleep / network (critical blocker) — **C5** ✅ fixed (`singleTask`)
2. ⏳ 🔷 **C2** / **C3** / **C4** markdown stream, lists, streaming tables (blocks readable chat)
3. ⏳ 🔷 **T1**–**T4** touch / input (mobile usability)
4. ⏳ 🔷 **U1**–**U6** styling polish
5. ⏳ 🔷 **W1**–**W3** / **F1** search + media (feature track; may need shared-code approval)

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
