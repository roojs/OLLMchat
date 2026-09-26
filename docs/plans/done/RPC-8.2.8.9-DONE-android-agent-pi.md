# 8.2.8.9 — DONE — Android Agent Pi when the desktop environment is live

**Status:** **DONE** ✔️ — Phase 1–2 in tree. Phases 3–5 are [`RPC-8.2.8.11-DONE-android-startup-history-bars.md`](RPC-8.2.8.11-DONE-android-startup-history-bars.md). Phases 6–8 are [`RPC-8.2.8.12-android-editor-chrome-bars.md`](../RPC-8.2.8.12-android-editor-chrome-bars.md).

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](../RPC-8.2.8-filesd-connections-ui.md) Phase 10

**Split to:** [`RPC-8.2.8.11-DONE-android-startup-history-bars.md`](RPC-8.2.8.11-DONE-android-startup-history-bars.md), then [`RPC-8.2.8.12-android-editor-chrome-bars.md`](../RPC-8.2.8.12-android-editor-chrome-bars.md)

**Depends on:**

- Phone connection flow, user-closed 2026-09-23 (Check stays up, row survives restart)
- [`RPC-8.2.8.6`](RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) — Android `ProjectManager`, HTTPS hello
- [`RPC-8.2.8.8`](../RPC-8.2.8.8-android-phone-tablet-pane.md) — `ChatDesktopInterface`, phone stack, tablet column

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`. Phases 1–2 are applied.

---

## Purpose

- **🔷** The phone gets Agent Pi only while the desktop environment is reachable.
- **🔷** Each phase below is the whole design for that slice. Read that phase on its own.
- **🔷** Call-site files import `OLLMchat.Settings` at the top. We normally do not `using`. Do it here only because `OLLMchat.Settings.FilesdClient.State.ENABLED` is too long. After the import the path is `FilesdClient.State.SOCKET`, `FilesdClient.State.LIVE`, and the other states.
- **ℹ️** Desktop Linux already registers Agent Pi at window setup (`ollmapp/Window.vala`). This plan does not change that.
- **ℹ️** Only Agent Pi. Not Code Assistant. Not Skill Runner. Parent decision in [`8.2.8.2`](RPC-8.2.8.2-DONE-filesd-android-file-connection.md).
- **ℹ️** Still one desktop environment. Home, office, and an online proxy host are [`8.2.8`](../RPC-8.2.8-filesd-connections-ui.md) Phase 13.
- **ℹ️** Startup hello and history-when-off are [`8.2.8.11`](RPC-8.2.8.11-DONE-android-startup-history-bars.md). Editor chrome and bar placement are [`8.2.8.12`](../RPC-8.2.8.12-android-editor-chrome-bars.md).

---

## Phase 1 — File connection state (`✔️`)

`FilesdClient` is the one outbound row (`filesd_client` on `Config2`). Desktop and Android share it.

- **ℹ️** Flags today (`libollmchat/Settings/FilesdClient.vala`):
  - `url` — HTTPS base. Empty means no row.
  - `approved` — the desktop has accepted this device. Check sets it true. The row subtitle is "Active" when true and "Requested" when false. This is the server-side flag.
  - `enabled` — the user switch. Off means do not connect. On means connect once `approved` is true. Default true. This is the client-side flag.
- **🔷** `✔️` Replace `approved` and `enabled` with one enum. JSON stores that enum as an integer.
- **🔷** `url` stays a string. Remove is still "no row" (empty `url`), not an enum value.
- **🔷** Skip migrating old `"approved"` / `"enabled"` JSON. Nothing in the wild uses those keys yet. Default deserialize loads `state`.

States:

- **🔷** `0` `REQUESTED` — registration sent. The desktop has not approved. Today's `approved == false`.
- **🔷** `1` `DISABLED` — the desktop has approved. The user turned the connection off. Do not hello. Do not show Agent Pi.
- **🔷** `2` `ENABLED` — the desktop has approved. The user turned it on. Hello has not finished this run.
- **🔷** `3` `LIVE` — hello succeeded. Agent Pi may be added to the agent list. This is active and enabled.
- **🔷** `4` `UNREACHABLE` — the desktop has approved and the user left it on, but the short hello failed. Agent Pi stays off. This is not `DISABLED`. The next startup hellos again.

Transitions:

- **🔷** A missed hello sets `UNREACHABLE`. It does not set `DISABLED`.
- **🔷** The user turns the switch off from `ENABLED`, `LIVE`, or `UNREACHABLE` → `DISABLED`. If the open chat is Agent Pi, start a new Chatter session.
- **🔷** Remove, while the open chat is Agent Pi, also starts a new Chatter session.
- **🔷** The user turns the switch on from `DISABLED` → `ENABLED`, then hello → `LIVE` or `UNREACHABLE`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

`⏳` Switch-off and Remove still owe the new Chatter session. These hunks only replace the flags.

### 1. `libollmchat/Settings/FilesdClient.vala` — `state` integer on the wire

**Why:** One enum replaces `approved` and `enabled`. JSON stores the ordinal, not the enum name.

**Where:** Property block, then `serialize_property` / `deserialize_property`.

**Depends on:** none.

#### Remove

```vala
		/**
		 * Desktop has accepted registration (Check sets true in Phase 2).
		 * UI: false → ''Requested'', true → ''Active''.
		 */
		public bool approved { get; set; default = false; }

		/**
		 * When false, Phase 2 must not connect / must not override local Unix.
		 */
		public bool enabled { get; set; default = true; }
