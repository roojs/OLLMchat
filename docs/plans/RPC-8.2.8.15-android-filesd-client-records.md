# 8.2.8.15 — Phone records for several desktops

**Status:** proposed

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.** The prefix 1.0 summary is updated only when this sub-plan is done and archived.

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md) Phase 13

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`.

---

## Purpose

- **🔷** The phone keeps a record for each desktop it has paired. Adding another one leaves the earlier records in place.
- **🔷** Home and office are both stored. Each is a desktop the phone has already reached on that network.
- **🔷** The records are a map on `Config2`, keyed by `server_id`.
- **🔷** Only one record is enabled. Enabling one disables the others. Pairing a second desktop disables the first and connects the one just paired.
- **🔷** At startup, try the records that are not disabled. The first one that connects is the live desktop. The others stay disabled.
- **ℹ️** Certificates already live in one directory per `server_id` under the user data directory. `FilesdClient.remove()` deletes that directory.
- **ℹ️** Pairing one desktop is `FilesdClient.try_connection`. The regression is `meson test -C build test-rpc-filesd-pair-flow`.

---

## Current behaviour

- **ℹ️** `Config2.filesd_client` is one object. JSON key `filesd-client`. Empty `url` means none.
- **ℹ️** `ConnectionsPage.render_file_connection` hides **Remote Desktop Connection** once that url is set, and draws one row.
- **ℹ️** A successful add writes that one object and, on Android, calls `OllmchatWindow.reconnect`.
- **ℹ️** `OllmchatWindow.reconnect` and `probe_addresses` read `config.filesd_client` only.
- **ℹ️** `Agent.Dropdown.wire` and `History.Manager` listen to the `filesd_client` object captured at startup. Replacing that property does not move those listeners.

---

## Proposed behaviour

- **🔷** The connections list shows every stored desktop. The add button stays available.
- **🔷** The phone's existing desktop still loads. A config that only has `filesd-client` remains that one record.
- **🔷** `filesd_client` is the enabled record, and that same object is the map entry for its `server_id`.
- **🔷** The user turns a row on to connect that desktop, or off to drop it. Turning one on turns every other row off.
- **🔷** `Config2` emits one signal, `filesd_changed`, with the server id and the new state. Listeners subscribe once. They do not connect or disconnect a watch on the desktop object.

---

## Phase 1 — Store every record

### 1. `libollmchat/Settings/FilesdClient.vala` — class docblock

**Why:** The class text says the connections tab holds one row.

**Where:** The docblock on `class FilesdClient`.

#### Remove

```vala
	 * JSON key ''filesd_client'' on {@link Config2}. At most one row in the
	 * Connections tab; empty ''url'' means not configured.
```

#### Replace with

The record is one desktop. Empty `url` means that record is not configured. Several records live in {@link Config2.filesd_clients}.

```vala
	 * One stored desktop. JSON for the connected desktop is
	 * ''filesd-client'' on {@link Config2}. Other stored desktops
	 * are ''filesd-clients'', keyed by {@link server_id}. Empty
	 * ''url'' means this record is not configured.
```

### 2. `libollmchat/Settings/Config2.vala` — `filesd_clients`

**Why:** The connected desktop stays `filesd_client`. The other records need a place to live.

**Where:** Immediately after the `filesd_client` property.

#### Add

After the `filesd_client` property, before the usage-types registry.

```vala
		/**
		 * Stored desktops other than the connected one, keyed by
		 * {@link FilesdClient.server_id}.
		 *
		 * The connected desktop is {@link filesd_client} and is also
		 * present here under its server id once that id is known.
		 */
		public Gee.Map<string, FilesdClient> filesd_clients {
			get; set; default = new Gee.HashMap<string, FilesdClient>();
		}

		/**
		 * A stored desktop's state changed.
		 *
		 * @param server_id the desktop id
		 * @param state the state just stored on that record
		 */
		public signal void filesd_changed(string server_id, FilesdClient.State state);
```

### 3. `libollmchat/Settings/Config2.vala` — `serialize_property`

**Why:** Save the map beside the existing connected object so a current config file still has `filesd-client`.

**Where:** `serialize_property`, the `filesd-client` case.

#### Add

Immediately after the `filesd-client` case.

```vala
				case "filesd-clients":
					var obj = new Json.Object();
					foreach (var entry in this.filesd_clients.entries) {
						obj.set_member(entry.key, Json.gobject_serialize(entry.value));
					}
					var node = new Json.Node(Json.NodeType.OBJECT);
					node.set_object(obj);
					return node;
