# 8.2.8.9 — Android Agent Pi when the desktop environment is live

**Status:** **PROPOSED**

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md) Phase 10

**Depends on:**

- Phone connection flow, user-closed 2026-09-23 (Check stays up, row survives restart)
- [`RPC-8.2.8.6`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) — Android `ProjectManager`, HTTPS hello
- [`RPC-8.2.8.8`](RPC-8.2.8.8-android-phone-tablet-pane.md) — `ChatDesktopInterface`, phone stack, tablet column

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`. Hunks wait until this plan is approved.

---

## Purpose

- **🔷** The phone gets Agent Pi only while the desktop environment is reachable.
- **🔷** Each phase below is the whole design for that slice. Read that phase on its own.
- **ℹ️** Desktop Linux already registers Agent Pi at window setup (`ollmapp/Window.vala`). This plan does not change that.
- **ℹ️** Only Agent Pi. Not Code Assistant. Not Skill Runner. Parent decision in [`8.2.8.2`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md).
- **ℹ️** Still one desktop environment. Home, office, and an online proxy host are [`8.2.8`](RPC-8.2.8-filesd-connections-ui.md) Phase 11.

---

## Phase 1 — File connection state (`⏳`)

`FilesdClient` is the one outbound row (`filesd_client` on `Config2`). Desktop and Android share it.

- **ℹ️** Flags today (`libollmchat/Settings/FilesdClient.vala`):
  - `url` — HTTPS base. Empty means no row.
  - `approved` — the desktop has accepted this device. Check sets it true. The row subtitle is "Active" when true and "Requested" when false. This is the server-side flag.
  - `enabled` — the user switch. Off means do not connect. On means connect once `approved` is true. Default true. This is the client-side flag.
- **🔷** `⏳` Replace `approved` and `enabled` with one enum. JSON stores that enum as an integer.
- **🔷** `url` stays a string. Remove is still "no row" (empty `url`), not an enum value.
- **ℹ️** Old JSON has `"approved": bool` and `"enabled": bool`. When `state` is absent, read those two bools into the enum below.

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

Old files have `approved` and `enabled` and no `state`. `Config2` writes `state` onto that object, then deserializes. `!approved` → `REQUESTED`. `approved` and not `enabled` → `DISABLED`. `approved` and `enabled` → `ENABLED` (hello has not run yet). Later saves write `state` as an integer and omit the two bools.

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

### 2. `libollmchat/Settings/Config2.vala` — `deserialize_property`: old `filesd-client` bools

**Why:** A file written before `state` still has `approved` and `enabled`. Those keys are not properties anymore, so the default loader would drop them.

**Where:** `deserialize_property` switch, after the `windows` case.

**Depends on:** §1.

#### Add — after the `windows` case `return true;`

Read the old bools when `state` is missing, store the ordinal, then deserialize `FilesdClient`.

```vala
				case "filesd-client":
					if (property_node.get_node_type() != Json.NodeType.OBJECT) {
						break;
					}
					var client_obj = property_node.get_object();
					if (!client_obj.has_member("state")) {
						var approved = false;
						if (client_obj.has_member("approved")) {
							approved = client_obj.get_boolean_member("approved");
						}
						var enabled = true;
						if (client_obj.has_member("enabled")) {
							enabled = client_obj.get_boolean_member("enabled");
						}
						var migrated = 0;
						if (approved && enabled) {
							migrated = 2;
						} else if (approved) {
							migrated = 1;
						}
						client_obj.set_int_member("state", migrated);
					}
					var client = Json.gobject_deserialize(
						typeof(FilesdClient), property_node) as FilesdClient;
					value = Value(typeof(FilesdClient));
					value.set_object(client);
					return true;
