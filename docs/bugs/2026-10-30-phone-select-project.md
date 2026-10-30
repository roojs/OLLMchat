# Phone Select project does nothing

**Status:** ⏳ pane show is dropped at startup — the tap itself left no app log

ℹ️ Same button as [`2026-10-28-FIXED-phone-project-click-does-nothing.md`](done/2026-10-28-FIXED-phone-project-click-does-nothing.md). That fix parented `SelectorPull` on the phone coder. [`2026-10-29-phone-selector-chrome.md`](2026-10-29-phone-selector-chrome.md) took that overlay back off `CoderView` and parents it only from `AgentManager.on_editor`.

## Problem

- 🔷 Phone SM-S9380, wireless debugging, `org.roojs.ollmchat.androidpoc` pid 13575, launch 2026-10-30 10:24:57. APK installed 10:18 the same morning, versionName 0.2.0.
- 🔷 Expected: Agent Pi is up, and pressing **Select project** opens the project list.
- 🔷 Actual: pressing **Select project** does nothing.
- 🔷 `android tablet: smallestScreenWidthDp=384`. The tablet cutoff is 600, so this window is the phone form.

## Evidence — session

- ℹ️ `adb -s adb-R5CY134DA0W-LrNhQc._adb-tls-connect._tcp logcat -d --pid=13575`
- ✔️ 10:25:07 `agent-pi list state=OLL_MCHAT_SETTINGS_FILESD_CLIENT_STATE_LIVE show=true`. Desktop hello succeeded. Agent Pi is the bound row.
- ✔️ 10:25:07.271 `id=2 method=ProjectManager.rpc_load_projects_from_db`, replied 10:25:08.507. That is the load from `AgentPi.Factory.activate`. No later `rpc_load_projects_from_db` and no `rpc_activate_project` through 10:35, when the screen was locked.
- ✔️ 10:25:07.241 and 10:25:07.280 `Child name 'pane' not found in GtkStack`. Both are before 10:25:07.293 `OllmchatWindow: initialize_client agents=3`. That message is the line after `view_stack.add_named(pane_stack, "pane")`.
- ✔️ 10:25:07.260 `invalid cast from 'GtkTextBuffer' to 'GtkSourceBuffer'`, then `signal 'cursor-moved' is invalid` for that `GtkTextBuffer`, then `g_signal_connect_data` on a NULL instance. Same trio as the 08:54 log on 2026-10-28, in the same instant `CoderView` is constructed.
- ✔️ 10:25:08.523 a `Gdk` popup, 204×179 at (90, 19) on a 384×750 window, hidden at 10:25:08.532. The 2026-10-28 log identified that size and place as the agent `Gtk.DropDown`, not the project pull-over. A project pull-over is a `Gtk.Box` on the chat overlay, not a small popup under the header.
- ✔️ InputDispatcher delivered taps to pid 13575 from 10:25:08.693 through 10:25:54. Those taps produced no `chat.androidpoc` line, no `Gtk` warning, and no `Gdk` popup. Settings opened at 10:25:35 (`/v1/models`, then `saved config`). The phone was on the lock screen by 10:40, so there is no picture of the failure.
- ℹ️ The **Select project** handler does not log. A tap that only sets `selector.visible` would look the same as a tap that missed the button.

## Evidence — the pane is requested before it exists

- ✔️ `initialize_client` switches to a new Agent Pi session, then builds the phone stack, then adds the pane. `ollmapp/android/OllmchatWindow.vala`.

```vala
			if (is_desktop_connected && is_desktop_available) {
				var empty = this.history_manager.create_new_session();
				empty.project_path = this.history_manager.session.project_path;
				empty.agent_name = "agent-pi";
				yield this.chat_widget.switch_to_session(empty);
				// ...
			}
			// ...
			} else {
				this.chat_widget.view_stack.add_named(this.pane_stack, "pane");
				this.chat_container.append(this.chat_widget);
			}
```

- ✔️ That `switch_to_session` emits `agent_activated` when the agent name changes. `libollmchat/History/Manager.vala`. `AgentManager.on_agent_activated` then calls `schedule_pane_update(true)`, which sets `view_stack.visible_child_name` to `"pane"`. The child is not in the stack yet. Gtk warns and leaves the visible child on `"chat"`.
- ✔️ `connect_agent_factory_signals` starts `Factory.activate` on that same signal. That constructs `CoderView` (the buffer-cast errors) and loads projects. A second `schedule_pane_update(true)` lands in that window, still before `add_named`. That is the second warning.
- ✔️ After `add_named`, `activate_session_and_sync_ui` switches to the session that is already Agent Pi. `agent_activated` fires only when the name changes, so this pass does not show the pane. Nothing in this launch logs a later `"pane"` warning, and a successful show would be silent.

## Evidence — the pull-over is not on the coder anymore

- ✔️ The button label is `Select project`. `liboccoder/ProjectSelector.vala`.
- ✔️ Phone and tablet `button.clicked` sets `selector.kind`, the project page, and `selector.visible = true`, then returns. It does not show `this.list`. That list is the desktop sheet.
- ✔️ The phone branch of `CoderView` appends the header and the editor and does not overlay `this.selector`. `liboccoder/CoderView.vala`.
- ✔️ `AgentManager.on_editor` is the phone path that calls `chat_widget.cover.add_overlay(coder.selector)`. It runs from the text-editor button, after `activate`. `on_agent_activated` shows the pane and does not parent the pull-over.
- ✔️ A `Gtk.Widget` with no parent is not mapped. `visible = true` on that pull-over changes nothing on screen and sends no RPC. That is the 2026-10-28 root cause, and it is reachable again when the pane is shown from `on_agent_activated` rather than `on_editor`.

## Root cause

- ✔️ Startup asks for the phone pane twice, both times before `"pane"` is a child of the chat stack. Those calls do not show the editor.
- 💩 If the header the user pressed was shown by a later `schedule_pane_update` that did not go through `on_editor`, the pull-over still has no parent, and **Select project** sets `visible` on a widget that is not in the window. That matches the taps: delivered, and no project RPC.
- 💩 If the header was shown by the text-editor button, `on_editor` does parent the pull-over, and this log cannot see whether that click ran. The handler has no `GLib.debug`.
- 🚫 The `GtkTextBuffer` / `cursor-moved` cast is the same construction failure left out of the 2026-10-28 fix. It does not open or hide the project list.
- 🚫 The 10:25:08 popup is the agent dropdown. It is not the project list.

## Proposed fix

- 💩 Add the `"pane"` child before the Agent Pi session switch, so the startup `schedule_pane_update(true)` hits a child that exists.
- 💩 Parent the phone `SelectorPull` when the coder is created, not only inside `on_editor`. The chrome change still wants that overlay on `chat_widget.cover` so it covers the composer. The parent has to exist before **Select project** can show it.
- 🚫 Do not add a click guard or a second list. The desktop sheet is the wrong surface for this form.

## Attempts / changelog

- ℹ️ 2026-10-30: logcat for pid 13575 after the 10:18 install. No code change.

## Next

- ⏳ One `GLib.debug` on the phone `button.clicked` path: parent is null or not, and `selector.visible` after the set. Rebuild, tap **Select project** once, and read that line. That separates "handler did not run" from "visible on an unparented pull-over".