```

### 4. `libollmchat/Settings/Config2.vala` — `deserialize_property`

**Why:** Read `filesd-clients` back into the map.

**Where:** `deserialize_property`, immediately before the `windows` case.

#### Add

```vala
				case "filesd-clients":
					if (property_node.get_node_type() != Json.NodeType.OBJECT) {
						break;
					}
					var obj = property_node.get_object();
					obj.foreach_member((object, key, node) => {
						var client = Json.gobject_deserialize(
							typeof(FilesdClient), node) as FilesdClient;
						if (client == null) {
							return;
						}
						this.filesd_clients.set(key, client);
					});
					value = Value(typeof(Gee.Map));
					value.set_object(this.filesd_clients);
					return true;
```

### 5. `libollmchat/Settings/Config2.vala` — `load`

**Why:** An old file has only `filesd-client`. That object becomes the one map entry, and it stays the same object as `filesd_client`.

**Where:** `load`, immediately after `loaded_config.loaded = true`, before `return loaded_config`.

#### Add

```vala
				if (loaded_config.filesd_client.server_id != "") {
					loaded_config.filesd_clients.set(
						loaded_config.filesd_client.server_id,
						loaded_config.filesd_client);
				}
				foreach (var entry in loaded_config.filesd_clients.entries) {
					var stored = entry.value;
					stored.notify["state"].connect(() => {
						loaded_config.filesd_changed(stored.server_id, stored.state);
					});
				}
```

---

## Phase 2 — Show every record

### 6. `ollmapp/SettingsDialog/ConnectionsPage.vala` — row field

**Why:** One field cannot hold several expanders.

**Where:** The `file_connection_row` field.

#### Remove

```vala
		private FileConnectionRow? file_connection_row;
```

#### Replace with

```vala
		private Gee.HashMap<string, FileConnectionRow> file_connection_rows {
			get; set; default = new Gee.HashMap<string, FileConnectionRow>();
		}
```

### 7. `ollmapp/SettingsDialog/ConnectionsPage.vala` — `render_file_connection`

**Why:** Draw one row per stored desktop, and stop hiding the add button after the first.

**Where:** The whole `render_file_connection` method.

#### Remove

```vala
		private void render_file_connection()
		{
			this.add_file_btn.visible =
				this.dialog.app.config.filesd_client.url.strip() == "";
			if (this.file_connection_row != null) {
				this.file_connection_row.expander.unparent();
				this.file_connection_row = null;
			}
			var client = this.dialog.app.config.filesd_client;
			if (client.url.strip() == "") {
				return;
			}
			this.file_connection_row = new FileConnectionRow(client, this.dialog.parent);
			this.arrow(this.file_connection_row.expander, this.file_connection_row.expander);
			this.file_connection_row.remove_requested.connect(() => {
				var was_live = client.state == FilesdClient.State.LIVE || 
					client.state == FilesdClient.State.SOCKET;
					
				client.remove();
#if !ANDROID
				var row = this.file_connection_row;
#endif
				/* Agent.Dropdown listens to this object. Mutating its state
				 * notifies the filter before the connection data is cleared. */
				client.state = FilesdClient.State.REQUESTED;
				client.url = "";
				client.addresses = "";
				client.server_id = "";
				this.render_file_connection();
				this.dialog.app.config.save();
				if (!was_live) {
					return;
				}
#if ANDROID
				/* Android has no local file daemon to reconnect after removal.
				 * Drop the remote RPC state and return to Chatter. */
				var data_dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat");
				this.dialog.parent.project_manager.replace_rpc(
					new OLLMrpc.Client(data_dir, "ollmfilesd.pid", "ollmfilesd.sock"));
				var empty = this.dialog.parent.history_manager.create_new_session();
				empty.project_path = this.dialog.parent.history_manager.session.project_path;
				empty.agent_name = "chatter";
				this.dialog.parent.chat_widget.switch_to_session.begin(empty);
#else
				row.reconnect.begin(false);
#endif
			});
			Adw.ExpanderRow? insert_after = null;
			foreach (var row in this.rows.values) {
				insert_after = row.expander;
			}
			if (insert_after != null) {
				this.boxed_list.insert_child_after(
					this.file_connection_row.expander, insert_after);
				return;
			}
			this.boxed_list.append(this.file_connection_row.expander);
		}
