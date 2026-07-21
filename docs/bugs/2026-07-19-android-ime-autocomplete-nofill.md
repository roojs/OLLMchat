# Android IME spell-correct / autocomplete tap does not replace typed text (IME-3)

> Pointer: `docs/bug-fix-process.md`. Legend: `docs/guide-to-writing-plans.md`.

**Status:** ⏳ OPEN — device-verified on EntryPopupTest; still broken; must fix for chat POC

**Started:** 2026-07-19  
**UX code:** **IME-3** in [`docs/android/2026-07-20-user-experience.md`](../android/2026-07-20-user-experience.md)

**Related:**

- ℹ️ Batch **T3** / **IME-2** — [`done/2026-07-18-FIXED-android-poc-completion-batch.md`](done/2026-07-18-FIXED-android-poc-completion-batch.md)
- ℹ️ Tracker: [`2026-07-18-android-poc-completion.md`](2026-07-18-android-poc-completion.md) **IME-3**
- ℹ️ Knowles GTK branch: `android-ime-spellcorrect-nofill` @ `/home/alan/git/gtk-Knowles` (attempted replace path — **did not fix**)
- ℹ️ Demo: `org.gtk.EntryPopupTest`

---

## Problem

- **🔷** Type a short wrong word (e.g. **`TAT`**) → Gboard offers **`THAT`** → tap the suggestion → the typed characters are **not replaced**. Suggestion cannot clear/delete the existing prefix; field stays wrong (or correction never lands).
- **🔷** Same class of failure as “spell-correct fills nothing”: Gboard’s correction expects to rewrite the current word, but the GTK Android IME bridge does not apply that rewrite.
- **🔷** Leave-field must still not double-fill (**IME-2**).
- **🔷** Affects EntryPopupTest and the real chat POC composer — fix needed in the GTK IME path we ship.

---

## Device verify (2026-07-21)

- **✅** 🔷 EntryPopupTest rebuilt with Meson 1.11, launches.
- **✅** 🔷 User repro: type **`TAT`** → tap suggestion **`THAT`** → typed text is **not** deleted/replaced.
- **✔️** Knowles attempt (`finishComposingText`: if Editable ≠ GTK surrounding, replace GTK with Editable) is **on device and insufficient** — do not treat as fixed; do not port as-is until a working fix exists.

---

## Root cause (partial)

- **✔️** Related to **IME-2**: composing-span-only commit fixed double-fill but left spell-correct / suggestion rewrite weak.
- **💩** Earlier hypothesis: empty composing span + `syncEditableFromGtk` wipe. Replace-Editable path did not make **`TAT` → `THAT`** work on device — either the Editable never holds `THAT` at finish time, delete/replace of the typed span fails, or Gboard uses another API (e.g. `setComposingText` / `commitText` / `deleteSurroundingText` + commit) that we still mishandle.
- **⏳** 🔷 Next debug: logcat IME calls around the suggestion tap (`finishComposingText`, `commitText`, `setComposingText`, `deleteSurroundingText`, Editable vs GTK surrounding before/after).

---

## Attempted fix (Knowles — not verified fixed)

- **✔️** Applied on Knowles: composing span → commit span only (IME-2); else Editable ≠ surrounding → replace GTK; else clear preedit only.
- **🚫** Do not bump OLLMchat `android-bugs.patch` for this until device shows **`TAT` → `THAT`** works and IME-2 still holds.

---

## Debug capture (EntryPopupTest)

Knowles `ImContext` logs Editable / composing span / GTK surrounding / replace decisions on the `"IME Connection"` logger.

```bash
adb logcat -c
adb logcat -s "IME Connection:I"
# On phone: open EntryPopupTest → type TAT → tap Gboard THAT
# Ctrl-C when done; paste the sequence into this log under Evidence.
```

Also useful API docs (contract, not Gboard’s exact sequence):

- ℹ️ https://developer.android.com/reference/android/view/inputmethod/InputConnection
- ℹ️ https://developer.android.com/reference/android/view/inputmethod/BaseInputConnection

## Next

1. **⏳** 🔷 Capture IME call sequence on suggestion tap (commands above).
2. **⏳** 🔷 Propose a root-cause fix that actually replaces the typed word (not only “Editable ≠ GTK”).
3. **⏳** 🔷 After ✅ on EntryPopupTest: port into OLLMchat `android-bugs.patch` and mark UX **IME-3** ✅.

---

## Changelog

| Date | Change |
|------|--------|
| 2026-07-19 | Opened from phone / T3 flip-side hypothesis |
| 2026-07-20 | User confirmed typo → spell-correct → no fill |
| 2026-07-20 | Proposed Editable≠GTK replace path; applied on Knowles |
| 2026-07-21 | EntryPopupTest launches (Meson 1.11). User: type TAT → suggestion THAT → **cannot delete/replace typed text**. Attempted fix insufficient; clarify problem; keep open for chat POC |
| 2026-07-21 | Richer IME Connection logging installed on EntryPopupTest for device capture |
