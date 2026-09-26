# 8.2.8.5 — DONE — Remote file connection: desktop takeover, Check, live toggle

**Status:** **DONE** ✅ — Phases C and D in tree. Android takeover is [`RPC-8.2.8.6`](RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md). Phone/tablet pane is [`RPC-8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md).

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](../RPC-8.2.8-filesd-connections-ui.md)

**Split from:** [`RPC-8.2.8.2-DONE-filesd-android-file-connection.md`](RPC-8.2.8.2-DONE-filesd-android-file-connection.md) Phase 2. UI half; the library half is [`RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md`](RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md).

**Depends on:**

- [`RPC-8.2.8.4`](RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md) — `OLLMrpc.Client.http`, safe `disconnect()`, `ProjectManager.replace_rpc` + `notification`
- `8.2.8.2` Phase 1 (in tree) — `Config2.filesd_client`, `Transport.Cert`, `FileConnectionAdd`, `FileConnectionRow`, `ConnectionsPage.render_file_connection`
- [`RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md`](RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md) — desktop Accept so a device can become `status = 1`

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Landed (tree)

- `ollmapp/Window.vala` — `initialize_client()` HTTPS `replace_rpc` when `url` + `enabled` + `approved`
- `ollmapp/SettingsDialog/FileConnectionRow.vala` — `check()`, `reconnect(bool remote)`, Enabled switch, `OllmchatWindow` at construct
- `ollmapp/SettingsDialog/ConnectionsPage.vala` — row construct with window; **Remove** falls back to local when the remote was live

---

## Purpose

- **🔷** **Check** on the file-connection row asks the remote `ollmfilesd` whether this device is approved.
  - Success sets `filesd_client.approved = true`, saves config, updates the row to **Active**, and goes live if **Enabled**.
  - Failure leaves **Requested** and shows the server message in the row subtitle.
- **🔷** When `filesd_client.url != ""` **and** `enabled` **and** `approved`, `OLLMfiles.ProjectManager` talks to the remote file server over **HTTPS** with the device client cert.
  - **Linux desktop:** remote **takes over** the local Unix `ollmfilesd` at startup.
  - `enabled == false` (or not approved): local Unix path wins, unchanged.
- **🔷** `enabled` toggle turns the remote connection on or off **live**: the running `ProjectManager` drops its client, connects the other one, reloads projects, restores the active project/file.
- **🔷** **Agent Pi** is available when the file connection is live.
  - **Linux:** Agent Pi stays registered as today (local daemon or remote both satisfy it).
  - **Android:** host surface is [`RPC-8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md). Register is [`8.2.8`](../RPC-8.2.8-filesd-connections-ui.md) Phase 10.
- **🔷** `FileConnectionRow(FilesdClient, OllmchatWindow)` — window at construct. **Check** and **Enabled** are wired on the row, not on `ConnectionsPage`.
- **🔷** `FileConnectionRow.check()` / `reconnect(bool remote)` — use `this.win` (config, `project_manager`, notifications).
- **ℹ️** Operator nginx doc: [`docs/filesd-behind-nginx-proxy.md`](../../filesd-behind-nginx-proxy.md).

---

## Current behaviour

- **ℹ️** `ConnectionsPage.render_file_connection` wires **Check** to `GLib.critical("file connection check not implemented")`; `FileConnectionRow.check_button` is `sensitive = false`; the **Enabled** switch is a constructor local.
- **ℹ️** `ollmapp/Window.vala` `initialize_client` creates the `ProjectManager`, connects with `RPC-Daemon.hello` + `ClientBoot`, then registers Code Assistant, Agent Pi, Skill Runner unconditionally.
- **ℹ️** Startup load sequence lives in `OLLMcoder.AgentPi.Factory.activate`: `client.project.load_start`, `rpc_load_projects_from_db()`, `restore_active_state(win_cfg.project, win_cfg.file)`, `apply_manager_state()`, `client.project.load_end`. `SourceView` re-runs `apply_manager_state` on `active_project_changed`.
- **ℹ️** Android `android_poc` links `ollmchat`, `ollmchatgtk`, reduced `occoder` (Skill + SkillSet only). `OLLMfiles.ProjectManager` is a stub in `ollmapp/android/AndroidToolTypes.vala`; libocfiles is not in the Android `subdir()` list.
- **ℹ️** `OLLMcoder.AgentPi.Factory.activate` casts the window to `OLLMchat.ChatDesktopInterface` and builds `OLLMcoder.SourceView`. Both are desktop-only today.