```

#### Replace with

The add button stays up. Each map entry with a url gets a row. Removing the connected desktop still drops Android back to Chatter. Removing any other record only deletes that record.

```vala
		private void render_file_connection()
		{
			foreach (var old in this.file_connection_rows.values) {
				old.expander.unparent();
			}
			this.file_connection_rows.clear();
			Adw.ExpanderRow? insert_after = null;
			foreach (var connection_row in this.rows.values) {
				insert_after = connection_row.expander;
			}
			foreach (var entry in this.dialog.app.config.filesd_clients.entries) {
				var client = entry.value;
				if (client.url.strip() == "") {
					continue;
				}
				var file_row = new FileConnectionRow(client, this.dialog.parent);
				this.file_connection_rows.set(entry.key, file_row);
				this.arrow(file_row.expander, file_row.expander);
				file_row.remove_requested.connect(() => {
					this.on_remove_desktop(file_row);
				});
				if (insert_after != null) {
					this.boxed_list.insert_child_after(file_row.expander, insert_after);
				} else {
					this.boxed_list.append(file_row.expander);
				}
				insert_after = file_row.expander;
			}
		}

		/**
		 * Drop one stored desktop from the list.
		 *
		 * Removing the connected desktop also leaves the remote RPC.
		 *
		 * @param file_row the row whose Remove button was pressed
		 */
		private void on_remove_desktop(FileConnectionRow file_row)
		{
			var client = file_row.client;
			var was_live = client == this.dialog.app.config.filesd_client
				&& (client.state == FilesdClient.State.LIVE
					|| client.state == FilesdClient.State.SOCKET);
			var key = client.server_id;
			client.remove();
			this.dialog.app.config.filesd_clients.unset(key);
			client.state = FilesdClient.State.REQUESTED;
			client.url = "";
			client.addresses = "";
			client.server_id = "";
			if (client == this.dialog.app.config.filesd_client) {
				this.dialog.app.config.filesd_client = new FilesdClient();
			}
			this.render_file_connection();
			this.dialog.app.config.save();
			if (!was_live) {
				return;
			}
#if ANDROID
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			this.dialog.parent.project_manager.replace_rpc(
				new OLLMrpc.Client(data_dir, "ollmfilesd.pid", "ollmfilesd.sock"));
			var empty = this.dialog.parent.history_manager.create_new_session();
			empty.project_path =
				this.dialog.parent.history_manager.session.project_path;
			empty.agent_name = "chatter";
			this.dialog.parent.chat_widget.switch_to_session.begin(empty);
#else
			file_row.reconnect.begin(false);
#endif
		}
```

### 8. `ollmapp/SettingsDialog/ConnectionsPage.vala` — add dialog `dialog_closed`

**Why:** A second pair must be stored. It must not wipe the desktop already in `filesd_client`.

**Depends on:** Phase 1.

**Where:** `dialog_closed` on `add_file_dialog`, the block that writes `filesd_client` after a non-null `registered_url`.

#### Remove

```vala
				this.dialog.app.config.filesd_client.url = this.add_file_dialog.registered_url;
				this.dialog.app.config.filesd_client.addresses =
					this.add_file_dialog.registered_addresses;
				this.dialog.app.config.filesd_client.server_id =
					this.add_file_dialog.server_id;

				//FIXME =- this ifdef does not make sense - why not do the same thing on desktop
#if ANDROID
				/* The Android pairing hello uses a temporary TLS stream.
				 * Connect the persistent RPC before exposing Agent Pi. */
				this.dialog.app.config.filesd_client.state = FilesdClient.State.ENABLED;
#else
				this.dialog.app.config.filesd_client.state = FilesdClient.State.SOCKET;
#endif
				this.dialog.app.config.save();
				this.render_file_connection();
#if ANDROID
				this.dialog.parent.reconnect.begin();
#endif
```

#### Replace with

The desktop just paired is stored enabled and becomes `filesd_client`. Every other record is disabled. Android reconnects that desktop.

```vala
				var client = this.dialog.app.config.filesd_client;
				if (client.server_id != "") {
					client = new FilesdClient();
				}
				client.url = this.add_file_dialog.registered_url;
				client.addresses = this.add_file_dialog.registered_addresses;
				client.server_id = this.add_file_dialog.server_id;
				client.notify["state"].connect(() => {
					this.dialog.app.config.filesd_changed(client.server_id, client.state);
				});
#if ANDROID
				client.state = FilesdClient.State.ENABLED;
#else
				client.state = FilesdClient.State.SOCKET;
#endif
				foreach (var entry in this.dialog.app.config.filesd_clients.entries) {
					if (entry.key == client.server_id) {
						continue;
					}
					if (entry.value.state == FilesdClient.State.REQUESTED) {
						continue;
					}
					entry.value.state = FilesdClient.State.DISABLED;
				}
				this.dialog.app.config.filesd_clients.set(client.server_id, client);
				this.dialog.app.config.filesd_client = client;
				this.dialog.app.config.save();
				this.render_file_connection();
#if ANDROID
				this.dialog.parent.reconnect.begin();
