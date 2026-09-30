# Android — source view on the phone

**Status:** ⏳ open — problems 1–5 are in the tree. Not confirmed on a device.

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
- **🔷** A document opens read-only. A tap must not bring up the keyboard.
- **🔷** A tap shows a toast under the source view: long hold to start editing.
- **🔷** A long hold starts editing: keyboard up, cursor at the hold.
- **🔷** A tap anywhere that is not the source view locks it again. Toast: view mode, long hold to edit.
- **🚫** A bottom-bar Viewer / Editor pair. That split is not the control.

### Evidence

- **ℹ️** After a file loads, `open_file` sets `this.source_view.editable = true`. The view is focusable, so a tap opens the Android keyboard.
- **ℹ️** Scroll vs cursor is problem 1 in the 2026-09-28 note. This problem is the mode split, not a new scroll patch.

### Fix

- **✔️** On Android a file stays non-editable, with focus off, until a long-press. Desktop still opens editable.
- **✔️** The long-press places the cursor and focuses the view so the keyboard can show.
- **✔️** A short tap toasts `Long hold to start editing` at the bottom of the source view.
- **✔️** A button release outside the source view (header, review bar, footer) returns to view mode and toasts `View mode. Long hold to edit.`

---

## Problem 4 — Bottom bar button sequence

- **🔷** Phone bar today shows Chat and Browser. The editor control is missing or does nothing.
- **🔷** Do not add a separate Viewer button. View vs edit is problem 3.
- **🔷** The three phone buttons stay the ones from [`RPC-8.2.8.11`](../plans/done/RPC-8.2.8.11-DONE-android-startup-history-bars.md) and [`RPC-8.2.8.12`](../plans/done/RPC-8.2.8.12-DONE-android-editor-chrome-bars.md): browser, text editor, chat, on the right of the bar.
- **🔷** A click activates that page. The editor click mounts Agent Pi’s source view.

### Evidence

- **ℹ️** The bar appends `browser_picker`, `editor_picker`, then `chat_picker`. That is the spec order.
- **ℹ️** `editor_picker` was shown only when the active agent `has_editor`, so Chatter hid it and the bar was Browser, Chat.
- **ℹ️** Its click set the pane to `{agent_name}-widget`. That child is absent until `Factory.activate` adds it, so the control did nothing.
- **ℹ️** The Android spec click is `agent_factories.get("agent-pi").activate()`.

### Fix

- **✔️** The editor button stays visible. Order on the right is browser, text editor, chat.
- **✔️** Its click calls Agent Pi `activate`, which adds the source view and shows that page.

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
- **⏳** **🔷** Open a file: no keyboard. A tap toasts “Long hold to start editing”. A long hold edits. A tap outside the file toasts “View mode. Long hold to edit.”
- **⏳** **🔷** Footer, left to right on the right: browser, text editor, chat. The editor button opens the source view.
