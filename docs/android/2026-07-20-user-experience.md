# Android user experience — GTK / chat POC

**Date:** 2026-07-20 · Package: `org.roojs.ollmchat.androidpoc`

Candidates for GTK Android / GLib discussion, plus a few app-wrapper workarounds. Open items stay even if not yet patched. Packaging-only setup (TLS modules, CA wiring) is out of scope here.

**Markers:** ✅ fixed in GTK patch / upstream path · ⏳ open · ⚠️ app workaround only (GTK/GLib still wrong)

---

## Summary

- **Input (soft keyboard / IME)** — GTK Android IME bridge
  - **IME-1** ✅ — Hold backspace: deletes one character, then stops (no continuous delete).
  - **IME-2** ✅ — Accepting a Gboard suggestion (or leaving the field) sometimes duplicated the whole line.
  - **IME-3** ⏳ — Typo (e.g. `TAT`) → tap Gboard suggestion (`THAT`) → typed word is **not deleted/replaced**; correction does not land. Flip-side of **IME-2**; still open for chat POC.
  - **IME-4** ✅ — With text selected, backspace deleted the character before the selection and left the handles on screen.
- **Copy / paste / selection** — GTK Android touch
  - **CP-1** ✅ — Copy/paste bubble should appear when you lift your finger after a long-press (or after drag-select); magnifier only while holding on existing text.
  - **CP-2** ✅ — Dragging a finger to scroll inside a text area started a text selection instead; long-press could stick into the next gesture.
- **Process / background**
  - **BG-1** ⏳ — Keep network (streaming reply) alive in the background when the screen locks or the user briefly leaves.
  - **BG-2** ⚠️ — Home / Recents → return felt like a full reboot. App uses `launchMode=singleTask`; want native GTK Android resume instead of per-app manifest hacks.
- **Freeze / rendering**
  - **FRZ-1** ✅ — Opening a large / markdown-heavy past chat froze the UI or showed “app isn’t responding” while it rendered (IME↔main deadlock during load).
- **Touch buttons** *(proximity / grab — GTK Android)*
  - **TOUCH-1** ⚠️ — Tapping near a dropdown/popover (trigger or just outside the popup) often does nothing; only a far tap dismisses. Hard to re-click the dropdown button. Layout nudge only; grab still wrong.
  - **TOUCH-2** ⏳ — With the text area focused, tapping the blue send button (when it sits close under the field) clears focus but never fires the click. Not diagnosed yet; likely the same proximity / grab class as **TOUCH-1**.
- **GLib on Android**
  - **GLIB-1** ⚠️ — `query_exists` / mkdir “File exists” is unreliable on Android external storage. Broke session history save/load and config saves (e.g. remembered model) until we switched to `FileUtils.test` EXISTS-tolerant paths. One GLib/GIO issue, many call sites.

---

## IME-1 — Hold-backspace stops after one character ✅

- **What you see:** Hold backspace down — one character deletes, then delete stops.
- **Fix (brief):** Real Android input type; DEL → `deleteSurrounding`.
- **Regression test:** Type in a text area → hold backspace → keeps deleting.

## IME-2 / IME-3 — Spell-correct / autocomplete (same bridge)

**IME-2 and IME-3 are related.** IME-2 fixed double-fill by committing only the composing span. IME-3 is the flip-side: Gboard’s spelling suggestion must **replace** the typed word, and that rewrite still fails on the GTK Android IME bridge.

- **IME-2** ✅ — Suggestion or leave-field duplicated the whole line.
  - **Fix (brief):** Commit composing span only (not the whole Editable).
  - **Regression test:** Accept suggestion → tap elsewhere → no duplicate.
- **IME-3** ⏳ — Spell-correct / suggestion tap does not replace the typed word.
  - **Repro:** Type `tat` → tap Gboard’s `rat` → field stays `tat` (or only updates later).
  - **Root cause (✔️ log):** Gboard calls `InputConnection.replaceText`; we only update the Android Editable, not GTK.
  - **Need:** Apply `replaceText` into GTK (then sync Editable). Keep **IME-2** (no double-fill on leave).
  - **Regression test:** `tat` → tap `rat` → field shows `rat` immediately; leave field → no double line.

## IME-4 — Backspace with a selection ✅

- **What you see:** Selected word + backspace deletes before the selection; handles stay.
- **Fix (brief):** Delete the selection when one exists; clear selection bubble / handles on IME delete.
- **Regression test:** Select word → backspace → selection + bubble gone.

