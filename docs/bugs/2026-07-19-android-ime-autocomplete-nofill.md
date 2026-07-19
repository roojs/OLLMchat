# Android IME autocomplete tap often fills nothing

> Pointer: `docs/bug-fix-process.md`. Legend: `docs/guide-to-writing-plans.md`.

**Status:** ⏳ OPEN — phone evidence; hypothesis from T3 fix flip-side

**Started:** 2026-07-19

**Related:**

- ℹ️ `docs/bugs/done/2026-07-18-FIXED-android-poc-completion-batch.md` **T3** — fixed double-fill by committing only composing span
- ℹ️ `docs/bugs/2026-07-19-android-ime-anr-composer-freeze.md` — `finishComposingText` ↔ `blockForMain` ANRs
- ℹ️ `subprojects/gtk/.../ImContext.java` — `finishComposingText` / `commitText`

---

## Problem

- **🔷** Tap keyboard autocomplete / suggestion: frequently **nothing** is inserted into the composer.
- **🔷** User keeps typing believing it filled; later it “randomly” works again.
- **🔷** Occurs on Android POC (Gboard).

---

## Evidence (phone)

- **✔️** Installed APK has T3 `ImContext` (`finishComposingText` only commits composing span; else `updatePreedit(null)` then `syncEditableFromGtk`).
- **✔️** Bugreport ANRs (13:45, 13:52, 14:10): Android `main` stuck in `ImContext.finishComposingText` → `GlibContext.blockForMain` while GTK thread waits on IME lock — same bridge that autocomplete uses.
- **ℹ️** Dumpstate: Gboard `onStartInput` for `org.roojs.ollmchat.androidpoc` with `autoCorrect` / learning on.
- **🚫** No app-level `scrolledview` / IME commit debug on device (Android POC does not wire `ApplicationInterface.debug_log`; `debug_on` only via `--touch-debug`).

---

## Root cause (hypothesis)

- **💩** T3 stopped committing the **whole** Editable (correct vs double-fill). When Gboard accepts a suggestion by mutating the Editable and calling `finishComposingText` **without** an active composing span, `toCommit` is empty → GTK gets only preedit clear → `syncEditableFromGtk` restores GTK surrounding and **wipes** the suggestion that never reached GTK.
- **💩** When Gboard uses `commitText` instead, fill works — explains intermittent success.
- **💩** When main is busy / ANR path, `blockForMain` stalls `finishComposingText` — tap appears to do nothing.

---

## Proposed next

- **⏳** Add temporary `android.util.Log` (or `GLib.message`) in `finishComposingText` / `commitText`: composing start/end, `toCommit` length, commit vs clear-preedit.
- **⏳** Reproduce: tap suggestion → confirm empty composing + sync wipe.
- **💩** Fix direction (after confirm): if composing empty but Editable differs from GTK surrounding, commit the delta (or full Editable replace once) without reintroducing T3 double-fill on focus-leave.

---

## Next

- **⏳** 🔷 Capture one failing tap with IME bridge logs.
- **⏳** 💩 Propose verbatim `ImContext.java` Replace after confirm.