```

#### Replace with

```vala
		/**
		 * Connection state. JSON is the ordinal.
		 *
		 * 0 requested, 1 disabled, 2 enabled, 3 live, 4 unreachable.
		 */
		public enum State {
			REQUESTED,
			DISABLED,
			ENABLED,
			LIVE,
			UNREACHABLE
		}

		public State state { get; set; default = State.REQUESTED; }
```

#### Remove

```vala
		public override Json.Node serialize_property(
			string property_name, Value value, ParamSpec pspec)
		{
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec,
			Json.Node property_node)
		{
			return default_deserialize_property(
				property_name, out value, pspec, property_node);
		}
```

#### Replace with

```vala
		public override Json.Node serialize_property(
			string property_name, Value value, ParamSpec pspec)
		{
			if (property_name == "state") {
				var node = new Json.Node(Json.NodeType.VALUE);
				node.set_int((int) this.state);
				return node;
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(
			string property_name, out Value value, ParamSpec pspec,
			Json.Node property_node)
		{
			if (property_name == "state") {
				value = Value(typeof(State));
				value.set_enum((int) property_node.get_int());
				return true;
			}
			return default_deserialize_property(
				property_name, out value, pspec, property_node);
		}
```

### 2. `libollmchat/Settings/Config2.vala` — old `filesd-client` bools

**Why:** A file written before `state` would still have `approved` and `enabled`.

**🔷** Skipped. Nothing has those keys on disk yet. `filesd-client` uses default deserialize, same as `filesd`.

### 3. Call sites that still name `approved` / `enabled`

**Why:** Those properties are gone. Startup still hellos for a row the user left on (`ENABLED`, `LIVE`, or `UNREACHABLE`).

**Depends on:** §1.

- **🔷** Each of these files gets `using OLLMchat.Settings;` after the copyright block, before `namespace`. We normally do not `using`. Do it here only because `FilesdClient.State.*` is otherwise `OLLMchat.Settings.FilesdClient.State.*` at every site.

#### Add — after the copyright block, before `namespace`

Same hunk in:

- `ollmapp/Window.vala`
- `ollmapp/android/OllmchatWindow.vala`
- `ollmapp/SettingsDialog/ConnectionsPage.vala`
- `ollmapp/SettingsDialog/FileConnectionRow.vala`

```vala
// Normally no using. FilesdClient.State.* without this is
// OLLMchat.Settings.FilesdClient.State.* at every site.
using OLLMchat.Settings;
```

#### Remove — `ollmapp/Window.vala` and `ollmapp/android/OllmchatWindow.vala` `initialize_client`

```vala
			if (config.filesd_client.url != "" && config.filesd_client.enabled
				&& config.filesd_client.approved) {
```

#### Replace with

```vala
			if (config.filesd_client.url != ""
				&& (config.filesd_client.state == FilesdClient.State.ENABLED
					|| config.filesd_client.state == FilesdClient.State.LIVE
					|| config.filesd_client.state == FilesdClient.State.UNREACHABLE)) {
```

#### Remove — `ollmapp/SettingsDialog/ConnectionsPage.vala` after a new registration

```vala
				this.dialog.app.config.filesd_client.url = this.add_file_dialog.registered_url;
				this.dialog.app.config.filesd_client.approved = false;
				this.dialog.app.config.filesd_client.enabled = true;
```

#### Replace with

```vala
				this.dialog.app.config.filesd_client.url = this.add_file_dialog.registered_url;
				this.dialog.app.config.filesd_client.state =
					FilesdClient.State.REQUESTED;
```

#### Remove — `ConnectionsPage.render_file_connection`

```vala
				var was_live = client.enabled && client.approved;
```

#### Replace with

```vala
				var was_live = client.state == FilesdClient.State.LIVE;
```

#### Remove — `FileConnectionRow` subtitle

```vala
			var subtitle = client.approved ? "Active" : "Requested";
```

#### Replace with

```vala
			var subtitle = "Requested";
			if (client.state != FilesdClient.State.REQUESTED) {
				subtitle = "Active";
			}
```

#### Remove — `FileConnectionRow` switch

```vala
			this.enabled_switch = new Gtk.Switch() {
				active = client.enabled,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
```

#### Replace with

```vala
			this.enabled_switch = new Gtk.Switch() {
				active = client.state != FilesdClient.State.DISABLED,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
```

#### Remove — `FileConnectionRow` switch handler

```vala
				if (this.enabled_switch.active == this.client.enabled) {
					return;
				}
```

#### Replace with

```vala
				if (this.enabled_switch.active
					== (this.client.state != FilesdClient.State.DISABLED)) {
					return;
				}
```

#### Remove

```vala
				this.client.enabled = this.enabled_switch.active;
				this.win.app.config.save();
				if (!this.client.approved) {
					return;
				}
				this.reconnect.begin(this.enabled_switch.active);
```

#### Replace with

```vala
				if (this.enabled_switch.active) {
					if (this.client.state == FilesdClient.State.REQUESTED) {
						return;
					}
					this.client.state = FilesdClient.State.ENABLED;
				} else if (this.client.state != FilesdClient.State.REQUESTED) {
					this.client.state = FilesdClient.State.DISABLED;
				}
				this.win.app.config.save();
				if (this.client.state != FilesdClient.State.ENABLED) {
					return;
				}
				this.reconnect.begin(true);
```

#### Remove — `FileConnectionRow.check` success

```vala
			this.client.approved = true;
```

#### Replace with

```vala
			if (this.enabled_switch.active) {
				this.client.state = FilesdClient.State.ENABLED;
			} else {
				this.client.state = FilesdClient.State.DISABLED;
			}
```

#### Remove — `FileConnectionRow.reconnect` remote failure

```vala
				this.client.enabled = false;
				this.win.app.config.save();
				this.enabled_switch.active = false;
				this.expander.subtitle = "Failed: " + rpc.connect_error;
```

#### Replace with

A missed hello is `UNREACHABLE`. The switch stays on.

```vala
				this.client.state = FilesdClient.State.UNREACHABLE;
				this.win.app.config.save();
				this.expander.subtitle = "Unreachable: " + rpc.connect_error;
```

---

## Phase 2 — Agent Pi appears after Check (`✔️`)

Live means Phase 1 state `LIVE`: the row is approved, the user left it on, and the HTTPS hello succeeded. `SOCKET` is the local Unix daemon hello. Agent Pi is in the list for either.

- **🔷** `FileConnectionRow` only writes `state` and reconnects. It does not register agents, tools, or switch the chat.
- **🔷** `FilesdClient.state` is a GObject property. `notify["state"]` is the signal. Each part listens and does its own job.
- **🔷** Add `SOCKET` (`5`) to `FilesdClient.State`. Do not renumber `0`–`4`.
- **🔷** `SOCKET` is the local `ollmfilesd` Unix socket hello. Empty `url`, desktop typical. Not a remote row.
- **🔷** Agent Pi is visible when state is `SOCKET` or `LIVE`. No `#if ANDROID` on that check. Other agents always match.
- **🔷** No file daemon (not even enabled, unix hello failed): not `SOCKET`, not `LIVE`. Hide Agent Pi.
- **🔷** `History.Manager` listens and, on `LIVE`, starts a new empty session whose `agent_name` is `agent-pi`. `SOCKET` only shows Agent Pi. It does not start a new session.
- **🔷** `AgentDropdown` listens and refilters. It does not rebuild the store.
- **🔷** No hunting for the selected agent. Read `dropdown.selected_item`. Write `select_only` from `dropdown-pos` stashed on the factory in `bind` (`list_item.position`).
- **🔷** One backing `GLib.ListStore` on `AgentDropdown`. The dropdown model is `Gtk.FilterListModel`. No extra store class.
- **🔷** Check success with the switch on reconnects, then sets `LIVE`. Listeners show Agent Pi and switch the open chat.
- **🔷** No live desktop environment: stay on Chatter. Do not show Agent Pi in the agent list.
- **🔷** Every `state == LIVE` that means “file backend is up” also allows `SOCKET` (`was_live`, save, startup hello when `url != ""`).
- **ℹ️** Android `register_default_agents()` adds Chatter only (`ollmapp/ChatUserInterface.vala`).
- **ℹ️** `AgentPi.Factory.activate` casts the window to `ChatDesktopInterface`, mounts `SourceView` on `tab_view()`, then `schedule_pane_update(true)`.
- **ℹ️** Desktop Linux already registers Agent Pi at window setup. Do not change that Linux block.
- **ℹ️** Desktop local hello sets `SOCKET`. The Manager `LIVE` early-return is a no-op there.
- **ℹ️** Same filter pattern as `liboccoder/FileDropdown.vala`: `Gtk.FilterListModel` + `Gtk.CustomFilter`.
- **ℹ️** `this.filter.changed(Gtk.FilterChange.DIFFERENT)` is the same call as `libollmchatgtk/HistoryBrowser.vala`.
- **ℹ️** `Gtk.DropDown.selected_item` is how `FileServerRow` and `ProjectDropdown` read the current row.
- **ℹ️** `write` / `read` already go through `ProjectManager` RPC when the client is on HTTPS.
- **ℹ️** `bash` does not exec on the daemon. `RunCommand` calls in-process `OLLMbwrap.Bubble.exec` (or `GLib.Subprocess` when bwrap is missing). Overlay apply is File.* RPC ([`2.10.4.19-DONE-runcommand-overlay-index.md`](2.10.4.19-DONE-runcommand-overlay-index.md)). Remote `bash` is [`RPC-8.2.8.10-android-remote-bash.md`](../RPC-8.2.8.10-android-remote-bash.md). Daemon `Bubble.exec` is [`BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md`](../BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md).
- **🔷** Android Agent Pi needs `bash` on the desktop. That is [`8.2.8.10`](../RPC-8.2.8.10-android-remote-bash.md), not this plan’s hunks. Registering `Bash` on the phone would run on the phone.
- **💩** Check hello is only the approval probe. Going live still needs `reconnect(true)` so `ProjectManager` is on the remote daemon.
- **💩** Android tool fill does not register `write` / `read`. Register those before `wire()`. Do not register `bash` until `Bubble.exec` is RPC.
- **💩** Manager `switch_to_session` does not clear the transcript. `ChatWidget` `session_activated` clears only for `EmptySession`, not when an empty session converts to a real `Session`.
- **💩** `window_config.agent` is saved on a user pick, not on `select_only`. Save it from `session_activated` so a LIVE switch sticks.
- **💩** `reconnect(false)` after a remote miss may assign `SOCKET` while `url` is still set. Do not `save()` that over the remote row. Phase 3 still hellos the URL when `url != ""`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 1. `libollmchat/Settings/FilesdClient.vala` — add `SOCKET`

**Why:** Agent Pi follows the file backend. Local Unix hello is `SOCKET`. Remote HTTPS hello is `LIVE`. Same enum, no `#if ANDROID`.

**Where:** Nested `State` enum and the ordinal comment.

**Depends on:** Phase 1 (enum already in tree).

#### Remove

```vala
		 * 0 requested, 1 disabled, 2 enabled, 3 live, 4 unreachable.
		 */
		public enum State {
			REQUESTED,
			DISABLED,
			ENABLED,
			LIVE,
			UNREACHABLE
		}
```

#### Replace with

```vala
		 * 0 requested, 1 disabled, 2 enabled, 3 live, 4 unreachable,
		 * 5 socket.
		 */
		public enum State {
			REQUESTED,
			DISABLED,
			ENABLED,
			LIVE,
			UNREACHABLE,
			SOCKET
		}
```

### 2. `ollmapp/AgentDropdown.vala` — filter the backing store, listen to `state`

**Why:** Agent Pi stays in one `ListStore`. The dropdown shows it when state is `SOCKET` or `LIVE`. The row does not touch the dropdown. Selection is `selected_item` and `list_item.position` on the factory, not a scan.

**Where:** `bind`, file top `using`, fields, then `wire()`: store fill, model, `selected_item`, `notify["state"]`.

**Depends on:** §1.

#### Add — in `list_factory.bind`, after `var agent_factory = list_item.item as OLLMchat.Agent.Factory;`

Stash the filtered row index on the factory so `select_only` does not scan.

```vala
				agent_factory.set_data<uint>("dropdown-pos", list_item.position);
```

#### Add — after the copyright block, before `namespace`

```vala
// Normally no using. FilesdClient.State.* without this is
// OLLMchat.Settings.FilesdClient.State.* at every site.
using OLLMchat.Settings;
```

#### Add — after `private bool block_select_signal = false;`

```vala
		private GLib.ListStore store;
		private Gtk.CustomFilter filter;
```

#### Remove — `wire()` store fill and `ListStore` model

```vala
			var agent_store = new GLib.ListStore(typeof(OLLMchat.Agent.Factory));

			uint selected_index = 0;
			uint i = 0;
			foreach (var factory in this.host.history_manager.agent_factories.values) {
				agent_store.append(factory);
				if (factory.name == this.host.history_manager.session.agent_name) {
					selected_index = i;
				}
				i++;
			}

			this.dropdown.model = agent_store;
```

#### Replace with

```vala
			this.store = new GLib.ListStore(typeof(OLLMchat.Agent.Factory));
			foreach (var factory in this.host.history_manager.agent_factories.values) {
				this.store.append(factory);
			}
			this.filter = new Gtk.CustomFilter((item) => {
				var factory = (OLLMchat.Agent.Factory) item;
				if (factory.name != "agent-pi") {
					return true;
				}
				switch (this.host.history_manager.config.filesd_client.state) {
					case FilesdClient.State.LIVE:
					case FilesdClient.State.SOCKET:
						return true;
					default:
						return false;
				}
			});
			this.dropdown.model = new Gtk.FilterListModel(this.store, this.filter);
			this.host.history_manager.config.filesd_client.notify["state"].connect(() => {
				this.filter.changed(Gtk.FilterChange.DIFFERENT);
			});
```

#### Remove — `notify["selected"]` item lookup

```vala
				var factory = (this.dropdown.model as GLib.ListStore)
					.get_item(this.dropdown.selected)
					as OLLMchat.Agent.Factory;
```

#### Replace with

```vala
				var factory = (OLLMchat.Agent.Factory) this.dropdown.selected_item;
```

#### Remove — `find` after session switch

```vala
					var agent_index = 0u;
					var store = (GLib.ListStore) this.dropdown.model;
					store.find(factory, out agent_index);
					this.select_only(agent_index);
```

#### Replace with

```vala
					this.select_only(factory.get_data<uint>("dropdown-pos"));
```

#### Remove — `session_activated` `find`

```vala
				var agent_index = 0u;
				var store = (GLib.ListStore) this.dropdown.model;
				store.find(factory, out agent_index);
```

#### Replace with

```vala
				var agent_index = factory.get_data<uint>("dropdown-pos");
```

#### Remove — initial `select_only(selected_index)`

```vala
			this.select_only(selected_index);
```

#### Replace with

```vala
			this.select_only(this.host.history_manager.get_active_agent()
				.get_data<uint>("dropdown-pos"));
```

#### Add — after `this.select_only(agent_index);` in `session_activated`

Save `window_config.agent` on a LIVE-driven switch. `select_only` does not run the user-pick saver.

```vala
				var desktop = this.host as OLLMchat.ChatDesktopInterface;
				if (desktop != null) {
					var row = desktop.window_config();
					row.agent = factory.name;
					this.host.history_manager.config.save();
				}
```

### 3. `libollmchat/History/Manager.vala` — listen to `filesd_client` `state`

**Why:** The row only sets `LIVE`. The manager starts an empty Agent Pi session. Set `agent_name` before the switch so `session_activated` already sees Agent Pi. Do not call `activate_agent` after: same name is a no-op. `SOCKET` does not start a session.

**Where:** Constructor, after `this.config = app.config;`.

**Depends on:** §5 (Android has `agent-pi` in `agent_factories` before Check).

#### Add — after `this.config = app.config;`

```vala
			this.config.filesd_client.notify["state"].connect(() => {
				if (this.config.filesd_client.state != Settings.FilesdClient.State.LIVE) {
					return;
				}
				if (!this.agent_factories.has_key("agent-pi")) {
					return;
				}
				if (this.session.agent_name == "agent-pi") {
					return;
				}
				var empty = this.create_new_session();
				empty.project_path = this.session.project_path;
				empty.agent_name = "agent-pi";
				this.switch_to_session.begin(empty, (obj, res) => {
					try {
						this.switch_to_session.end(res);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
				});
			});
```

### 4. `libollmchatgtk/ChatWidget.vala` — `session_activated` paints a manager-driven switch

**Why:** Manager `switch_to_session` does not call `ChatWidget.switch_to_session`, so the transcript would stay. Limit the clear to `EmptySession` so converting empty → real does not wipe the first send.

**Where:** Existing `session_activated` handler, first lines of the Idle callback.

**Depends on:** §3.

#### Add — first lines inside the `session_activated` Idle callback

```vala
					if (!this.restoring_session && session is OLLMchat.History.EmptySession) {
						this.chat_view.finalize_assistant_message();
						this.clear_chat();
					}
```

### 5. `ollmapp/android/OllmchatWindow.vala` — `initialize_client`: Agent Pi on the backing store

**Why:** `wire()` copies `agent_factories` once. Agent Pi must already be in that map. The filter hides it until `SOCKET` or `LIVE`.

**Where:** After `this.register_default_agents();`, before `this.agent_dropdown.wire();`.

**Depends on:** §2.

#### Add — after `this.register_default_agents();`, before `this.agent_dropdown.wire();`

```vala
			if (!this.history_manager.tools.has_key("write")) {
				this.history_manager.register_tool(
					new OLLMtools.EditMode.Write(this.project_manager));
			}
			if (!this.history_manager.tools.has_key("read")) {
				this.history_manager.register_tool(
					new OLLMtools.ReadFile.Read(this.project_manager));
			}
```

`bash` and `AgentPi.Factory.register_config` wait on [`RPC-8.2.8.10`](../RPC-8.2.8.10-android-remote-bash.md). Do not register `Bash` here.

### 6. `ollmapp/Window.vala` — local hello sets `SOCKET`

**Why:** Desktop Agent Pi follows the Unix daemon, not `#if ANDROID`. Empty `url` plus a successful hello is `SOCKET`.

**Where:** `initialize_client`, after the successful `rpc.connect` (the block that currently continues into “Preparing agents”).

**Depends on:** §1.

#### Add — after the hello succeeds, before “Preparing agents”

```vala
			if (config.filesd_client.url == "") {
				config.filesd_client.state = FilesdClient.State.SOCKET;
				this.app.config.save();
			}
```

### 7. `ollmapp/SettingsDialog/FileConnectionRow.vala` — `reconnect` success sets `LIVE` or `SOCKET`

**Why:** Setting state is the row's job. Remote hello is `LIVE`. Local Unix hello is `SOCKET`. `notify["state"]` wakes the dropdown and the manager.

**Where:** End of `reconnect()`, after the success `client.project.load_end` notification.

**Depends on:** §1.

#### Add — after the success `load_end` notification

```vala
			if (remote) {
				this.client.state = FilesdClient.State.LIVE;
				this.win.app.config.save();
				return;
			}
			this.client.state = FilesdClient.State.SOCKET;
			if (this.client.url != "") {
				return;
			}
			this.win.app.config.save();
```

### 8. `ollmapp/SettingsDialog/FileConnectionRow.vala` — `check()` success only writes state

**Why:** The row reconnects when the switch is on. It does not switch Agent Pi. Writing `ENABLED` before `LIVE` means a second Check still emits `notify["state"]` if the user had moved to Chatter.

**Where:** `check()` docblock, then the `enabled_switch.active` state write through the approval banner.

**Depends on:** §7.

#### Remove — stale “does not swap RPC” docblock lines

```vala
		 * On success sets {@link OLLMchat.Settings.FilesdClient.state}
		 * from the Enabled switch and saves config. Does not swap
		 * {@link OLLMfiles.ProjectManager} RPC (use the Enabled switch or
		 * restart to connect live).
```

#### Replace with

```vala
		 * On success, switch off is {@link FilesdClient.State.DISABLED}.
		 * Switch on is {@link FilesdClient.State.ENABLED}, then
		 * {@link reconnect} which sets {@link FilesdClient.State.LIVE}.
```

#### Remove

```vala
			if (this.enabled_switch.active) {
				this.client.state = FilesdClient.State.ENABLED;
			} else {
				this.client.state = FilesdClient.State.DISABLED;
			}
			this.win.app.config.save();
			this.expander.subtitle = "Active";
			this.status_label.label = "Active";
			this.check_button.sensitive = true;
			this.win.notification(new OLLMrpc.Notification() {
				method = "Banner.show",
				message = "Device approved — turn the connection off and on to connect"
			});
```

#### Replace with

```vala
			this.expander.subtitle = "Active";
			this.status_label.label = "Active";
			if (!this.enabled_switch.active) {
				this.client.state = FilesdClient.State.DISABLED;
				this.win.app.config.save();
				this.check_button.sensitive = true;
				return;
			}
			this.client.state = FilesdClient.State.ENABLED;
			this.win.app.config.save();
			yield this.reconnect(true);
			this.check_button.sensitive = true;
```

### 9. `ollmapp/SettingsDialog/ConnectionsPage.vala` — `was_live` includes `SOCKET`

**Why:** Removing the remote row while the backend is up must still fall back to the Unix daemon. `SOCKET` is up.

**Where:** `render_file_connection` remove handler.

**Depends on:** §1.

#### Remove

```vala
				var was_live = client.state == FilesdClient.State.LIVE;
```

#### Replace with

```vala
				var was_live = client.state == FilesdClient.State.LIVE
					|| client.state == FilesdClient.State.SOCKET;
```

### 10. `ollmapp/Window.vala` and `ollmapp/android/OllmchatWindow.vala` — startup HTTPS also if `SOCKET`

**Why:** A saved `SOCKET` with `url != ""` is last run’s local fallback. Still hello the remote URL. Empty `url` plus `SOCKET` stays local (the `url != ""` guard).

**Where:** `initialize_client` remote `replace_rpc` condition.

**Depends on:** §1.

#### Remove — both windows

```vala
				&& (config.filesd_client.state == FilesdClient.State.ENABLED
					|| config.filesd_client.state == FilesdClient.State.LIVE
					|| config.filesd_client.state == FilesdClient.State.UNREACHABLE)) {
```

#### Replace with

```vala
				&& (config.filesd_client.state == FilesdClient.State.ENABLED
					|| config.filesd_client.state == FilesdClient.State.LIVE
					|| config.filesd_client.state == FilesdClient.State.UNREACHABLE
					|| config.filesd_client.state == FilesdClient.State.SOCKET)) {
```

---

## Remaining work

**➡️** [`RPC-8.2.8.11-DONE-android-startup-history-bars.md`](RPC-8.2.8.11-DONE-android-startup-history-bars.md) — startup hello, history when Agent Pi is off, phone pickers. Editor chrome and bar placement are [`8.2.8.12`](../RPC-8.2.8.12-android-editor-chrome-bars.md).

---

## LLM notes

- **🚫** Code Assistant and Skill Runner on Android.
- **🚫** Changing Linux Agent Pi registration.
- **🚫** `#if ANDROID` to decide whether Agent Pi is in the list. That check is `SOCKET` or `LIVE`.
- **🚫** Index loops / `ListStore.find` to locate the selected agent.
- **🚫** Registering in-process `Bash` on Android. Exec stays on the daemon ([`8.2.8.10`](../RPC-8.2.8.10-android-remote-bash.md)).
- **🚫** `FileConnectionRow` registering tools, constructing `AgentPi.Factory`, appending the dropdown store, calling `switch_to_session`, or `activate_agent`.
- **🚫** A second agent `ListStore` class, or rebuilding the dropdown store when `state` changes.
- **🚫** More than one desktop environment. That is parent Phase 13.
- **ℹ️** Startup hello and history 🚫 list live on [`8.2.8.11`](RPC-8.2.8.11-DONE-android-startup-history-bars.md). Bar placement 🚫 list lives on [`8.2.8.12`](../RPC-8.2.8.12-android-editor-chrome-bars.md).
