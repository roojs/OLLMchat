# CLOSED — Android IME spell-correct / autocomplete (IME-3) — out of scope

**Status:** 🚫 CLOSED / passed over (2026-07-24) — fix lives in Knowles GTK / IME bridge, not OLLMchat

**Started:** 2026-07-19  
**UX code:** **IME-3** in [`docs/android/2026-07-20-user-experience.md`](../android/2026-07-20-user-experience.md)

**Related:**

- ℹ️ Knowles GTK: `/home/alan/git/gtk-Knowles` · Demo: `org.gtk.EntryPopupTest`
- ℹ️ Tracker pointer was: [`2026-07-18-android-poc-completion.md`](../2026-07-18-android-poc-completion.md) **IME-3** (updated to passed over)
- ℹ️ Prior OPEN log (evidence retained below)

---

## Why closed here

🔷 **Out of scope for OLLMchat.** Spell-correct / autocomplete `replaceText` → GTK is owned by the Knowles GTK IME work. Do not land a primary fix in this repo; port from GTK when that lands if still needed.

---

## Problem (archived)

- **🔷** Type a wrong word (e.g. **`tat`**) → Gboard suggests **`rat`** / **`that`** → tap suggestion → GTK field does **not** replace the typed word.

## Root cause (archived)

- **✔️** Gboard uses **`replaceText(start, end, text, …)`**. `ImContext.ImeConnection.replaceText` only updated the Android **Editable**; GTK surrounding stayed wrong until a later sync.

## Proposed fix (for Knowles GTK — not this repo)

🔷 On `replaceText`: apply range replace to GTK, then `syncEditableFromGtk`. Keep IME-2 leave-field behaviour.

---

## Changelog

| Date | Change |
|------|--------|
| 2026-07-19 … 21 | Opened; device log; root cause ✔️; Knowles sketch |
| 2026-07-24 | 🚫 Passed over — track in GTK Knowles, not OLLMchat |
