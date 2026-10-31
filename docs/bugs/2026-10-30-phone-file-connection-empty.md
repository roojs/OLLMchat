# Phone editor shows FileConnectionAdd.vala empty

**Status:** ⏳ fix is on the phone (pid 25075, installed 08:52). Editor not checked. Pairing data was wiped with the reinstall.

The open file is `examples/oc-test-source-diff/FileConnectionAdd.vala`. The phone has it open. The read returned the text. The editor on screen stayed empty.

## Problem

- 🔷 On the phone, open `examples/oc-test-source-diff/FileConnectionAdd.vala` from the OLLMchat project. The editor is empty.
- 🔷 Expected: the file text is on screen. The file on disk is the `FileConnectionAdd` class, about 248 lines.

## Evidence

- ✔️ 16:18:53 pid 22048, tag `chat.androidpoc`: `SourceView.vala:532` `file read path=/home/alan/gitlive/OLLMchat/examples/oc-test-source-diff/FileConnectionAdd.vala loaded=true chars=7294`.
- ✔️ The next lines, same second: `gtk_source_buffer_set_language` failed `GTK_SOURCE_IS_BUFFER`, then `gtk_text_buffer_get_tag_table` failed `GTK_IS_TEXT_BUFFER` twice, then `gtk_text_buffer_set_text` failed `GTK_IS_TEXT_BUFFER`, then `gtk_text_buffer_set_modified` failed `GTK_IS_TEXT_BUFFER`.
- ✔️ Those calls are `open_file` setting `language` on `(this.source_view.buffer as GtkSource.Buffer)`, then `ChangeView.apply` (`tag_table.lookup` twice, then `set_text`), then `show_pending_diff` calling `set_modified` on the same cast.
- ✔️ 16:11:15 the same pid logged `invalid cast from 'GtkTextBuffer' to 'GtkSourceBuffer'`.
- ✔️ `file.buffer as GtkSource.Buffer` is the object whose `.text.length` printed 7294. That buffer has the file. The view never got it.
- 🚫 The missing note `docs/bugs/2026-10-30-phone-open-file-crash.md` is a different open. 16:10:22 `File.read` returned `ENOENT` and `chars=0`. The note now lives under `docs/bugs/done/`. That is not the empty `FileConnectionAdd.vala`.
- 🚫 The filesd connection is live (`tcp://192.168.88.132:8422`, state 3). This is not an empty connection.

## Root cause

- ✔️ `ChangeView` is built once with `this.source_view.buffer as GtkSource.Buffer`. On this phone that cast is null: the view's buffer is a plain `GtkTextBuffer`, and the `as` result is what `apply` writes to. `apply` then calls `tag_table` and `set_text` on null, so the 7294 characters stay on `file.buffer`. The widget keeps the empty text buffer.
- ✔️ `open_file` never calls `set_buffer`. It only casts the view buffer again for `language` and `set_modified`. Both casts hit the same empty result, which is the two source-buffer and text-buffer assertions around the read.
- ℹ️ `libocmarkdowngtk/RenderSourceView.vala` already does the other pattern: `new GtkSource.Buffer(null)`, then `source_view.set_buffer`.

## Proposed fix

- 🔷 After the `GtkSource.View` is created, put a real `GtkSource.Buffer` on it and give that same object to `ChangeView`. `apply` then writes the file text onto the buffer the view is showing.
- 🚫 Do not add a method. Do not point the view at `file.buffer`. The file buffer stays the loaded text. `apply` copies it across, including the diff tags.

### `liboccoder/SourceView.vala` — `SourceView` constructor

**Why:** `new GtkSource.View()` left a `GtkTextBuffer` in `buffer`. The cast into `ChangeView` stored null, and the open path wrote the file into that null.

**Where:** In place of `new ChangeView(this.source_view.buffer as GtkSource.Buffer)`.

#### Replace

```vala
				this.change_view = new ChangeView(this.source_view.buffer as GtkSource.Buffer);
```

#### With

```vala
				var editor_buffer = new GtkSource.Buffer(null);
				this.source_view.set_buffer(editor_buffer);
				this.change_view = new ChangeView(editor_buffer);
```

## Attempts / changelog

- ℹ️ 2026-10-30 16:15 — first note treated the empty screen as the missing crash-note path. Wrong file.
- ℹ️ 2026-10-30 16:30 — phone log for pid 22048 at 16:18:53. `FileConnectionAdd.vala` loaded 7294 characters, then the view buffer rejected `set_language`, `set_text`, and `set_modified`. No product change.
- ✔️ 2026-10-31 — applied the constructor fence in `liboccoder/SourceView.vala`. The view gets a `GtkSource.Buffer`, and that same object is passed to `ChangeView`.
- ✔️ 2026-10-31 08:34 — `PIXIEWOOD_PHASE=build scripts/android/build-chat-poc-apk.sh` wrote `app-arm64-v8a-debug.apk`. Cert SHA-256 `26304203…` (`~/.android/debug.keystore`).
- ℹ️ 08:34 — wireless adb was already `device` at `192.168.0.12:45747` (`adb-R5CY134DA0W`). The first `adb install` stalled. Reconnect, then `install -r` failed `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Phone package from 2026-10-30 16:05 is cert `967ef8e8…`. That keystore is not on disk.
- ✔️ 08:52 — uninstalled `org.roojs.ollmchat.androidpoc` and installed the new APK. Launched `ToplevelActivity`, pid 25075, `lastUpdateTime=2026-10-31 08:52:00`. On-device pairing data went with the old package.

## Next

- 💩 ⏳ Pair the phone to the desktop again, then open `examples/oc-test-source-diff/FileConnectionAdd.vala`. The editor shows the `FileConnectionAdd` class.
