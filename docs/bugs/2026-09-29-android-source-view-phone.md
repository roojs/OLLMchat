# Android — source view on the phone

**Status:** ⏳ open — problems 1, 2, and 5 are in the tree. Not confirmed on a device. Problems 3 and 4 are still open.

**Package:** `org.roojs.ollmchat.androidpoc`

**Related:**

- **ℹ️** Earlier scroll, search bar, and font: [`2026-09-28-android-source-view-usability.md`](2026-09-28-android-source-view-usability.md).
- **ℹ️** Editor: `liboccoder/SourceView.vala`. Desktop `open_file` shows the search bar. Android leaves it hidden.
- **ℹ️** Phone bottom bar: `ollmapp/android/OllmchatWindow.vala` (`chat_picker`, `browser_picker`, `editor_picker`).
- **ℹ️** Language id on a buffer: `liboccoder/BufferProvider.vala`.

---

## Problem 1 — Pinch zoom does not change the font

- **🔷** Pinch on the open file should change the source font size.
- **🔷** 2026-09-29, phone: it does not.

### Evidence

- **ℹ️** `.source-view` in `resources/style.css` sets the family only (`Droid Sans Mono`, then `monospace`). It does not set a size.

### Fix

- **✔️** Two-finger pinch and Ctrl+mouse wheel both change `.source-view` font size, clamped to 8–64 px, starting at 14 px. Wheel up grows the font by 2 px per step.
- **ℹ️** The same path runs on the phone and on the desktop.

### Next

- **⏳** **🔷** Confirm on the phone: pinch changes the source font size.

---

## Problem 2 — Hide the search bar for now

- **🔷** With a file open, the search bar stays on screen.
- **🔷** Hide it. Search is not useful enough on the phone to keep the bar.
- **🔷** Bring search back later. Do not design the replacement in this pass.

### Evidence

- **ℹ️** `open_file` sets `this.search_bar.visible = true` on desktop. The bar is hidden when no file is selected.
- **ℹ️** The 2026-09-28 note’s menu idea (window About button opens search) is not the current direction.

### Fix

- **✔️** On Android, `open_file` leaves the bar hidden. Desktop still shows it.

### Next

- **⏳** **🔷** Confirm on the phone: an open file has no search bar.

---

## Problem 3 — Viewing and editing are the same mode

- **🔷** Pan on the file works reasonably well.
- **🔷** It still loses to editing often enough that panning is not a reliable way to read a file.
- **🔷** Long-press to turn editing on was considered. The chosen control is a bottom-bar toggle, not a long-press.
- **🔷** Viewer is the same source view with editing off, so the keyboard does not keep opening.
- **🔷** Editor is that view with editing on.

### Evidence

- **ℹ️** After a file loads, `open_file` sets `this.source_view.editable = true`.
- **ℹ️** Scroll vs cursor is problem 1 in the 2026-09-28 note. This problem is the mode split, not a new scroll patch.

---

## Problem 4 — Bottom bar needs four buttons

- **🔷** Phone bar today shows Chat and Browser. Edit mode is missing.
- **🔷** The editor button does not work.
- **🔷** The bar should be four buttons: Chat, Browser, Editor, Viewer.
- **🔷** Viewer opens the source view with editing disabled.
- **🔷** Editor opens the same view with editing enabled.

### Evidence

- **ℹ️** The bar appends `browser_picker`, `editor_picker`, then `chat_picker` (`chat_picker` is phone-only).
- **ℹ️** `editor_picker` uses `document-edit-symbolic` and tooltip `Text editor`. It is shown only when the active agent `has_editor`.
- **ℹ️** Its click sets the pane to `{agent_name}-widget` and calls `schedule_pane_update(true)`.
- **⏳** Why the phone shows two buttons, and why the editor control does nothing, is not logged on a device.

---

## Problem 5 — Vala highlighting does not run

- **🔷** A Vala file open in the phone source view is not syntax-coloured.
- **💩** The language data files may not be on the device.

### Evidence

- **ℹ️** `BufferProvider.detect_language` asks `GtkSource.LanguageManager.get_default().guess_language` for the file name. `create_buffer` then calls `get_language` with that id.
- **✔️** `libgtksourceview-5.so` in the Pixiewood tree already contains the `.lang` files, including Vala, as gresources.
- **✔️** Parsing a spec still calls `xmlTextReaderRelaxNGValidate` on `language2.rng`. That call needs a filesystem path. `resource://` does not pass `g_file_test`.
- **✔️** The Android library’s `DATADIR` is `/share`. That path is not on the phone. The first place the manager looks is `XDG_DATA_HOME/gtksourceview-5/language-specs`, which is the extracted `assets/share/` tree.
- **✔️** The built APK listed no `language-specs` files. Style schemes already load from `resource://`, so they do not need a copy.

### Root cause

- **✔️** Without `language2.rng` on disk, every language spec fails validation. The buffer stays uncoloured. The `.lang` data itself is already in the library.

### Fix

- **✔️** The APK build copies `language2.rng`, `language.rng`, and `language.dtd` from the GtkSourceView 5.16.0 wrap into `assets/share/gtksourceview-5/language-specs/`. `verify-apk.sh` requires `language2.rng`.

### Next

- **⏳** **🔷** Rebuild the APK and confirm a `.vala` file is coloured on the phone.
- **⏳** **🔷** Confirm pinch changes font size, and an open file has no search bar.