---

## Design decisions

- **🔷** Check probe = `RPC-Daemon.hello` (`"is"`, `1`, `"ollmchat"`) through `Transport.HttpClient` with the device leaf.
  - Approved cert: hello returns the `Daemon` object.
  - Pending cert: gate replies `INVALID_REQUEST` "certificate not registered" and `HttpClient.call` throws.
- **💩** `RPC-Daemon.hello` result is not read by `check` (only success vs error matters).
- **💩** Device leaf literals (`client.pem`, `client-key.pem`, `cn = "ollmchat-device"`, `product_ca_resource = true`, dir `~/.local/share/ollmchat`) are repeated at `FileConnectionAdd`, `Window` startup, and `FileConnectionRow.check` / `reconnect`. No fourth helper unless you want one.
- **🔷** `FileConnectionRow` takes `OllmchatWindow` at construct (`this.win`). That is the live connection (`project_manager`, `notification`, `app.config`). Check and Enabled wire themselves in the constructor, same pattern as `FileConnectionAdd.request.begin()`.
- **💩** Unsaved buffer guard lives on the row (`this.win.project_manager.active_file`); refuse the toggle, flip the switch back, message in the subtitle.
- **💩** Agent Pi mid-run is **not** guarded: with 8.2.8.4 §0 its in-flight RPC fails with "Client: disconnected" instead of aborting the app. Acceptable for this plan; see **Follow-ups**.
- **🔷** `Cert.ensure()` does **not** throw (in tree). Missing/unreadable leaf PEMs are recreated; a broken install is `GLib.error` and aborts. Same construction as `FileConnectionAdd.request()`: `tls.ensure()` then `tls.certificate` / `tls.trust` on `HttpClient`.
- **💩** A remote connect failure in `reconnect` disables the file connection, raises `Alert.show`, and falls back to the local daemon (one recursive `reconnect(false)`). Not silent: the alert and the row subtitle both say so.
- **💩** Agent Pi contract reading: `8.2.8.2` says register Agent Pi only when the remote connection is live. On Linux that would remove Agent Pi from every local-daemon user, so this plan keeps the Linux registration unchanged and applies the gate on Android ([`8.2.8`](../RPC-8.2.8-filesd-connections-ui.md) Phase 10). Confirm or veto.

---

## Phase C — Desktop takeover (`ollmapp/Window.vala`) **✅**

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `ollmapp/Window.vala` — `initialize_client()`: remote client when approved + enabled

**Why:** Linux takeover contract. Remote replaces the local Unix daemon only when all three flags hold; otherwise the constructor's Unix client stays in place.
**Where:** `initialize_client()`, the two lines that create `project_manager` and its `buffer_provider` (after `yield this.history_manager.connection_models.refresh();`).
**Depends on:** 8.2.8.4 §2, §3.

ℹ️ This is the never-connected case of `replace_rpc`: the constructor's Unix client has not run `connect()`, so `disconnect()` is a no-op and the state clears are on empty collections.
ℹ️ Same `Cert` / `HttpClient` construction as `FileConnectionAdd.vala` `request()` (`tls.ensure()` then `tls.certificate` / `tls.trust` in the `HttpClient` initializer).
ℹ️ The later `rpc.connect(hello, new OLLMrpc.ClientBoot())` line is unchanged: the HTTPS branch in 8.2.8.4 §2 returns before `ClientBoot` is consulted, so no daemon spawn happens for remote.

#### Remove

```vala
			this.project_manager = new OLLMfiles.ProjectManager();
			this.project_manager.buffer_provider = new OLLMcoder.BufferProvider();
```

#### Replace with

```vala
			this.project_manager = new OLLMfiles.ProjectManager();
			this.project_manager.buffer_provider = new OLLMcoder.BufferProvider();
			if (config.filesd_client.url != "" && config.filesd_client.enabled
				&& config.filesd_client.approved) {
				var tls = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat"),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
					product_ca_resource = true,
				};
				tls.ensure();
				var http = new OLLMrpc.Transport.HttpClient(config.filesd_client.url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				this.project_manager.replace_rpc(
					new OLLMrpc.Client("", "", config.filesd_client.url) { http = http }
				);
			}
```

ℹ️ The swap happens before the existing `this.project_manager.rpc.connect(…)` line further down, so it picks up the HTTPS client. The notification hook is already on the manager after 8.2.8.4 §3b.
ℹ️ Agent Pi registration further down (`new OLLMcoder.AgentPi.Factory(this.project_manager)`) is untouched on Linux (see **Design decisions**).

