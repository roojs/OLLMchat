# Android phone — chrome, settings rows, session_fetch crash

**Status:** ⏳ open — phone SM-S9380, wireless debugging

**Package:** `org.roojs.ollmchat.androidpoc` (APK `lastUpdateTime=2026-09-27 12:48:42`)

**Related:**

- **ℹ️** Browser page load: [`done/2026-09-27-FIXED-android-browser-page-never-loads.md`](done/2026-09-27-FIXED-android-browser-page-never-loads.md) ✅. Layout issues are later.

**🚫** Phone layout polish beyond the items below.

---

## Problem 1 — Bottom pickers do not show which page is on

- **🔷** Phone chat mode. The chat picker should look depressed.
- **🔷** Browser and chat both look like ordinary buttons. Pressed and not pressed are almost the same.
- **🔷** The browser mark is a black blob.
- **🔷** The chat mark is a square with a plus. Neither mark reads as browser or chat.
- **🔷** Expected: the visible page’s button is clearly down, and each button’s picture is the thing it opens.

### Evidence

- **ℹ️** `ollmapp/android/OllmchatWindow.vala` builds both as `Gtk.Button`. Browser icon is `web-browser-symbolic`. Idle chat icon is `chat-message-new-symbolic`.
- **ℹ️** The on state is CSS class `picker-on`: `background-color: alpha(@window_fg_color, 0.15)` in `resources/style.css`.
- **ℹ️** `chat-message-new-symbolic` is the Adwaita “new message” glyph (bubble plus a plus badge). Plan [`RPC-8.2.8.11`](../plans/done/RPC-8.2.8.11-DONE-android-startup-history-bars.md) already noted that plus badge.
- **ℹ️** Both names are in `android/icons/manifest`.

### Root cause

- **⏳** Why the browser glyph paints solid black on the phone is not confirmed.
- **✔️** The selected wash is a 15% foreground tint on a normal button, which matches “hard to tell pressed from not.”

### Fix

- **✔️** Phone pickers use CSS `page-picker` (no frame) and `picker-on` is an inset wash.
- **✔️** Browser mark is a bundled symbolic globe (`fill="#2e3436"`, so the theme recolors it). The Adwaita legacy file is hardcoded `#474747` and stayed black.
- **✔️** Idle chat mark is bundled `chat-message-symbolic` (speech bubble, no plus).

### Next

- **⏳** **🔷** Confirm on the phone: chat looks pressed in chat mode, browser is a globe, chat is a bubble.

---

## Problem 2 — Connections add buttons

- **🔷** Bottom of Connections. Replace the word Add with a plus icon.
- **🔷** `Add LLM connection` becomes a plus, then `LLM connection`.
- **🔷** `Add remote desktop environment` becomes a plus, then `remote desktop environment`.
- **🔷** Ellipsize those labels on a narrow phone, especially the remote-desktop one.

### Evidence

- **ℹ️** `ollmapp/SettingsDialog/ConnectionsPage.vala` labels:
  - `Gtk.Button.with_label("Add LLM connection")` (`suggested-action`)
  - `Gtk.Button.with_label("Add remote desktop environment")`
- **ℹ️** `list-add-symbolic` is already in `android/icons/manifest`.

### Fix

- **✔️** Both buttons use `list-add-symbolic` plus the shorter label. Labels ellipsize at the end.

---

## Problem 3 — Settings expanders open only sometimes

- **🔷** Connections row `LLM: …` (the default LLM row). Taps sometimes expand, usually do nothing. One sequence took six taps before it collapsed. Further taps then did nothing for a while, then it opened again.
- **🔷** Same intermittent expand and collapse on Tools rows.
- **🔷** Same on Models rows.
- **🔷** Expected: one tap on the row header opens it. One tap closes it.

### Evidence

- **ℹ️** Connections rows are `Adw.ExpanderRow` (`ConnectionRow`, `FileConnectionRow`, `FileServerRow`). `ConnectionsPage.arrow()` unparents `expander-row-arrow` and readds it as a prefix (`pan-end-symbolic` / `pan-down-symbolic`).
- **ℹ️** Tools rows (`Rows/ToolRow.vala`) and model rows (`ModelRow.vala`) are also `Adw.ExpanderRow`. They do not go through `arrow()`.
- **✔️** Phone log 2026-09-27 19:22, settings open: `AdwExpanderRow placed into GtkBox, can only be placed into GtkListBox`. Connections, Tools, and Models all append expanders to a `Gtk.Box`.
- **ℹ️** Expansion is the inner `Gtk.ListBox` `row-activated` on the header (`adw-expander-row.ui`), not the outer row. A `Gtk.Box` parent does not remove that header list.
- **💩** A shared Android tap on that header list. `gtk_list_box_click_gesture_stopped` clears the press, so a scroll claim on a slightly moving finger never activates the row.

### Next

- **⏳** **💩** One log on expander header activation (page, row title, expanded before and after) and a tap series on the phone.

---

## Problem 4 — Phone crash in `session_fetch`

- **🔷** Critical: the phone app crashes.
- **✔️** Crash buffer on SM-S9380, 2026-09-27 13:05:23 +0800. Process uptime 1002s. `SIGSEGV` `SEGV_MAPERR` fault addr `0x0` on `GTK Thread`. Cause: null pointer dereference in `strlen`.
- **✔️** Symbolized against the unstripped libraries (BuildID match):
  - `libollmchat-android-poc.so` `51b7934d…` — `oll_mtools_session_fetch_request_real_execute_request_co` at `ollmapp/android/tools/SessionFetch/Request.vala:50`
  - caller `oll_mchat_tool_request_base_execute_request` → `execute_tools` → `toolsReply`
- **ℹ️** Line 50 is `if (preview.length > 100)` after `msg.content.split("\n")[0]`. `.length` is `strlen`. A null `preview` faults there.
- **ℹ️** Only fatal for this package on 2026-09-27. The 2026-09-23 crash in `file_connection_row_check` is older. Current process (pid 10174, started ~18:56) has not faulted.
- **💩** Some session message has a null `content` when `session_fetch` runs with reference `index`. Which message is not in the log.

### Next

- **⏳** **💩** Log role and whether `content` is null for each message inside that index loop, then reproduce one `session_fetch`. No null guard that skips the message.
