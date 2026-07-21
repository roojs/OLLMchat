# Android IME spell-correct / autocomplete tap does not replace typed text (IME-3)

> Pointer: `docs/bug-fix-process.md`. Legend: `docs/guide-to-writing-plans.md`.

**Status:** ⏳ OPEN — root cause confirmed from device log; fix proposed (not applied)

**Started:** 2026-07-19  
**UX code:** **IME-3** in [`docs/android/2026-07-20-user-experience.md`](../android/2026-07-20-user-experience.md)

**Related:**

- ℹ️ Batch **T3** / **IME-2** — [`done/2026-07-18-FIXED-android-poc-completion-batch.md`](done/2026-07-18-FIXED-android-poc-completion-batch.md)
- ℹ️ Tracker: [`2026-07-18-android-poc-completion.md`](2026-07-18-android-poc-completion.md) **IME-3**
- ℹ️ Knowles GTK: `/home/alan/git/gtk-Knowles` · Demo: `org.gtk.EntryPopupTest`
- ℹ️ API: [`InputConnection.replaceText`](https://developer.android.com/reference/android/view/inputmethod/InputConnection#replaceText(int,%20int,%20java.lang.CharSequence,%20int,%20android.view.inputmethod.TextAttribute)) — suggestion range replace

---

## Problem

- **🔷** Type a wrong word (e.g. **`tat`**) → Gboard suggests **`rat`** / **`that`** → tap suggestion → GTK field does **not** replace the typed word (stays wrong until something else syncs).
- **🔷** Leave-field must still not double-fill (**IME-2**).
- **🔷** Chat POC needs the same IME bridge fix.

---

## Evidence (2026-07-21 EntryPopupTest + Gboard)

User typed toward `… tat`, tapped spell suggestion **`rat`**.

```
IME: beginBatchEdit editable="this is a tat" …
IME: replaceText(10, 13, "rat ", 1) before editable="this is a tat" …
IME: replaceText after editable="this is a rat " … ok=true
IME: endBatchEdit editable="this is a rat " …
```

~30s later (focus leave):

```
IME: finishComposingText editable="this is a rat " … gtk="this is a tat" …
  toCommit="this is a rat " replaceAll=true
IME: finishComposingText after replace gtk="this is a rat "
```

- **✔️** Gboard uses **`replaceText(start, end, text, …)`**, not `finishComposingText` / empty composing-span alone.
- **✔️** `super.replaceText` updates the Android **Editable** (`tat`→`rat `) but **GTK surrounding stays `… tat`** until a later `finishComposingText` replace-all.
- **✔️** What the user sees is the GTK widget → correction looks like it “can’t delete/replace” the typed word.

---

## Root cause

- **✔️** `ImContext.ImeConnection.replaceText` only forwards to `BaseInputConnection` (Editable). It never applies the range replace to GTK (`deleteSurrounding` / selection + `commit`).
- **🚫** Earlier Knowles `finishComposingText` Editable≠GTK path is a late sync, not the suggestion tap path. Not the right primary fix.

---

## Proposed fix

In Knowles `ImContext.replaceText` (then port to OLLMchat `android-bugs.patch`):

1. **🔷** On `replaceText(start, end, text, …)`: apply to GTK — move cursor/selection to `[start,end]` (or delete `end-start` chars before cursor if cursor is at `end`), `commit(text)`, then `syncEditableFromGtk`.
2. **🔷** Keep composing-span-only `finishComposingText` for **IME-2**; optional keep Editable≠GTK as safety net only.
3. **🔷** Regression: `tat` → tap `rat` → field shows `… rat ` immediately; leave field → no double line.

#### Sketch (Knowles `ImContext.java` `replaceText`)

```java
// After logging: push range replace into GTK, then sync Editable from GTK
GlibContext.blockForMain(() -> {
  SurroundingRetVal s = ImContext.this.getSurrounding();
  if (s == null || s.text == null) return;
  int from = Math.min(start, end);
  int to = Math.max(start, end);
  // delete [from,to) relative to cursor, then commit text
  // (same idea as InputConnection docs: finish compose + setSelection + commitText)
  …
  if (text != null && text.length() > 0)
    ImContext.this.commit(text.toString());
});
syncEditableFromGtk(getEditable());
return true; // do not rely on super alone for editor content
```

Exact delete/cursor math to match `BaseInputConnection.replaceText` before applying.

---

## Debug capture

```bash
adb logcat -c
adb logcat -s "IME Connection:I"
```

---

## Next

1. **⏳** 🔷 Approve / apply `replaceText` → GTK path on Knowles; retest `tat`→`rat`.
2. **⏳** 🔷 Port to OLLMchat `android-bugs.patch`; mark UX **IME-3** ✅ after device verify.

---

## Changelog

| Date | Change |
|------|--------|
| 2026-07-19 | Opened from phone / T3 flip-side hypothesis |
| 2026-07-20 | User confirmed typo → spell-correct → no fill |
| 2026-07-20 | Proposed Editable≠GTK on finishComposingText; applied on Knowles |
| 2026-07-21 | EntryPopupTest + Meson 1.11; user: typed word not replaced on suggestion |
| 2026-07-21 | Richer IME logging installed |
| 2026-07-21 | Log: Gboard `replaceText(10,13,"rat ")` updates Editable only; GTK stays `tat` until later finish — root cause **✔️** |