---

## Phase D — Check + live toggle (Connections tab) **✅**

### 2. `ollmapp/SettingsDialog/FileConnectionRow.vala` — `check` / `reconnect`; enable **Check**; expose the switch

**Why:** Check, Enabled, and the live swap are row behaviour. Pass `OllmchatWindow` at construct so they do not round-trip through `ConnectionsPage`. The page only keeps **Remove**.
**Where:** constructor signature + `this.win`; drop `enabled_changed`; constructor switch / Check button; `check` / `reconnect` before the class closing brace.
**Depends on:** 8.2.8.4 §0, §3, §3a–§3e; `Transport.Cert` / `HttpClient` from `8.2.8.2` Phase 1.

##### Part 1 — properties + constructor

#### Remove

```vala
		public signal void enabled_changed(bool enabled);
```

#### Add — after `public Gtk.Button check_button { get; private set; }`

```vala
		public Gtk.Switch enabled_switch { get; private set; }
		public Gtk.Label status_label { get; private set; }
		public OLLMchat.Settings.FilesdClient client { get; private set; }
		public OllmchatWindow win { get; private set; }
```

#### Remove

```vala
		public FileConnectionRow(OLLMchat.Settings.FilesdClient client)
		{
```

#### Replace with

```vala
		public FileConnectionRow(OLLMchat.Settings.FilesdClient client, OllmchatWindow win)
		{
			this.client = client;
			this.win = win;
```

#### Remove

```vala
			status_row.add_suffix(new Gtk.Label(subtitle) {
				xalign = 1
			});
```

#### Replace with

```vala
			this.status_label = new Gtk.Label(subtitle) {
				xalign = 1
			};
			status_row.add_suffix(this.status_label);
```

#### Remove

```vala
			var enabled_switch = new Gtk.Switch() {
				active = client.enabled,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var enabled_row = new Adw.ActionRow() {
				title = "Enabled"
			};
			enabled_row.add_suffix(enabled_switch);
			enabled_switch.notify["active"].connect(() => {
				this.enabled_changed(enabled_switch.active);
			});
```

#### Replace with

```vala
			this.enabled_switch = new Gtk.Switch() {
				active = client.enabled,
				vexpand = false,
				valign = Gtk.Align.CENTER
			};
			var enabled_row = new Adw.ActionRow() {
				title = "Enabled"
			};
			enabled_row.add_suffix(this.enabled_switch);
			this.enabled_switch.notify["active"].connect(() => {
				if (this.enabled_switch.active == this.client.enabled) {
					return;
				}
				var manager = this.win.project_manager;
				if (manager.active_file != null && manager.active_file.buffer.is_modified) {
					this.expander.subtitle = "Save or discard changes to "
						+ GLib.Path.get_basename(manager.active_file.path) + " first";
					this.enabled_switch.active = !this.enabled_switch.active;
					return;
				}
				this.client.enabled = this.enabled_switch.active;
				this.win.app.config.save();
				if (!this.client.approved) {
					return;
				}
				this.reconnect.begin(this.enabled_switch.active);
			});
```

ℹ️ The first `if` makes the switch flip-back re-entrant-safe: setting `enabled_switch.active` fires `notify["active"]` again with a value that matches `client.enabled`.
ℹ️ `!this.client.approved`: a **Requested** device is not live in either state, so only the flag changes (`check` goes live when it later succeeds).

#### Remove

```vala
			this.check_button = new Gtk.Button.with_label("Check") {
				sensitive = false,
				tooltip_text = "Check whether the desktop has approved this device (Phase 2)"
			};
```

#### Replace with

```vala
			this.check_button = new Gtk.Button.with_label("Check") {
				tooltip_text = "Ask the file server whether the desktop has approved this device"
			};
			this.check_button.clicked.connect(() => {
				this.check.begin();
			});
```

##### Part 2 — `check()`

#### Add — before the class closing brace

Ask the remote file server whether this device is approved. `yield http.call`; on success set `approved`, save, update the subtitle; if Enabled, `yield this.reconnect(true)`.

