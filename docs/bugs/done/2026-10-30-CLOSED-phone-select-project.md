# Phone Select project does nothing

**Status:** 🚫 CLOSED 2026-10-30. Parked. §1–§2 are in the tree. The phone check (Select project covers the composer, then `rpc_activate_project`) was not run. The pull-over overlay is the open question this log leaves.

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
- ✔️ `connect_agent_factory_signals` starts `Factory.activate` on that same signal. That constructs `CoderView` (the buffer-cast errors) and yields on the project load. `Factory.activate` does not show the pane.
- ✔️ The second `"pane"` warning is the same `on_agent_activated` → `schedule_pane_update(true)`, from `session_restored` at the end of that `switch_to_session`. `switch_to_session` has not returned, so `add_named` has not run.
- ✔️ After `add_named`, `activate_session_and_sync_ui` switches to the session that is already Agent Pi. `agent_activated` fires only when the name changes, so this pass does not show the pane. Nothing in this launch logs a later `"pane"` warning, and a successful show would be silent.

## Evidence — the pull-over is not on the coder anymore

- ✔️ The button label is `Select project`. `liboccoder/ProjectSelector.vala`.
- ✔️ Phone and tablet `button.clicked` sets `selector.kind`, the project page, and `selector.visible = true`, then returns. It does not show `this.list`. That list is the desktop sheet.
- ✔️ The phone branch of `CoderView` appends the header and the editor and does not overlay `this.selector`. `liboccoder/CoderView.vala`.
- ✔️ `AgentManager.on_editor` is the phone path that calls `chat_widget.cover.add_overlay(coder.selector)`. It runs from the text-editor button, after `activate`. `on_agent_activated` shows the pane and does not parent the pull-over.
- ✔️ A `Gtk.Widget` with no parent is not mapped. `visible = true` on that pull-over changes nothing on screen and sends no RPC. That is the 2026-10-28 root cause, and it is reachable again when the pane is shown from `on_agent_activated` rather than `on_editor`.

## Root cause

- ✔️ Startup asks for the phone pane twice, both times before `"pane"` is a child of the chat stack. Gtk leaves the visible child on `"chat"`. `activate_session_and_sync_ui` switches to the session that is already Agent Pi, so `agent_activated` does not fire again and nothing shows the editor.
- ✔️ Both of those shows are `on_agent_activated`. That method does not parent `SelectorPull`. The only `cover.add_overlay(coder.selector)` is in `on_editor`, which runs from the text-editor button. After the pane child exists, startup shows the editor through `on_agent_activated`, and **Select project** sets `visible` on a pull-over that is not in the window.
- 💩 This log cannot tell which path the taps took. The handler does not log, and opening the list does not send an RPC. The two edits below cover both: the startup show, and the text-editor button.
- 🚫 The `GtkTextBuffer` / `cursor-moved` cast is the same construction failure left out of the 2026-10-28 fix. It does not open or hide the project list.
- 🚫 The 10:25:08 popup is the agent dropdown. It is not the project list.

## Proposed fix

- 💩 Put the phone `"pane"` child on the chat stack before the Agent Pi session switch, so both startup `schedule_pane_update(true)` calls hit a child that exists. Leave the tablet column where it is: that branch sets `pane_stack.visible = false` after the switch, and moving it would show the tablet pane at startup.
- 💩 Parent the phone `SelectorPull` on `chat_widget.cover` inside the two `activate.end` callbacks that already create the coder. Those lines are the same parent `on_editor` already has. The pull-over stays invisible until **Select project** or the file button sets `visible`.
- 🚫 Do not add a method. `on_editor` stays as it is. Do not add a click guard, a second list, or a `GLib.debug` on the button. The desktop sheet is the wrong surface. The handler's silence is not the defect.

### 1. `ollmapp/android/OllmchatWindow.vala` — `initialize_client`: phone pane before the session switch

**Why:** `on_agent_activated` sets `view_stack.visible_child_name` to `"pane"` during the Agent Pi `switch_to_session`. That child has to already be in the stack.

**Where:** Phone branch only. Insert it after `connect_agent_factory_signals()` and before `if (is_desktop_connected && is_desktop_available)`. Delete the same two lines from the later `else`, and leave the tablet `if` and `this.view_stack.visible_child_name = "chat"` at the bottom.

**Depends on:** none.

#### Add — `initialize_client`, immediately before `if (is_desktop_connected && is_desktop_available)`

The phone chat stack gets its `"pane"` child before that switch can show it.

```vala
			if (!this.is_tablet) {
				this.chat_widget.view_stack.add_named(this.pane_stack, "pane");
				this.chat_container.append(this.chat_widget);
			}
```

#### Remove

```vala
			} else {
				this.chat_widget.view_stack.add_named(this.pane_stack, "pane");
				this.chat_container.append(this.chat_widget);
			}
```

#### Replace with

```vala
			}
```

### 2. `ollmapp/ChatUserInterface.vala` — `connect_agent_factory_signals`: parent the phone pull-over

**Why:** Startup creates the coder from these callbacks. `on_editor` is the text-editor button, so it never runs for that show. `SelectorPull.visible = true` does nothing until the pull-over is on `chat_widget.cover`.

**Where:** The `activate.end` callback on `agent_activated`, and the one on `session_restored`. Same replacement in both. `activate_session_and_sync_ui` is unchanged: its switch still reaches `session_restored`.

**Depends on:** none.

#### Remove

```vala
				factory.activate.begin(this, (obj, res) => {
					factory.activate.end(res);
				});
```

#### Replace with

```vala
				factory.activate.begin(this, (obj, res) => {
					factory.activate.end(res);
					if (factory.name != "agent-pi") {
						return;
					}
					var tabs = (Adw.ViewStack) ((OLLMchat.ChatDesktopInterface) this).tab_view();
					var coder = (OLLMcoder.CoderView) tabs.get_visible_child();
					if (coder.files.form != OLLMcoder.Form.PHONE ||
						coder.selector.get_parent() != null) {
						return;
					}
					this.chat_widget.cover.add_overlay(coder.selector);
				});
```

- ✔️ 2026-10-30: applied in `ollmapp/android/OllmchatWindow.vala` and `ollmapp/ChatUserInterface.vala`. Host `ninja -C build ollmapp/ollmchat.p/ChatUserInterface.c` succeeded. The android window is not in that target.

## Attempts / changelog

- ℹ️ 2026-10-30: logcat for pid 13575 after the 10:18 install. No code change.
- ℹ️ 2026-10-30: proposed fix written above. `mount_pull` removed. No product change.
- ℹ️ 2026-10-30: applied §1 and §2. No new method.
- ℹ️ 2026-10-30 15:45: phone `192.168.88.145:35617` is up. `adb install -r` of `app-arm64-v8a-debug.apk` (built 15:31, after these edits) failed `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Installed package was updated 10:18, cert SHA-256 `26304203…`. This APK is cert SHA-256 `967ef8e8…`. The 10:18 build is still the one on the phone.

## Next

- 🚫 None. Closed.
