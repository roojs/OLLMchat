# Android — source view usability

**Status:** ⏳ open — scroll and search bar still need design. Problem 3 (font) is in the tree, not confirmed on a device.

**Package:** `org.roojs.ollmchat.androidpoc`

**Related:**

- **ℹ️** Editor and search bar: `liboccoder/SourceView.vala`.
- **ℹ️** Window header (right end): `ollmapp/android/OllmchatWindow.vala`. About is `ollmapp/About.vala`.
- **ℹ️** Monospace CSS: `resources/style.css` (`.source-view`).

---

## Problem 1 — Cannot scroll the editor

- **🔷** Dragging on the open file should scroll the text.
- **🔷** 2026-09-28, phone: a drag is taken by the text view and moves the cursor to the touch point. The file does not scroll.
- **🔷** This is expected to be an upstream touch handling fix. Record it here. Do not patch it in this tree as the first response.

### Evidence

- **ℹ️** The editor is a `GtkSource.View` inside `this.scrolled_window` (`SourceView` constructor). `editable` and `cursor_visible` are true once a file is open.
- **⏳** Which GTK or GtkSourceView release owns the gesture is not identified yet.

---

## Problem 2 — Search bar stays visible

- **🔷** With a file open, the search bar (entry, result label, previous, next) stays on screen the whole time.
- **🔷** That bar should not occupy the phone while search is unused.

### Direction

- **🔷** Working idea, not a locked layout: take the window’s top-right button and use it as the source-view menu. That button’s current action is expected to be replaced.
- **ℹ️** Rightmost header control is About (`help-about-symbolic`), packed after Settings in `OllmchatWindow`.
- **ℹ️** The bar is shown for every opened file: `open_file` sets `this.search_bar.visible = true`. It is hidden only when no file is selected.
- **⏳** What the menu contains, and whether the bar hides until that menu opens search, is not decided.

---

## Problem 3 — Editor font is not fixed-width ✔️

- **🔷** Source text on the phone is not a monospace font.
- **🔷** The tablet is expected to show the same face.

### Evidence

- **ℹ️** `SourceView` adds CSS class `source-view`. `resources/style.css` asked for `font-family: monospace`.
- **ℹ️** Android fontconfig (`60-latin.conf`) prefers `Noto Sans Mono`, then DejaVu, Inconsolata, Andale, Courier, Nimbus. None of those files are on the tablet or the emulator.
- **✔️** Tablet SM-X406B and emulator `sdk_gphone16k` both have `/system/fonts/DroidSansMono.ttf`. The name table is `Droid Sans Mono`. They also have `CutiveMono.ttf`. They do not have Noto Sans Mono.
- **ℹ️** The phone SM-S9380 was not attached. It is the same Samsung system-font set as the tablet.

### Root cause

- **✔️** `font-family: monospace` asks for a family none of the preferred faces provide on Android. Matching then uses the proportional UI font. Desktop still has Noto Sans Mono, so the same rule looks fixed there.

### Fix

- **✔️** `.source-view` requests `Droid Sans Mono`, then `monospace`. Android uses the face that is installed. Desktop skips the missing name and keeps `monospace`.
- **ℹ️** Chat code and tool output still request the generic name `monospace`. This change does not cover them.

#### Replace with

```css
.source-view {
  font-family: "Droid Sans Mono", monospace;
}
```