```vala
		/**
		 * Ask the remote file server whether this device is approved.
		 *
		 * Sends ''RPC-Daemon.hello'' with the device client certificate.
		 * On success sets {@link OLLMchat.Settings.FilesdClient.approved},
		 * saves config, and if Enabled calls {@link reconnect} to the remote
		 * server.
		 */
		public async void check()
		{
			var tls = new OLLMrpc.Transport.Cert() {
				dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat"),
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "ollmchat-device",
				product_ca_resource = true
			};
			tls.ensure();
			var http = new OLLMrpc.Transport.HttpClient(this.client.url) {
				bin_body = true,
				tls_certificate = tls.certificate,
				tls_database = tls.trust
			};
			this.check_button.sensitive = false;
			try {
				yield http.call(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				});
			} catch (GLib.Error e) {
				GLib.debug("file connection check: %s", e.message);
				this.check_button.sensitive = true;
				this.expander.subtitle = "Requested: " + e.message;
				return;
			}
			this.client.approved = true;
			this.win.app.config.save();
			this.expander.subtitle = "Active";
			this.status_label.label = "Active";
			this.check_button.sensitive = true;
			if (!this.client.enabled) {
				return;
			}
			yield this.reconnect(true);
		}
```

ℹ️ A device that was already **Enabled** while **Requested** goes live the moment **Check** succeeds; no restart. The page does not re-render the row.

##### Part 3 — `reconnect(bool remote)`

#### Add — after `check()`, still before the class closing brace

Point `this.win.project_manager` at the remote file server or back at the local Unix daemon. Builds the `OLLMrpc.Client`, `replace_rpc`, `RPC-Daemon.hello`, reload projects, restore active file.

```vala
		/**
		 * Point the window's {@link OLLMfiles.ProjectManager} at the remote
		 * file server or back at the local Unix daemon, live.
		 *
		 * Builds the client, swaps it in with
		 * {@link OLLMfiles.ProjectManager.replace_rpc}, connects with
		 * ''RPC-Daemon.hello'', reloads projects and restores the window's
		 * active project and file. Progress goes through the window's
		 * ''client.project.load_start'' / ''load_end'' notifications.
		 *
		 * A remote connect failure disables the file connection, reports
		 * it with ''Alert.show'' and falls back to the local daemon (one
		 * recursive call with ''remote = false'').
		 *
		 * @param remote true for HTTPS to this row's URL, false for the local Unix socket
		 */
		public async void reconnect(bool remote)
		{
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var rpc = new OLLMrpc.Client(data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
			if (remote) {
				var tls = new OLLMrpc.Transport.Cert() {
					dir = data_dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
					product_ca_resource = true,
				};
				tls.ensure();
				var http = new OLLMrpc.Transport.HttpClient(this.client.url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				rpc = new OLLMrpc.Client("", "", this.client.url) { http = http };
			}
			this.win.notification(new OLLMrpc.Notification() {
				method = "client.project.load_start"
			});
			this.win.project_manager.replace_rpc(rpc);
			var hello = new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "ollmchat")
			};
			var connected = false;
			if (remote) {
				connected = yield rpc.connect(hello);
			} else {
				connected = yield rpc.connect(hello, new OLLMrpc.ClientBoot());
			}
			if (!connected) {
				this.win.notification(new OLLMrpc.Notification() {
					method = "client.project.load_end"
				});
				this.win.notification(new OLLMrpc.Notification() {
					method = "Alert.show",
					message = (remote ? "File server: " : "Filesystem daemon: ")
						+ rpc.connect_error
				});
				if (!remote) {
					return;
				}
				this.client.enabled = false;
				this.win.app.config.save();
				this.enabled_switch.active = false;
				this.expander.subtitle = "Failed: " + rpc.connect_error;
				yield this.reconnect(false);
				return;
			}
			try {
				yield this.win.project_manager.rpc_load_projects_from_db();
				var win_cfg = this.win.window_config();
				yield this.win.project_manager.restore_active_state(win_cfg.project, win_cfg.file);
			} catch (GLib.Error e) {
				GLib.critical("file server reconnect: %s", e.message);
				this.win.notification(new OLLMrpc.Notification() {
					method = "Alert.show",
					message = "Could not load projects: " + e.message
				});
			} finally {
				this.win.notification(new OLLMrpc.Notification() {
					method = "client.project.load_end"
				});
			}
		}
```

ℹ️ `restore_active_state` emits `active_project_changed`, which `SourceView` already answers with `apply_manager_state.begin()`. `Approvals` refreshes through `review_files` on `activate_project`.
ℹ️ On remote failure the switch flip-back is re-entrant-safe: `client.enabled` is already false, so the constructor's `notify["active"]` handler sees no change.
ℹ️ Unix `Client` is constructed first so both branches share a `var rpc` (no explicit-type local). The unused Unix object on the remote path is only path strings; `connect()` is never called on it.
ℹ️ Do not put `new ClientBoot()` on a ternary arm (`remote ? null : new …`) — Vala codegen / async ctor bug. `if (remote)` / `else` with `new` only in the local-daemon call.
ℹ️ `this.win.window_config()` returns the `Settings.Window` for this window's uuid: same source `AgentPi.Factory.activate` uses for the startup restore.

