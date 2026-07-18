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
- ✅ **C2** markdown header emoji stream hang — ATX gate allows non-ASCII (2026-07-18)

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

**Status:** ⏳ 🔷 open — ✔️ styling tweak applied (blue markers + blank line between items); awaiting visual verify

**Expected:** 🔷 List items with colored bullets and a bit more vertical spacing (user mock: blue `●`, airy gaps between items). Nesting structure already OK.

**Actual (before):** 🔷 Black `●` / numbers, tight single-newline spacing (`oc-test-gtkmd` nested-lists screenshot).

**Parser:** ✔️ Structure fine — not a parse bug.

**How lists are drawn:** ℹ️ Shared `libocmarkdowngtk/Render.vala` `on_li` — tabs + marker + tab + text. Same path desktop / Android.

**Applied fix (2026-07-18):** 🔷 Narrow in `on_li` only (same pattern as ordered bold state / link `foreground`):

#### Remove
```vala
			if (!is_start) {
				this.current_state.close_state(true);
				this.current_state.add_text("\n");
				return;
			}
			// ...
			if (list_number == 0) {
				this.current_state.add_text("●");
			} else {
				string number_marker = list_number.to_string() + ".";
				var bold_state = this.current_state.add_state();
				bold_state.style.weight = Pango.Weight.BOLD;
				bold_state.add_text(number_marker);
				bold_state.close_state();
			}
```

#### Replace with
```vala
			if (!is_start) {
				this.current_state.close_state(true);
				this.current_state.add_text("\n\n");
				return;
			}
			// ...
			if (list_number == 0) {
				var bullet_state = this.current_state.add_state();
				bullet_state.style.foreground = "#3584E4";
				bullet_state.add_text("●");
				bullet_state.close_state();
			} else {
				string number_marker = list_number.to_string() + ".";
				var bold_state = this.current_state.add_state();
				bold_state.style.weight = Pango.Weight.BOLD;
				bold_state.style.foreground = "#3584E4";
				bold_state.add_text(number_marker);
				bold_state.close_state();
			}
```

**Defaults picked:** `#3584E4`; bullet→text = two spaces (was a tab — too wide); vertical gap = `\n` + half-scale `" \n"` spacer (`pixels_below_lines` did not show on screen; full `\n\n` was too heavy). Font face unchanged.

**Next:** ⏳ 🔷 Rebuild `oc-test-gtkmd` nested-lists — confirm mid gap + tighter bullet gap

---### C4 — Streaming table placeholder (shared, not Android-only)

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

1. ✅ **C2** markdown header emoji stream — FIXED
2. ⏳ 🔷 **C1** sleep / network (critical blocker) — **C5** ✅ fixed (`singleTask`)
3. ⏳ 🔷 **C3** / **C4** markdown lists + streaming tables (blocks readable chat)
4. ⏳ 🔷 **T1**–**T4** touch / input (mobile usability)
5. ⏳ 🔷 **U1**–**U6** styling polish
6. ⏳ 🔷 **W1**–**W3** / **F1** search + media (feature track; may need shared-code approval)

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