```

### 3. Call sites that still name `approved` / `enabled`

**Why:** Those properties are gone. Startup still hellos for a row the user left on (`ENABLED`, `LIVE`, or `UNREACHABLE`).

**Depends on:** §1.

#### Remove — `ollmapp/Window.vala` and `ollmapp/android/OllmchatWindow.vala` `initialize_client`

```vala
			if (config.filesd_client.url != "" && config.filesd_client.enabled
				&& config.filesd_client.approved) {
```

#### Replace with

```vala
			if (config.filesd_client.url != ""
				&& (config.filesd_client.state == OLLMchat.Settings.FilesdClient.State.ENABLED
					|| config.filesd_client.state == OLLMchat.Settings.FilesdClient.State.LIVE
					|| config.filesd_client.state == OLLMchat.Settings.FilesdClient.State.UNREACHABLE)) {
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
					OLLMchat.Settings.FilesdClient.State.REQUESTED;
```

#### Remove — `ConnectionsPage.render_file_connection`

```vala
				var was_live = client.enabled && client.approved;
```

#### Replace with

```vala
				var was_live = client.state == OLLMchat.Settings.FilesdClient.State.LIVE;
```

#### Remove — `FileConnectionRow` subtitle

```vala
			var subtitle = client.approved ? "Active" : "Requested";
```

#### Replace with

```vala
			var subtitle = "Requested";
			if (client.state != OLLMchat.Settings.FilesdClient.State.REQUESTED) {
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
				active = client.state != OLLMchat.Settings.FilesdClient.State.DISABLED,
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
					== (this.client.state != OLLMchat.Settings.FilesdClient.State.DISABLED)) {
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
					if (this.client.state == OLLMchat.Settings.FilesdClient.State.REQUESTED) {
						return;
					}
					this.client.state = OLLMchat.Settings.FilesdClient.State.ENABLED;
				} else if (this.client.state != OLLMchat.Settings.FilesdClient.State.REQUESTED) {
					this.client.state = OLLMchat.Settings.FilesdClient.State.DISABLED;
				}
				this.win.app.config.save();
				if (this.client.state != OLLMchat.Settings.FilesdClient.State.ENABLED) {
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
				this.client.state = OLLMchat.Settings.FilesdClient.State.ENABLED;
			} else {
				this.client.state = OLLMchat.Settings.FilesdClient.State.DISABLED;
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
				this.client.state = OLLMchat.Settings.FilesdClient.State.UNREACHABLE;
				this.win.app.config.save();
				this.expander.subtitle = "Unreachable: " + rpc.connect_error;
```

---

## Phase 2 — Agent Pi appears after Check (`⏳`)

Live means Phase 1 state `LIVE`: the row is approved, the user left it on, and the HTTPS hello succeeded.

- **ℹ️** Android `register_default_agents()` adds Chatter only (`ollmapp/ChatUserInterface.vala`).
- **ℹ️** Android `OllmchatWindow` never constructs `OLLMcoder.AgentPi.Factory`.
- **ℹ️** `liboccoder/meson.build` already lists `AgentPi/Factory.vala` and `SourceView.vala` for the Android host. Do not start a second library.
- **ℹ️** `AgentPi.Factory.activate` casts the window to `ChatDesktopInterface`, mounts `SourceView` on `tab_view()`, then `schedule_pane_update(true)`.
- **🔷** `⏳` Check success, when the connection is on, adds Agent Pi to the agent list if it is missing, then switches the open chat to Agent Pi.
- **🔷** No live desktop environment: stay on Chatter. Do not show Agent Pi in the agent list.
- **💩** If Agent Pi is already in the agent list, tapping Check again only switches the open chat to Agent Pi. It does not add a second copy.

---

## Phase 3 — Startup hello (`⏳`)

- **🔷** `⏳` On startup, if the desktop environment is already live, the session starts on Agent Pi. Same switch as Phase 2, before the first session paint.
- **🔷** That check is a short-timeout hello to the file server. The desktop may be on another network. Do not sit on the normal RPC wait.
- **ℹ️** The probe is `RPC-Daemon.hello`, not an ICMP ping.
- **ℹ️** `OllmchatWindow.initialize_client` already sends that hello when the row is approved and enabled. Failure today is `Alert.show` ("File server: …") and startup continues. `Client.call_timeout_seconds` defaults to 120.
- **🔷** Hello succeeds → state `LIVE`, then Phase 2's switch to Agent Pi.
- **🔷** Hello fails or times out:
  - State `UNREACHABLE` (Phase 1). Do not add Agent Pi. Do not show it in the agent list.
  - Start a new Chatter session. Do not keep the open chat on Agent Pi.
  - Header banner: the desktop environment is unavailable.
- **🔷** That notice is `Banner.show` on `window.notification`.
  - **ℹ️** `Banner.show` is the dismissible header banner (`Adw.Banner` on desktop, `tool_error_banner`).
  - **ℹ️** `Alert.show` is a modal OK dialog. This notice is not that dialog.
  - **ℹ️** `ActivityBanner` is scan and index progress. Not this notice.
  - **ℹ️** Android today turns both `Banner.show` and `Alert.show` into `Adw.AlertDialog`. This notice still uses `Banner.show`. Android must show that as a banner, not a dialog.

---

## Phase 4 — History when Agent Pi is off (`⏳`)

- **🔷** `⏳` An Agent Pi session cannot be restored while Agent Pi is not in the agent list.
- **🔷** The history row stays in the list. It shows the agent name and "disabled". Tapping it does nothing until that agent is available again.
- **ℹ️** The row today is the title plus `display_info` (model and message count). `agent_name` is stored and not shown (`SessionPlaceholder.display_info`, `HistoryBrowser`).
- **ℹ️** `Manager.load_sessions` drops a row whose model is missing (`find_model_by_name` returns null). A missing agent is different: it rewrites `agent_name` to `just-ask` in memory only and still lists the row. That rewrite is the bug. Do not hide the row, and do not retarget it to Chatter.

---

## Phase 5 — Phone bottom bar (`⏳`)

The phone does not keep a left-rail toggle and does not split the screen. The bottom bar (`OLLMchatGtk.ChatBar`) already holds the browser toggle and the model selector. That row is where you change what fills the screen.

- **ℹ️** Phone `schedule_pane_update(true)` replaces the chat: `chat_widget.view_stack` child `"pane"`. `false` puts `"chat"` back. That is the same swap the browser globe uses.
- **ℹ️** Today `ChatBar.tool_button_box` is on the left and the model dropdown follows it. Moving the pickers to the right is Phase 8.
- **🔷** `⏳` Three pickers: browser, text editor, chat.
- **🔷** One of them is the visible page. Picking another replaces it. Chat, browser, and the editor each take the whole content area.
- **🔷** While the session is running, the chat picker shows the thinking mark, even if the editor or the browser is the visible page. That is how you see that chat is occurring without leaving the file.
- **🔷** The mark is `weather-fog-symbolic`, the thinking icon on the model dropdown (`libollmchatgtk/List/ModelUsageFactory.vala`). It is three wavy lines. Each frame hides lines: show one, then two, then three, then back to one. Not a spinner.
- **ℹ️** The icon is one Adwaita symbolic, not three files. Extract each wavy line into its own icon (the other lines hidden) and cycle those on the chat picker while `session.is_running`.
- **🔷** When the session is idle, the chat picker is a speech bubble. The thinking icon is only the running state.

---

## Phase 6 — Editor chrome (`⏳`)

When the text editor is the visible page, the column is four bands, top to bottom.

- **🔷** `⏳` The normal OLLMchat header stays on top.
- **🔷** Under that, a second bar: project dropdown and file dropdown. Those already exist inside the coder (`ProjectDropdown`, `FileDropdown`).
- **🔷** Then the text area.
- **🔷** When review is active, the review bar sits at the bottom of the text area. Not in this slice unless review is already showing there on desktop.
- **ℹ️** Desktop review footer is `liboccoder/Diff/ReviewBar.vala`. The phone reuses that band. It does not invent a second review widget.

---

## Phase 7 — Tablet bar (`⏳`)

- **ℹ️** Tablet `schedule_pane_update` only shows or hides the right column. Chat stays on the left ([`8.2.8.8`](RPC-8.2.8.8-android-phone-tablet-pane.md)).
- **🔷** `⏳` Browser and code are the same kind of choice as on the phone. Those two buttons sit on the right of the left column's bottom bar, not on its left edge.
- **🔷** Selecting Agent Pi still fills the right column with the editor. The buttons choose browser vs code in that column.
- **ℹ️** Moving the model selector fully left, on phone and tablet together, is Phase 8. This phase only moves browser and code to the right of that left-column bar.

---

## Phase 8 — Pickers on the right (`⏳`)

- **🔷** `⏳` Later, the same bar on phone and tablet: pickers sit on the right, and the model selector moves fully left.
  - Phone: three pickers (browser, text editor, chat).
  - Tablet: two pickers (browser, code). Chat is the left column, so it is not a picker.

---

## LLM notes

- **🚫** Code Assistant and Skill Runner on Android.
- **🚫** Changing Linux Agent Pi registration.
- **🚫** A left-rail editor toggle.
- **🚫** A phone split (editor over a short chat strip) and a draggable sash (`Gtk.Paned`).
- **🚫** A spinner on the chat picker. Running is `weather-fog-symbolic`, one wavy line at a time. Idle is a speech bubble.
- **🚫** More than one desktop environment. That is parent Phase 11.
- **🚫** An ICMP ping. Reachability is `RPC-Daemon.hello`.
- **🚫** Waiting the default 120s RPC timeout when the file server is off-network.
- **🚫** `Alert.show` for desktop-environment unavailable.
- **🚫** Turning the saved connection to `DISABLED` because one startup hello missed. That miss is `UNREACHABLE`.
- **🚫** Rewriting a missing `agent_name` to `just-ask`, or hiding that history row.