### 3. `ollmapp/SettingsDialog/ConnectionsPage.vala` — construct the row; **Remove**

**Why:** Check and Enabled are wired on the row. The page passes `this.dialog.parent` at construct and only handles **Remove**.
**Where:** `new FileConnectionRow(…)` and the three lambdas in `render_file_connection()`.
**Depends on:** §2.

##### Part 1 — construct with the window; drop Check / Enabled wiring

#### Remove

```vala
			this.file_connection_row = new FileConnectionRow(client);
```

#### Replace with

```vala
			this.file_connection_row = new FileConnectionRow(client, this.dialog.parent);
```

#### Remove

```vala
			this.file_connection_row.check_button.clicked.connect(() => {
				GLib.critical("file connection check not implemented");
			});
```

#### Remove

```vala
			this.file_connection_row.enabled_changed.connect((enabled) => {
				this.dialog.app.config.filesd_client.enabled = enabled;
				this.dialog.app.config.save();
			});
```

##### Part 2 — **Remove**: back to local when the remote was live

#### Remove

```vala
			this.file_connection_row.remove_requested.connect(() => {
				this.dialog.app.config.filesd_client =
					new OLLMchat.Settings.FilesdClient();
				this.render_file_connection();
				this.dialog.app.config.save();
			});
```

#### Replace with

```vala
			this.file_connection_row.remove_requested.connect(() => {
				var was_live = client.enabled && client.approved;
				var row = this.file_connection_row;
				this.dialog.app.config.filesd_client =
					new OLLMchat.Settings.FilesdClient();
				this.render_file_connection();
				this.dialog.app.config.save();
				if (!was_live) {
					return;
				}
				row.reconnect.begin(false);
			});
```

ℹ️ `row` keeps the `FileConnectionRow` alive after `render_file_connection()` unparents the expander. `reconnect(false)` does not touch the expander. Unsaved-buffer guard is not applied on **Remove**.

---

## Phase E — Android

**➡️** [`RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md`](RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) — `ProjectManager`, HTTPS takeover, full liboccoder.
**➡️** [`RPC-8.2.8.8-DONE-android-phone-tablet-pane.md`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md) — `ChatDesktopInterface`, phone/tablet pane.
**➡️** [`8.2.8`](../RPC-8.2.8-filesd-connections-ui.md) Phase 10 — Android `AgentPi.Factory` register.

---

## Follow-ups (`⏳`, not in this plan)

- **💩** `⏳` Agent Pi guard on the live swap: refuse the toggle while an agent run is in progress (it holds `File` objects from the old server). Today its in-flight RPC fails with `Client: disconnected` and the run errors out; a proper guard needs a "running" query on the agent factory.
- **💩** `⏳` Startup busy label "Connecting to filesystem daemon…" could read "Connecting to file server…" on the remote branch.

---

## Suggested order

1. **✅** [`RPC-8.2.8.4`](RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md) in full (library side)
2. **✅** Phase D — §2–§3 (Check works against a desktop that has accepted the device; toggle swaps live)
3. **✅** Phase C — §1 (Linux takeover at startup; verify local fallback when `enabled` is off)
4. **✔️** Phase E takeover — [`RPC-8.2.8.6`](RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md)
5. **✔️** Phase E pane — [`RPC-8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md)

---

## LLM notes

- **ℹ️** `FileConnectionRow.check` `yield`s `HttpClient.call` with a fresh `Request`; after 8.2.8.4 §1 it goes out with `id == 0`, which the server echoes.
- **ℹ️** Sanctioned new members on `FileConnectionRow`: `enabled_switch`, `status_label`, `client`, `win`, `check`, `reconnect`. Drop `enabled_changed`. Page only wires **Remove**.
- **🚫** `ensure_trust()`, `try/catch` around `Cert.ensure()`, `ConnectionsPage.reconnect_file_server`, `connect_remote` / `device_cert` helpers, `new` on a ternary arm (`remote ? null : new ClientBoot()`), gating Linux Agent Pi on the remote connection, multiple file-server URLs, "restart to apply" wording anywhere.