#endif
```

### 9. `ollmapp/SettingsDialog/FileConnectionRow.vala` — Enabled switch

**Why:** Turning a row on selects that desktop. Every other record is disabled, then `reconnect` runs against `filesd_client`.

**Where:** The Enabled switch handler, immediately after the state is written and before `this.win.app.config.save()`.

#### Add

After the `if (this.enabled_switch.active)` / `else if` that sets this row's state, before `this.win.app.config.save()`.

```vala
				if (this.client.state != FilesdClient.State.DISABLED
					&& this.client.state != FilesdClient.State.REQUESTED) {
					foreach (var entry in this.win.app.config.filesd_clients.entries) {
						if (entry.value == this.client) {
							continue;
						}
						if (entry.value.state == FilesdClient.State.REQUESTED) {
							continue;
						}
						entry.value.state = FilesdClient.State.DISABLED;
					}
					this.win.app.config.filesd_client = this.client;
				}
```

---

## Phase 3 — First desktop that connects

### 10. `ollmapp/android/OllmchatWindow.vala` — `initialize_client`

**Why:** Startup tries each desktop the user has not switched off. The first hello that succeeds is the live one, and it is the only enabled record.

**Depends on:** Phase 1.

**Where:** `initialize_client`, the block that sets `is_desktop_connected` from `config.filesd_client` and calls `probe_addresses`.

#### Remove

```vala
			if (config.filesd_client.addresses != ""
				&& (config.filesd_client.state == FilesdClient.State.ENABLED
					|| config.filesd_client.state == FilesdClient.State.LIVE
					|| config.filesd_client.state == FilesdClient.State.UNREACHABLE
					|| config.filesd_client.state == FilesdClient.State.SOCKET)) {
				is_desktop_connected = true;
				this.startup_status_label.label = "Checking desktop environment…";
				is_desktop_available = yield this.probe_addresses(config);
				this.startup_status_label.label = "Opening chat…";
			}
```

#### Replace with

Skip `DISABLED` and `REQUESTED`. On the first successful probe, that record becomes `filesd_client` and every other record is disabled. If none connect, `filesd_client` stays the last one tried so the existing give-up still runs.

```vala
			foreach (var entry in config.filesd_clients.entries) {
				var candidate = entry.value;
				switch (candidate.state) {
					case FilesdClient.State.DISABLED:
					case FilesdClient.State.REQUESTED:
						continue;
					default:
						break;
				}
				if (candidate.addresses == "") {
					continue;
				}
				config.filesd_client = candidate;
				is_desktop_connected = true;
				this.startup_status_label.label = "Checking desktop environment…";
				is_desktop_available = yield this.probe_addresses(config);
				if (!is_desktop_available) {
					continue;
				}
				foreach (var other in config.filesd_clients.entries) {
					if (other.value == candidate) {
						continue;
					}
					if (other.value.state == FilesdClient.State.REQUESTED) {
						continue;
					}
					other.value.state = FilesdClient.State.DISABLED;
				}
				break;
			}
			if (is_desktop_connected) {
				this.startup_status_label.label = "Opening chat…";
			}
```

### 11. One signal for every desktop

**Why:** Listeners need the server id and the state. They subscribe once to `Config2`. Swapping a `notify["state"]` watch when the enabled object changes stacks handlers.

**Where:** `History.Manager`, the `filesd_client.notify["state"]` connection. `Agent.Dropdown.wire`, the same kind of connection. The agent-pi filter still reads the enabled record.

#### Remove — `libollmchat/History/Manager.vala`

```vala
			this.config.filesd_client.notify["state"].connect(() => {
				GLib.debug("filesd state=%s session=%s",
					this.config.filesd_client.state.to_string(),
					this.session.agent_name);
```

#### Replace with

Ignore a desktop that is not the enabled one. Use the state from the signal.

```vala
			this.config.filesd_changed.connect((server_id, state) => {
				if (server_id != this.config.filesd_client.server_id) {
					return;
				}
				GLib.debug("filesd state=%s session=%s",
					state.to_string(),
					this.session.agent_name);
```

The `LIVE` test in that same handler:

#### Remove

```vala
				if (this.config.filesd_client.state != Settings.FilesdClient.State.LIVE
```

#### Replace with

```vala
				if (state != Settings.FilesdClient.State.LIVE
```

#### Replace with — `ollmapp/Agent/Dropdown.vala`

The filter reads the enabled record when it runs.

```vala
				switch (this.host.history_manager.config.filesd_client.state) {
```

`wire` subscribes once:

```vala
			this.host.history_manager.config.filesd_changed.connect((server_id, state) => {
				if (server_id != this.host.history_manager.config.filesd_client.server_id) {
					return;
				}
```

The rest of that handler is the body already on `filesd_client.notify["state"]`. The debug line prints `state`.

---

## LLM notes

- **ℹ️** A disabled record is not tried at the next startup. The user's off switch stays off.
- **ℹ️** The online desktop through the proxy stays out of this plan.
- **ℹ️** `test-rpc-filesd-pair-flow` does not open the connections list. A second record needs a separate check after the code lands.