## CP-1 — Copy / paste bubble on finger release ✅

- **What you see:** Long-press in a text area and lift — copy/paste bubble missing or wrong; magnifier wrong.
- **Desired:** Magnifier only while holding on existing text; bubble on **release** (blank long-press or after drag-select).
- **Fix (brief):** Bubble on release / drag-end; sync popup parent bounds.
- **Regression test:** Blank long-press→release = bubble; drag-select→release = bubble; hold on text = magnifier.

## CP-2 — Finger-scroll in a text area starts a selection ✅

- **What you see:** Text area has more text than fits. Drag to scroll → selection starts instead. Next touch may still act like long-press.
- **Fix (brief):** Set long-press only after touch resolves to a text position; clear on each new press.
- **Regression test:** Drag-scroll → no select; long-press → select; no sticky select after CP-1.

## FRZ-1 — Freeze while a large chat renders ✅

- **What you see:** Open a long past session; UI freezes or “isn’t responding” while markdown builds.
- **Fix (brief):** Post `imm.restartInput` to the UI thread (never call it synchronously from the GTK thread while the UI thread is inside `finishComposingText` → `blockForMain`).
- **Regression test:** Open heavy session → tap during load → no ANR; typing works after (recheck IME-2 / IME-3).

## BG-1 — Background network while streaming ⏳

- **What you see:** Mid-reply, screen locks or brief leave → TCP/SSE dies → “Network error”.
- **Need:** Keep network I/O alive in the background for an in-flight stream.
- **Applied (our app):** Foreground service (`dataSync`) while a reply is running; device verify pending.
- **Regression test:** Long stream → screen off / Home → stream continues (or clear interrupt UX).

## BG-2 — Home / return reboot feel ⚠️

- **What you see:** Leave via Home/Recents and return → full GTK startup instead of resume.
- **App workaround:** `launchMode=singleTask` on the toplevel activity. Home reuse is app-specific.
- **GTK proposal:** Native single-toplevel resume so apps need not invent launchMode / activity-stack rules.
- **Regression test:** Home → return → same UI; single activity in the task.

## TOUCH-1 — Dropdown / popover near-tap ⚠️

- **What you see:** With any dropdown or popover open, taps in a band near the popup or on the trigger often do nothing; only a clearly far tap dismisses. Hard to re-click the dropdown button itself.
- **Not a product fix:** Layout nudge so the bad band is less likely to hit. GTK Android popup grab / `input_region` still wrong — raise with GTK group.
- **Regression test:** Open a dropdown → far tap closes; near-edge / trigger still usable (workaround only).

## TOUCH-2 — Send (or nearby) button eats focus, no click ⏳

- **What you see:** Type in the text area. Tap the blue send button at the bottom when it sits close under the field → keyboard/focus drops, but send never runs (no click).
- **Status:** Not diagnosed. Suspected same proximity / grab class as **TOUCH-1**.
- **Next:** Confirm whether the press hits a popup/surface grab region vs widget; compare with send farther from the field.
- **Regression test (when understood):** Text area focused → tap send → message sends.

## GLIB-1 — `query_exists` unreliable on Android ⚠️

- **What you see:** Force-stop / cold start lost chat history and/or forgot the selected model — saves aborted with mkdir “File exists” after a false-negative existence check.
- **GLib issue:** On Android external storage, `GFile.query_exists` (and mkdir treating any error as fatal) is unreliable. One GIO behaviour, many call sites.
- **App workaround:** Prefer `g_file_test` / `FileUtils.test(…, EXISTS)` and do not abort on mkdir EXISTS.
- **Regression test:** Multi-turn + change model → force-stop → history and model both survive.

---

## Quick pass

- **IME-1** hold-backspace keeps deleting
- **IME-2** suggestion + leave (no double)
- **IME-3** `TAT` → tap `THAT` replaces typed word
- **IME-4** delete selection
- **CP-1** long-press → release → bubble
- **CP-2** drag-scroll text area without selecting
- **FRZ-1** heavy session load (no ANR)
- **BG-2** Home → return
- **BG-1** mid-stream background / screen-off
- **TOUCH-1** dropdown near-tap / trigger
- **TOUCH-2** send near text area (focus lost, no click)
- **GLIB-1** history + model survive force-stop
