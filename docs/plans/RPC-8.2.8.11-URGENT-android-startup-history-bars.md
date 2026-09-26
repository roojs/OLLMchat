# 8.2.8.11 URGENT — Android startup hello, history, and bars

**Status:** **URGENT** · Phases 1–2 **✔️** · Phases 3–6 **⏳**

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md) Phase 11

**Split from:** [`RPC-8.2.8.9-DONE-android-agent-pi.md`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) Phases 3–8. That plan is closed. Phase 1 here was Phase 3 there, through Phase 6 here = Phase 8 there.

**Depends on:**

- Phone connection flow, user-closed 2026-09-23 (Check stays up, row survives restart)
- [`RPC-8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) — `FilesdClient.State`, Agent Pi on `SOCKET` / `LIVE`, Check listen
- [`RPC-8.2.8.8`](RPC-8.2.8.8-android-phone-tablet-pane.md) — `ChatDesktopInterface`, phone stack, tablet column

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`. Code fences after each phase is agreed, or when the existing bullets are enough to apply.

---

## Purpose

- **🔷** Leftover Android Agent Pi work from [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md). That file closed after state + visibility.
- **🔷** This ticket is **URGENT**.
- **🔷** Each phase below is the whole design for that slice. Read that phase on its own.
- **ℹ️** State enum, dropdown filter, Manager `LIVE` listen, and Check reconnect are already in tree ([`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) Phases 1–2).
- **ℹ️** Still one desktop environment. Home, office, and an online proxy host are [`8.2.8`](RPC-8.2.8-filesd-connections-ui.md) Phase 13.
- **ℹ️** Remote `bash` is [`8.2.8.10`](RPC-8.2.8.10-android-remote-bash.md). Not this plan.

---

## Phase 1 — Startup hello (`✔️`)

- **🔷** `✔️` On startup, if the desktop environment is already live, the session starts on Agent Pi. Same switch as [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) Phase 2, before the first session paint.
- **🔷** That check is a hello to the file server. The desktop may be on another network.
- **🔷** `✔️` That hello waits 15 seconds. Do not sit on the normal RPC wait.
- **🔷** `✔️` While it waits, the startup spinner stays up. The status line says it is checking the desktop environment.
- **ℹ️** The probe is `RPC-Daemon.hello`, not an ICMP ping.
- **ℹ️** The spinner is already on the startup panel in `ollmapp/android/OllmchatWindow.vala`, next to `startup_status_label`. `view_stack` stays on `"startup"` through `initialize_client`.
- **ℹ️** `OllmchatWindow.initialize_client` already sends that hello when the row is approved and enabled. Failure today is `Alert.show` ("File server: …") and startup continues.
- **ℹ️** `Client.call_timeout_seconds` defaults to 120. That is the socket wait. HTTP `connect` does not read it. This hello sets `http.soup.timeout` to 15, then back to 0.
- **ℹ️** Empty `url` plus a successful local hello is already `SOCKET` in desktop `ollmapp/Window.vala`. Android hellos only when `url != ""`. Success here is `LIVE`.
- **ℹ️** `AgentPi.Factory.register_config` aborts without `bash`. Do not call it. Registration of `Bash` is [`8.2.8.10`](RPC-8.2.8.10-android-remote-bash.md). The factory still goes in `agent_factories` so the `LIVE` switch can run. The dropdown filter hides it until `LIVE`.
- **🔷** Hello succeeds → state `LIVE` (remote) or `SOCKET` (local, empty `url`), then [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) Phase 2's Agent Pi visibility. Remote `LIVE` still switches the session.
- **🔷** Startup hellos the remote URL when `url != ""` and state is `ENABLED`, `LIVE`, `UNREACHABLE`, or `SOCKET`.
- **🔷** Hello fails or times out:
  - State `UNREACHABLE` (Phase 1 on [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md)). Do not add Agent Pi. Do not show it in the agent list.
  - Start a new Chatter session. Do not keep the open chat on Agent Pi.
  - Header banner: the desktop environment is unavailable.
- **🔷** That notice is `Banner.show` on `window.notification`.
  - **ℹ️** `Banner.show` is the dismissible header banner (`Adw.Banner` on desktop, `tool_error_banner`).
  - **ℹ️** `Alert.show` is a modal OK dialog. This notice is not that dialog.
  - **ℹ️** `ActivityBanner` is scan and index progress. Not this notice.
  - **ℹ️** Android today turns both `Banner.show` and `Alert.show` into `Adw.AlertDialog`. This notice still uses `Banner.show`. Android must show that as a banner, not a dialog.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 1. `libocrpc/Transport/HttpClient.vala` — `soup` visible

**Why:** The startup hello is HTTP. `Client.connect` does not apply `call_timeout_seconds` on that path. The wait is `Soup.Session.timeout` on the session `call` already uses. `0` is no limit, which is today's behavior after the hello.

**Where:** The `soup` field, after `tls_certificate`.

**Depends on:** none.

#### Remove

```vala
		private Soup.Session soup { get; set; default = new Soup.Session(); }
```

#### Replace with

Callers set `timeout` on this session. They do not replace it.

```vala
		/**
		 * Soup session used by {@link call}.
		 *
		 * Startup sets {@link Soup.Session.timeout} to 15 for the
		 * desktop hello, then 0. 0 means no limit.
		 */
		public Soup.Session soup { get; private set; default = new Soup.Session(); }
```

### 2. `ollmapp/android/OllmchatWindow.vala` — header banner

**Why:** Desktop-unavailable is `Banner.show`. Android must reveal an `Adw.Banner`, not an `Adw.AlertDialog`. `Alert.show` stays a dialog.

**Where:** Field next to `startup_status_label`. Create the banner before `notification.connect`. Put it under the header with `toolbar_view.add_top_bar`.

**Depends on:** none.

#### Add — field after `public Gtk.Label startup_status_label;`

```vala
		private Adw.Banner tool_error_banner;
```

#### Add — immediately before `this.notification.connect`

Create the dismissible banner the handler reveals.

```vala
			this.tool_error_banner = new Adw.Banner("") {
				button_label = "Dismiss",
				revealed = false
			};
			this.tool_error_banner.button_clicked.connect(() => {
				this.tool_error_banner.revealed = false;
			});
```

#### Remove

```vala
				if (notif.method == "Banner.show") {
					var banner = new Adw.AlertDialog("OLLMchat", notif.message);
					banner.add_response("ok", "OK");
					banner.choose.begin(this, null);
					return;
				}
```

#### Replace with

Reveal the header banner. Leave `Alert.show` as the dialog below this `if`.

```vala
				if (notif.method == "Banner.show") {
					this.tool_error_banner.title = notif.message;
					this.tool_error_banner.revealed = true;
					return;
				}
```

#### Add — after `toolbar_view.add_top_bar(this.header_bar);`

```vala
			toolbar_view.add_top_bar(this.tool_error_banner);
```

### 3. `ollmapp/android/OllmchatWindow.vala` — `initialize_client` hello

**Why:** The spinner is already on the startup panel. The status line says the desktop is being checked, and this hello waits 15 seconds. Reachability is recorded here. State and the session switch happen in §5, after Agent Pi is in the map and the chat widget is listening, so the switch finishes before the first chat paint.

**Where:** `initialize_client`, the `filesd_client.url` hello `if`.

**Depends on:** §1.

#### Add — immediately before `if (config.filesd_client.url != "")`

Flags for §5. Both stay false when this startup does not hello.

```vala
			var desktop_checked = false;
			var desktop_reached = false;
```

#### Add — first lines inside that `if`, before `var tls`

```vala
				desktop_checked = true;
				this.startup_status_label.label = "Checking desktop environment…";
```

#### Remove

```vala
				var http = new OLLMrpc.Transport.HttpClient(config.filesd_client.url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				this.project_manager.replace_rpc(
					new OLLMrpc.Client("", "", config.filesd_client.url) { 
						http = http 
					}
				);
				var hello = new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				};
				if (!yield this.project_manager.rpc.connect(hello)) {
					var msg = this.project_manager.rpc.connect_error;
					if (msg == "") {
						msg = "could not reach the file server";
					}
					GLib.warning("%s", msg);
					this.notification(new OLLMrpc.Notification() {
						method = "Alert.show",
						message = "File server: " + msg
					});
				}
```

#### Replace with

15 seconds on this hello only. Log a miss. Do not alert. Put the status line back when the hello returns.

```vala
				var http = new OLLMrpc.Transport.HttpClient(config.filesd_client.url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				http.soup.timeout = 15;
				this.project_manager.replace_rpc(
					new OLLMrpc.Client("", "", config.filesd_client.url) { 
						http = http 
					}
				);
				var hello = new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				};
				desktop_reached = yield this.project_manager.rpc.connect(hello);
				http.soup.timeout = 0;
				if (!desktop_reached) {
					var msg = this.project_manager.rpc.connect_error;
					if (msg == "") {
						msg = "could not reach the file server";
					}
					GLib.warning("%s", msg);
				}
				this.startup_status_label.label = "Opening chat…";
```

### 4. `ollmapp/android/OllmchatWindow.vala` — `initialize_client` Agent Pi factory

**Why:** The `LIVE` listener in `History.Manager` returns unless `agent_factories` has `agent-pi`. Do not call `register_config`. That aborts without `bash`.

**Where:** After the `read` tool registration, before `this.agent_dropdown.wire()`.

**Depends on:** none.

#### Add — after the `read` `register_tool` block, before `this.agent_dropdown.wire()`

```vala
			if (!this.history_manager.agent_factories.has_key("agent-pi")) {
				var agent_pi = new OLLMcoder.AgentPi.Factory(this.project_manager);
				this.history_manager.agent_factories.set(agent_pi.name, agent_pi);
			}
```

### 5. `ollmapp/android/OllmchatWindow.vala` — `initialize_client` session before paint

**Why:** `filesd_client.notify["state"]` starts `switch_to_session.begin`, which does not finish before `view_stack` shows chat. Yield the same new session the listener builds, then set state. The listener sees `agent-pi` already and returns. A miss is `UNREACHABLE`, a Chatter session, and `Banner.show`. The startup stack is still `"startup"` here. `EmptySession.load` returns `this` and restore is skipped, so this switch does not throw. `ChatWidget.switch_to_session` is `async void` and already accepts the `throws` on `Manager.switch_to_session`.

**Where:** After `this.connect_agent_factory_signals();`, before `this.history_manager.agent_status_change.connect`.

**Depends on:** §2, §3, §4.

#### Add — after `this.connect_agent_factory_signals();`

Set `LIVE` only after the yield. Setting it first starts a second switch from the listener.

```vala
			if (desktop_checked && desktop_reached) {
				var empty = this.history_manager.create_new_session();
				empty.project_path = this.history_manager.session.project_path;
				empty.agent_name = "agent-pi";
				yield this.chat_widget.switch_to_session(empty);
				config.filesd_client.state = FilesdClient.State.LIVE;
				this.app.config.save();
			}
			if (desktop_checked && !desktop_reached) {
				config.filesd_client.state = FilesdClient.State.UNREACHABLE;
				this.app.config.save();
				this.notification(new OLLMrpc.Notification() {
					method = "Banner.show",
					message = "The desktop environment is unavailable."
				});
				var empty = this.history_manager.create_new_session();
				empty.project_path = this.history_manager.session.project_path;
				empty.agent_name = "chatter";
				yield this.chat_widget.switch_to_session(empty);
			}
```

---

## Phase 2 — History when Agent Pi is off (`✔️`)

- **🔷** `✔️` An Agent Pi session cannot be restored while Agent Pi is not in the agent list.
- **🔷** The history row stays in the list. It shows the agent name and "disabled". Tapping it does nothing until that agent is available again.
- **ℹ️** The row today is the title plus `display_info` (model and message count). `agent_name` is stored and not shown (`SessionPlaceholder.display_info`, `HistoryBrowser`).
- **ℹ️** `Manager.load_sessions` drops a row whose model is missing (`find_model_by_name` returns null). A missing agent is different: it rewrites `agent_name` to `just-ask` in memory only and still lists the row. That rewrite is the bug. Do not hide the row, and do not retarget it to Chatter.
- **ℹ️** "In the agent list" is the dropdown filter in `ollmapp/AgentDropdown.vala`. `agent-pi` is listed only for `LIVE` or `SOCKET`. Any other name is listed when `agent_factories` has that key. The factory can be registered while the row is still hidden.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 1. `libollmchat/History/Manager.vala` — `load_sessions` keeps `agent_name`

**Why:** A missing agent stays on the row. Rewriting it to `just-ask` retargets the chat to Chatter in memory.

**Where:** `load_sessions`, after `reconstruct_model_usage_from_model()`, before `this.sessions.append`.

**Depends on:** none.

#### Remove

```vala
				if (placeholder.agent_name == "" || !this.agent_factories.has_key(placeholder.agent_name)) {
					GLib.warning(
						"Session fid=%s: unknown agent_name '%s', resetting to just-ask (in memory only)",
						placeholder.fid,
						placeholder.agent_name);
					placeholder.agent_name = "just-ask";
				}

```

### 2. `libollmchat/History/SessionPlaceholder.vala` — `display_info` when the agent is off

**Why:** The secondary line is `display_info`. While the agent is not in the list, that line is the agent name and "disabled". The name is `Factory.title` when the factory is registered, otherwise the stored `agent_name`.

**Where:** `display_info` getter, before the model and message count return.

**Depends on:** none.

#### Remove

```vala
		public override string display_info {
			owned get {
				return "%s - %d %s".printf(
					this.model_usage.model,
					this.total_messages,
					this.total_messages == 1 ? "message" : "messages"
				);
			}
		}
```

#### Replace with

```vala
		public override string display_info {
			owned get {
				var state = this.manager.config.filesd_client.state;
				if (!this.manager.agent_factories.has_key(this.agent_name)
					|| (this.agent_name == "agent-pi"
						&& state != Settings.FilesdClient.State.LIVE
						&& state != Settings.FilesdClient.State.SOCKET)) {
					var agent_label = this.agent_name;
					if (this.manager.agent_factories.has_key(this.agent_name)) {
						agent_label = this.manager.agent_factories.get(this.agent_name).title;
					}
					return agent_label + " disabled";
				}
				return "%s - %d %s".printf(
					this.model_usage.model,
					this.total_messages,
					this.total_messages == 1 ? "message" : "messages"
				);
			}
		}
```

### 3. `libollmchat/History/Session.vala` — `display_info` when the agent is off

**Why:** A restored session uses this getter. Same line as the placeholder.

**Where:** `display_info` getter, before the reply count.

**Depends on:** none.

#### Remove

```vala
		public override string display_info {
			owned get {
				// Count assistant messages (replies) from session messages
				int reply_count = 0;
```

#### Replace with

```vala
		public override string display_info {
			owned get {
				var state = this.manager.config.filesd_client.state;
				if (!this.manager.agent_factories.has_key(this.agent_name)
					|| (this.agent_name == "agent-pi"
						&& state != Settings.FilesdClient.State.LIVE
						&& state != Settings.FilesdClient.State.SOCKET)) {
					var agent_label = this.agent_name;
					if (this.manager.agent_factories.has_key(this.agent_name)) {
						agent_label = this.manager.agent_factories.get(this.agent_name).title;
					}
					return agent_label + " disabled";
				}
				// Count assistant messages (replies) from session messages
				int reply_count = 0;
```

### 4. `libollmchatgtk/HistoryBrowser.vala` — ignore a tap while the agent is off

**Why:** Selecting the row restores the session. While the agent is not listed, clear the selection and do not emit `session_selected`. Clearing it means a later tap still fires after the agent is back.

**Where:** `selection_changed` handler, the `position != Gtk.INVALID_LIST_POSITION` branch.

**Depends on:** none.

#### Remove

```vala
				var position = selection_model.selected;
				if (position != Gtk.INVALID_LIST_POSITION) {
					var session = this.sorted_store.get_item(position) as OLLMchat.History.SessionBase;
					this.session_selected(session);
				}
```

#### Replace with

```vala
				var position = selection_model.selected;
				if (position == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				var session = this.sorted_store.get_item(position) as OLLMchat.History.SessionBase;
				var state = this.manager.config.filesd_client.state;
				if (!this.manager.agent_factories.has_key(session.agent_name)
					|| (session.agent_name == "agent-pi"
						&& state != OLLMchat.Settings.FilesdClient.State.LIVE
						&& state != OLLMchat.Settings.FilesdClient.State.SOCKET)) {
					this.changing_selection = true;
					selection_model.selected = Gtk.INVALID_LIST_POSITION;
					this.changing_selection = false;
					return;
				}
				this.session_selected(session);
```

### 5. `libollmchat/History/Manager.vala` — refresh the line when Agent Pi returns

**Why:** `display_info` is bound once. When `filesd_client` state changes, Agent Pi rows must read it again, so "disabled" leaves after `LIVE` or `SOCKET`.

**Where:** First lines of the `filesd_client.notify["state"]` handler, before the `LIVE` early return.

**Depends on:** §2, §3.

#### Add — first lines inside the `notify["state"]` lambda

```vala
				foreach (var session in this.sessions.id_map.values) {
					if (session.agent_name != "agent-pi") {
						continue;
					}
					session.notify_property("display_info");
				}
```

---

## Phase 3 — Phone bottom bar (`⏳`)

The phone does not keep a left-rail toggle and does not split the screen. The bottom bar (`OLLMchatGtk.ChatBar`) already holds the browser toggle and the model selector. That row is where you change what fills the screen.

- **ℹ️** Phone `schedule_pane_update(true)` replaces the chat: `chat_widget.view_stack` child `"pane"`. `false` puts `"chat"` back. That is the same swap the browser globe uses.
- **ℹ️** Today `ChatBar.tool_button_box` is on the left and the model dropdown follows it. Moving the pickers to the right is Phase 6.
- **🔷** `⏳` Three pickers: browser, text editor, chat.
- **🔷** One of them is the visible page. Picking another replaces it. Chat, browser, and the editor each take the whole content area.
- **🔷** While the session is running, the chat picker shows the thinking mark, even if the editor or the browser is the visible page. That is how you see that chat is occurring without leaving the file.
- **🔷** The mark is `weather-fog-symbolic`, the thinking icon on the model dropdown (`libollmchatgtk/List/ModelUsageFactory.vala`). It is three wavy lines. Each frame hides lines: show one, then two, then three, then back to one. Not a spinner.
- **ℹ️** The icon is one Adwaita symbolic, not three files. Extract each wavy line into its own icon (the other lines hidden) and cycle those on the chat picker while `session.is_running`.
- **🔷** When the session is idle, the chat picker is a speech bubble. The thinking icon is only the running state.
- **ℹ️** Phone only. Tablet keeps today's tool toggles until Phase 5. The three buttons stay in `tool_button_box` on the left. Phase 6 moves them right.
- **ℹ️** Idle icon is Adwaita `chat-message-new-symbolic`. Editor is `document-edit-symbolic`. Browser stays `web-browser-symbolic`.
- **💩** That speech-bubble icon includes a plus badge.
- **💩** The thinking frames advance every 400 ms.
- **ℹ️** Each frame is one icon, cut from Adwaita `weather-fog-symbolic.svg`. The path has three subpaths split by `z m 0 5.003906`. Frame 1 keeps the first subpath. Frame 2 keeps the first two. Frame 3 is the whole path. One icon at a time: one wave, then two, then three.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 1. Fog frame icons

**Why:** The chat picker cycles one icon. Each frame is the same fog mark with later waves removed.

**Where:** `resources/icons/scalable/status/`, and `resources/gresources.xml`.

**Depends on:** none.

#### Add — `resources/icons/scalable/status/ollm-fog-1-symbolic.svg`

Copy `/usr/share/icons/Adwaita/symbolic/status/weather-fog-symbolic.svg`. In `d`, delete from the first `z m 0 5.003906` to the end of the path. Leave the closing `z` on the first subpath.

#### Add — `resources/icons/scalable/status/ollm-fog-2-symbolic.svg`

Same copy. Delete from the second `z m 0 5.003906` to the end. Leave the `z` that closes the second subpath.

#### Add — `resources/icons/scalable/status/ollm-fog-3-symbolic.svg`

The Adwaita file unchanged.

#### Add — before `</gresources>` in `resources/gresources.xml`

```xml
  <gresource prefix="/ollmchat/icons/scalable/status">
    <file alias="ollm-fog-1-symbolic.svg">icons/scalable/status/ollm-fog-1-symbolic.svg</file>
    <file alias="ollm-fog-2-symbolic.svg">icons/scalable/status/ollm-fog-2-symbolic.svg</file>
    <file alias="ollm-fog-3-symbolic.svg">icons/scalable/status/ollm-fog-3-symbolic.svg</file>
  </gresource>
```

### 2. `ollmapp/android/OllmchatWindow.vala` — picker fields and icon path

**Why:** The phone buttons and the fog timeout have to outlive `initialize_client`. The frames are resource icons, so the icon theme has to see that path.

**Where:** Fields after `private bool is_tablet`. Icon path in the existing `realize` handler, before `load_config_and_initialize`.

**Depends on:** §1.

#### Add — after `private bool is_tablet = false;`

```vala
		private Gtk.ToggleButton chat_picker;
		private Gtk.ToggleButton browser_picker;
		private Gtk.ToggleButton editor_picker;
		private bool picker_block = false;
		private uint fog_source = 0;
```

#### Add — first line inside the `realize` handler

```vala
				Gtk.IconTheme.get_for_display(this.display).add_resource_path(
					"/ollmchat/icons");
```

### 3. `ollmapp/android/OllmchatWindow.vala` — three phone pickers

**Why:** Browser, editor, and chat each take the whole phone content area. One stays on. Tablet still uses the tool toggles.

**Where:** `initialize_client`, the `foreach` over `UiWidgets` and the `tool_toggle` handler. Phone skips that loop.

**Depends on:** §2.

#### Remove

```vala
			foreach (var tool in this.history_manager.tools.values) {
				var ui = tool as OLLMchat.Tool.UiWidgets;
				if (ui == null) {
					continue;
				}
				var widget_id = tool.name;
				this.chat_widget.chat_bar.add_tool_toggle(
					widget_id, ui.icon_name, ui.tooltip_text);
				ui.show_view.connect(() => {
					this.chat_widget.chat_bar.toggle_active_tool(widget_id, true);
				});
			}
			this.chat_widget.chat_bar.tool_toggle.connect((tool_name, active) => {
				if (!active) {
					this.schedule_pane_update(false);
					return;
				}
				if (!this.history_manager.tools.has_key(tool_name)) {
					return;
				}
				var ui = this.history_manager.tools.get(tool_name) as OLLMchat.Tool.UiWidgets;
				if (ui == null) {
					return;
				}
				var view = (Gtk.Widget) ui.view_widget;
				if (this.pane_stack.get_child_by_name(tool_name) == null) {
					this.pane_stack.add_named(view, tool_name);
				}
				this.pane_stack.set_visible_child_name(tool_name);
				this.schedule_pane_update(true);
			});
```

#### Replace with

Tablet keeps the tool toggles. Phone gets three exclusive pickers in `tool_button_box`.

```vala
			if (this.is_tablet) {
				foreach (var tool in this.history_manager.tools.values) {
					var ui = tool as OLLMchat.Tool.UiWidgets;
					if (ui == null) {
						continue;
					}
					var widget_id = tool.name;
					this.chat_widget.chat_bar.add_tool_toggle(
						widget_id, ui.icon_name, ui.tooltip_text);
					ui.show_view.connect(() => {
						this.chat_widget.chat_bar.toggle_active_tool(widget_id, true);
					});
				}
				this.chat_widget.chat_bar.tool_toggle.connect((tool_name, active) => {
					if (!active) {
						this.schedule_pane_update(false);
						return;
					}
					if (!this.history_manager.tools.has_key(tool_name)) {
						return;
					}
					var ui = this.history_manager.tools.get(tool_name) as OLLMchat.Tool.UiWidgets;
					if (ui == null) {
						return;
					}
					var view = (Gtk.Widget) ui.view_widget;
					if (this.pane_stack.get_child_by_name(tool_name) == null) {
						this.pane_stack.add_named(view, tool_name);
					}
					this.pane_stack.set_visible_child_name(tool_name);
					this.schedule_pane_update(true);
				});
			}
			if (!this.is_tablet) {
				this.browser_picker = new Gtk.ToggleButton() {
					icon_name = "web-browser-symbolic",
					tooltip_text = "Browser"
				};
				this.editor_picker = new Gtk.ToggleButton() {
					icon_name = "document-edit-symbolic",
					tooltip_text = "Text editor"
				};
				this.chat_picker = new Gtk.ToggleButton() {
					icon_name = "chat-message-new-symbolic",
					tooltip_text = "Chat",
					active = true
				};
				this.chat_widget.chat_bar.tool_button_box.append(this.browser_picker);
				this.chat_widget.chat_bar.tool_button_box.append(this.editor_picker);
				this.chat_widget.chat_bar.tool_button_box.append(this.chat_picker);
				this.browser_picker.toggled.connect(() => {
					if (this.picker_block) {
						return;
					}
					if (!this.browser_picker.active) {
						this.picker_block = true;
						this.browser_picker.active = true;
						this.picker_block = false;
						return;
					}
					var ui = this.history_manager.tools.get("browser") as OLLMchat.Tool.UiWidgets;
					var view = (Gtk.Widget) ui.view_widget;
					if (this.pane_stack.get_child_by_name("browser") == null) {
						this.pane_stack.add_named(view, "browser");
					}
					this.pane_stack.set_visible_child_name("browser");
					this.schedule_pane_update(true);
				});
				this.editor_picker.toggled.connect(() => {
					if (this.picker_block) {
						return;
					}
					if (!this.editor_picker.active) {
						this.picker_block = true;
						this.editor_picker.active = true;
						this.picker_block = false;
						return;
					}
					var factory = this.history_manager.agent_factories.get("agent-pi");
					factory.activate.begin(this, (obj, res) => {
						factory.activate.end(res);
					});
				});
				this.chat_picker.toggled.connect(() => {
					if (this.picker_block) {
						return;
					}
					if (!this.chat_picker.active) {
						this.picker_block = true;
						this.chat_picker.active = true;
						this.picker_block = false;
						return;
					}
					this.schedule_pane_update(false);
				});
			}
```

### 4. `ollmapp/android/OllmchatWindow.vala` — `schedule_pane_update` keeps one picker on

**Why:** Agent Pi `activate` already calls `schedule_pane_update(true)`. The phone pickers have to follow that, or the chat button stays down while the editor is showing.

**Where:** `schedule_pane_update`, the phone branch.

**Depends on:** §3.

#### Remove

```vala
			if (visible) {
				this.chat_widget.view_stack.visible_child_name = "pane";
				return;
			}
			this.chat_widget.view_stack.visible_child_name = "chat";
```

#### Replace with

```vala
			this.chat_widget.view_stack.visible_child_name = visible ? "pane" : "chat";
			if (this.picker_block) {
				return;
			}
			this.picker_block = true;
			this.chat_picker.active = !visible;
			this.browser_picker.active = visible
				&& this.pane_stack.visible_child_name == "browser";
			this.editor_picker.active = visible
				&& this.pane_stack.visible_child_name != "browser";
			this.picker_block = false;
```

### 5. `ollmapp/android/OllmchatWindow.vala` — thinking mark on the chat picker

**Why:** While `session.is_running`, the chat button cycles the three fog frames even if the editor or the browser is the page. Idle is the speech bubble.

**Where:** The existing `agent_status_change` handler, after the wake-lock calls.

**Depends on:** §1, §3.

#### Add — at the end of the `agent_status_change` lambda, after the wake-lock calls

```vala
				if (this.is_tablet) {
					return;
				}
				if (this.fog_source != 0) {
					GLib.Source.remove(this.fog_source);
					this.fog_source = 0;
				}
				if (!running) {
					this.chat_picker.icon_name = "chat-message-new-symbolic";
					return;
				}
				string[] frames = {
					"ollm-fog-1-symbolic",
					"ollm-fog-2-symbolic",
					"ollm-fog-3-symbolic"
				};
				var frame = 0;
				this.chat_picker.icon_name = frames[frame];
				this.fog_source = GLib.Timeout.add(400, () => {
					frame++;
					if (frame > 2) {
						frame = 0;
					}
					this.chat_picker.icon_name = frames[frame];
					return true;
				});
```

---

## Phase 4 — Editor chrome (`⏳`)

When the text editor is the visible page, the column is four bands, top to bottom.

- **🔷** `⏳` The normal OLLMchat header stays on top.
- **🔷** Under that, a second bar: project dropdown and file dropdown. Those already exist inside the coder (`ProjectDropdown`, `FileDropdown`).
- **🔷** Then the text area.
- **🔷** When review is active, the review bar sits at the bottom of the text area. Not in this slice unless review is already showing there on desktop.
- **ℹ️** Desktop review footer is `liboccoder/Diff/ReviewBar.vala`. The phone reuses that band. It does not invent a second review widget.

---

## Phase 5 — Tablet bar (`⏳`)

- **ℹ️** Tablet `schedule_pane_update` only shows or hides the right column. Chat stays on the left ([`8.2.8.8`](RPC-8.2.8.8-android-phone-tablet-pane.md)).
- **🔷** `⏳` Browser and code are the same kind of choice as on the phone. Those two buttons sit on the right of the left column's bottom bar, not on its left edge.
- **🔷** Selecting Agent Pi still fills the right column with the editor. The buttons choose browser vs code in that column.
- **ℹ️** Moving the model selector fully left, on phone and tablet together, is Phase 6. This phase only moves browser and code to the right of that left-column bar.

---

## Phase 6 — Pickers on the right (`⏳`)

- **🔷** `⏳` Later, the same bar on phone and tablet: pickers sit on the right, and the model selector moves fully left.
  - Phone: three pickers (browser, text editor, chat).
  - Tablet: two pickers (browser, code). Chat is the left column, so it is not a picker.

---

## Suggested order

1. **✔️** Phase 1 — startup hello (15s, spinner while checking, `UNREACHABLE`, `Banner.show`, Chatter if miss)
2. **✔️** Phase 2 — history rows for a missing agent stay listed, marked disabled, cannot restore
3. **⏳** Phase 3 — phone bottom bar: browser / editor / chat + thinking icon
4. **⏳** Phase 4 — editor chrome (header, project/file dropdowns, text, review bar)
5. **⏳** Phase 5 — tablet bar: browser and code on the right of the left-column bar
6. **⏳** Phase 6 — pickers on the right, model selector fully left

---

## LLM notes

- **🚫** Code Assistant and Skill Runner on Android.
- **🚫** Changing Linux Agent Pi registration.
- **🚫** A left-rail editor toggle.
- **🚫** A phone split (editor over a short chat strip) and a draggable sash (`Gtk.Paned`).
- **🚫** A spinner on the chat picker. Running is `weather-fog-symbolic`, one wavy line at a time. Idle is a speech bubble.
- **🚫** More than one desktop environment. That is parent Phase 13.
- **🚫** An ICMP ping. Reachability is `RPC-Daemon.hello`.
- **🚫** Waiting the default 120s RPC timeout when the file server is off-network.
- **🚫** `Alert.show` for desktop-environment unavailable.
- **🚫** Turning the saved connection to `DISABLED` because one startup hello missed. That miss is `UNREACHABLE`.
- **🚫** Rewriting a missing `agent_name` to `just-ask`, or hiding that history row.
- **🚫** Registering in-process `Bash` on Android. That is [`8.2.8.10`](RPC-8.2.8.10-android-remote-bash.md).
- **🚫** Reopening [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) for these hunks.
