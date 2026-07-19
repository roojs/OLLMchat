# Android IME ANR during chat render — composer freeze

**Status:** ✅ FIXED — user confirmed restore/session no longer hangs

**Started:** 2026-07-19  
**Reopened:** 2026-07-19 (app freeze alone was insufficient)

**Process:** `docs/bug-fix-process.md`

**Related:**

- ℹ️ `docs/bugs/2026-07-19-android-ime-autocomplete-nofill.md` — same `ImContext` / `blockForMain` bridge
- ℹ️ Patch tag: `ollmchat-android-bugs-v9`
- ℹ️ GTK fork: Knowles / `roojs/gtk` — ship via `android/pixiewood-wraps/gtk/android-bugs.patch`

---

## Problem

- **🔷** Heavy session restore ANR: *Input dispatching timed out*. App freeze delayed it; ANRs returned further into markdown load.

---

## Root cause

- **✔️** GTK thread called `imm.restartInput` synchronously while Android UI thread held `InputMethodManager$H` inside `finishComposingText` → `blockForMain`.

## Fix

- **✅** `setActiveImContext`: `runOnUiThread(() -> imm.restartInput(this))`
- **✅** `ImContext.reset`: `view.post(() -> imm.restartInput(view))`
- **✅** Kept app-level composer freeze
- **✅** `android-bugs.patch` + marker **v9**
