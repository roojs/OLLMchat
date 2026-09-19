# 8.2.8.5 — Remote file connection: desktop takeover, Check, live toggle

**Status:** **PROPOSED** — code proposals ready for review

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Split from:** [`RPC-8.2.8.2-DONE-filesd-android-file-connection.md`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md) Phase 2. UI half; the library half is [`RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md`](done/RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md).

**Depends on:**

- [`RPC-8.2.8.4`](done/RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md) — `OLLMrpc.Client.http`, safe `disconnect()`, `ProjectManager.replace_rpc` + `notification`
- `8.2.8.2` Phase 1 (in tree) — `Config2.filesd_client`, `Transport.Cert`, `FileConnectionAdd`, `FileConnectionRow`, `ConnectionsPage.render_file_connection`
- [`RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md`](done/RPC-8.2.8.1-DONE-filesd-desktop-connections-ui.md) — desktop Accept so a device can become `status = 1`

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** **Check** on the file-connection row asks the remote `ollmfilesd` whether this device is approved.
  - Success sets `filesd_client.approved = true`, saves config, re-renders the row as **Active**, and goes live if **Enabled**.
  - Failure leaves **Requested** and shows the server message in the row subtitle.
- **🔷** When `filesd_client.url != ""` **and** `enabled` **and** `approved`, `OLLMfiles.ProjectManager` talks to the remote file server over **HTTPS** with the device client cert.
  - **Linux desktop:** remote **takes over** the local Unix `ollmfilesd` at startup.
  - `enabled == false` (or not approved): local Unix path wins, unchanged.
- **🔷** `enabled` toggle turns the remote connection on or off **live**: the running `ProjectManager` drops its client, connects the other one, reloads projects, restores the active project/file.
- **🔷** **Agent Pi** is available when the file connection is live.
  - **Linux:** Agent Pi stays registered as today (local daemon or remote both satisfy it).
  - **Android:** unlock needs the Android port in **Phase E** (design only here).
- **💩** `⏳` `ConnectionsPage.reconnect_file_server(bool remote)` named async method drives the live swap.
- **ℹ️** Operator nginx doc: [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md).

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
- **💩** `RPC-Daemon.hello` result is not read by the Check handler (only success vs error matters).
- **💩** Device leaf literals (`client.pem`, `client-key.pem`, `cn = "ollmchat-device"`, `product_ca_resource = true`, dir `~/.local/share/ollmchat`) are repeated inline at each of the **four** call sites (`FileConnectionAdd` in tree, Check, `Window`, `reconnect_file_server`). No helper unless you want one; four copies is where I would start wanting one.
- **💩** `ConnectionsPage.reconnect_file_server(bool remote)` is a **named async method** (plan-sanctioned).
  - The sequence is connect → load projects → restore, three awaits, and Vala lambdas cannot be `async`. Inline `.begin` callbacks would nest three deep.
  - `replace_rpc` (8.2.8.4 §3) does the state work; this method does the network work.
- **💩** Unsaved buffer guard: the toggle refuses when `active_file.buffer.is_modified` (message in the row subtitle, switch flipped back).
- **💩** Agent Pi mid-run is **not** guarded: with 8.2.8.4 §0 its in-flight RPC fails with "Client: disconnected" instead of aborting the app. Acceptable for this plan; see **Follow-ups**.
- **💩** TLS setup failure at startup (cannot mint or load the leaf) is **not** silently downgraded to local Unix. It shows the same `tool_error_banner` as a daemon connect failure and returns.
- **💩** A remote connect failure on the live toggle disables the file connection, raises `Alert.show`, and falls back to the local daemon (one recursive `reconnect_file_server(false)`). Not silent: the alert and the row subtitle both say so.
- **💩** Agent Pi contract reading: `8.2.8.2` says register Agent Pi only when the remote connection is live. On Linux that would remove Agent Pi from every local-daemon user, so this plan keeps the Linux registration unchanged and applies the gate on Android (Phase E). Confirm or veto.

---

## Phase C — Desktop takeover (`ollmapp/Window.vala`)

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `ollmapp/Window.vala` — `initialize_client()`: remote client when approved + enabled

**Why:** Linux takeover contract. Remote replaces the local Unix daemon only when all three flags hold; otherwise the constructor's Unix client stays in place.
**Where:** `initialize_client()`, the two lines that create `project_manager` and its `buffer_provider` (after `yield this.history_manager.connection_models.refresh();`).
**Depends on:** 8.2.8.4 §2, §3.

ℹ️ This is the never-connected case of `replace_rpc`: the constructor's Unix client has not run `connect()`, so `disconnect()` is a no-op and the state clears are on empty collections.
ℹ️ Same `Cert` / `HttpClient` construction as `FileConnectionAdd.vala` `on_request_clicked` (object initializers are fine in `async` methods; the Vala async ctor bug is about object creation in constructor arguments, not property assignment).
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
				var http = new OLLMrpc.Transport.HttpClient(config.filesd_client.url) {
					bin_body = true
				};
				try {
					tls.ensure();
					http.tls_certificate = tls.certificate;
					http.tls_database = tls.ensure_trust();
					this.project_manager.replace_rpc(
						new OLLMrpc.Client("", "", config.filesd_client.url) { http = http }
					);
				} catch (GLib.Error e) {
					GLib.warning("remote file server TLS: %s", e.message);
					this.tool_error_banner.title = "Remote file server: " + e.message;
					this.tool_error_banner.revealed = true;
				}
			}
```

ℹ️ The swap happens before the existing `this.project_manager.rpc.connect(…)` line further down, so it picks up the HTTPS client. The notification hook is already on the manager after 8.2.8.4 §3b.
ℹ️ `ensure()` / `ensure_trust()` only throw if the PEMs `FileConnectionAdd` minted are gone or unreadable. On that failure the catch does not `return`: `replace_rpc` was never reached, so the constructor's Unix client stays and the existing `connect(hello, new ClientBoot())` boots the local daemon; the banner tells the user why remote was skipped.
ℹ️ `ensure_trust()` is assigned after construction rather than inside the `HttpClient` initializer: a throwing call inside an object initializer in an `async` method is the shape the Vala async ctor bug bites.
ℹ️ Agent Pi registration further down (`new OLLMcoder.AgentPi.Factory(this.project_manager)`) is untouched on Linux (see **Design decisions**).

---

## Phase D — Check + live toggle (Connections tab)

### 2. `ollmapp/SettingsDialog/FileConnectionRow.vala` — constructor: enable **Check**, expose the switch

**Why:** Phase 1 parked the button as insensitive with a placeholder tooltip. §3 also needs to flip the **Enabled** switch back when it refuses a toggle (unsaved buffer), and the switch is a constructor local today.
**Where:** property block after `check_button`; the `var enabled_switch = new Gtk.Switch() { … };` initializer; the `this.check_button = new Gtk.Button.with_label("Check") { … };` initializer.
**Depends on:** none.

#### Add — after `public Gtk.Button check_button { get; private set; }`

```vala
		public Gtk.Switch enabled_switch { get; private set; }
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
				this.enabled_changed(this.enabled_switch.active);
			});
```

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
```

### 3. `ollmapp/SettingsDialog/ConnectionsPage.vala` — `render_file_connection()`: Check probe + live toggle + Remove; `reconnect_file_server()`

**Why:** replace the `GLib.critical` stub with the hello probe; make the **Enabled** switch (and **Remove**, and a successful **Check**) swap the running `ProjectManager` between remote and local through `replace_rpc` and a new `reconnect_file_server()`.
**Where:** `render_file_connection()`, the `remove_requested`, `check_button.clicked` and `enabled_changed` lambdas; new method after `render_file_connection()`. The local `client` (`this.dialog.app.config.filesd_client`) is already in scope in the lambdas.
**Depends on:** §2; 8.2.8.4 §0, §3, §3a–§3e; `Transport.Cert` / `HttpClient` from `8.2.8.2` Phase 1.

ℹ️ Part 1 keeps the inline callback style (`http.call.begin(…, (obj, res) => { … })`): one await, and the standards forbid a `check_file_connection` method. Part 4 is a named `async` method because it chains three awaits and Vala lambdas cannot be `async`; the plan sanctions the name `reconnect_file_server`.

##### Part 1 — Check probe

#### Remove

```vala
			this.file_connection_row.check_button.clicked.connect(() => {
				GLib.critical("file connection check not implemented");
			});
```

#### Replace with

```vala
			this.file_connection_row.check_button.clicked.connect(() => {
				var tls = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat"),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
					product_ca_resource = true
				};
				var http = new OLLMrpc.Transport.HttpClient(client.url) {
					bin_body = true
				};
				try {
					tls.ensure();
					http.tls_certificate = tls.certificate;
					http.tls_database = tls.ensure_trust();
				} catch (GLib.Error e) {
					GLib.warning("file connection check: %s", e.message);
					this.file_connection_row.expander.subtitle = "Requested: " + e.message;
					return;
				}
				this.file_connection_row.check_button.sensitive = false;
				http.call.begin(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				}, (obj, res) => {
					try {
						http.call.end(res);
					} catch (GLib.Error e) {
						GLib.debug("file connection check: %s", e.message);
						this.file_connection_row.check_button.sensitive = true;
						this.file_connection_row.expander.subtitle = "Requested: " + e.message;
						return;
					}
					this.dialog.app.config.filesd_client.approved = true;
					this.dialog.app.config.save();
					this.render_file_connection();
					if (client.enabled) {
						this.reconnect_file_server.begin(true);
					}
				});
			});
```

ℹ️ A device that was already **Enabled** while **Requested** goes live the moment **Check** succeeds; no restart.

##### Part 2 — `enabled` toggle: live swap

#### Remove

```vala
			this.file_connection_row.enabled_changed.connect((enabled) => {
				this.dialog.app.config.filesd_client.enabled = enabled;
				this.dialog.app.config.save();
			});
```

#### Replace with

```vala
			this.file_connection_row.enabled_changed.connect((enabled) => {
				if (enabled == this.dialog.app.config.filesd_client.enabled) {
					return;
				}
				var manager = this.dialog.parent.project_manager;
				if (manager.active_file != null && manager.active_file.buffer.is_modified) {
					this.file_connection_row.expander.subtitle = "Save or discard changes to "
						+ GLib.Path.get_basename(manager.active_file.path) + " first";
					this.file_connection_row.enabled_switch.active = !enabled;
					return;
				}
				this.dialog.app.config.filesd_client.enabled = enabled;
				this.dialog.app.config.save();
				if (!client.approved) {
					return;
				}
				this.reconnect_file_server.begin(enabled);
			});
```

ℹ️ The first `if` makes the switch flip-back re-entrant-safe: setting `enabled_switch.active` fires `notify["active"]` → `enabled_changed(old value)` → equals config → return.
ℹ️ `!client.approved`: a **Requested** device is not live in either state, so only the flag changes (Part 1 goes live when **Check** later succeeds).

##### Part 3 — **Remove**: back to local when the remote was live

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
				this.dialog.app.config.filesd_client =
					new OLLMchat.Settings.FilesdClient();
				this.render_file_connection();
				this.dialog.app.config.save();
				if (was_live) {
					this.reconnect_file_server.begin(false);
				}
			});
```

ℹ️ `client` is the captured pre-reset object, so `was_live` reads the old flags. Unsaved-buffer guard is not applied on **Remove** (destructive action already confirmed by the button); the buffer is dropped.

##### Part 4 — `reconnect_file_server()`

#### Add — after the closing `}` of `render_file_connection()`, before the `apply_config` docblock

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
		 * @param remote true for HTTPS to ''filesd_client.url'', false for the local Unix socket
		 */
		private async void reconnect_file_server(bool remote)
		{
			var win = this.dialog.parent;
			var client = this.dialog.app.config.filesd_client;
			OLLMrpc.Client rpc;
			OLLMrpc.ClientBoot? boot = null;
			if (remote) {
				var tls = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat"),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
					product_ca_resource = true,
				};
				var http = new OLLMrpc.Transport.HttpClient(client.url) {
					bin_body = true
				};
				try {
					tls.ensure();
					http.tls_certificate = tls.certificate;
					http.tls_database = tls.ensure_trust();
				} catch (GLib.Error e) {
					GLib.warning("file server reconnect: %s", e.message);
					client.enabled = false;
					this.dialog.app.config.save();
					this.render_file_connection();
					this.file_connection_row.expander.subtitle = "Failed: " + e.message;
					return;
				}
				rpc = new OLLMrpc.Client("", "", client.url) { http = http };
			} else {
				rpc = new OLLMrpc.Client(
					GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat"),
					"ollmfilesd.pid",
					"ollmfilesd.sock"
				);
				boot = new OLLMrpc.ClientBoot();
			}
			win.notification(new OLLMrpc.Notification() {
				method = "client.project.load_start"
			});
			win.project_manager.replace_rpc(rpc);
			if (!yield rpc.connect(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "ollmchat")
			}, boot)) {
				win.notification(new OLLMrpc.Notification() {
					method = "client.project.load_end"
				});
				win.notification(new OLLMrpc.Notification() {
					method = "Alert.show",
					message = (remote ? "File server: " : "Filesystem daemon: ")
						+ rpc.connect_error
				});
				if (!remote) {
					return;
				}
				client.enabled = false;
				this.dialog.app.config.save();
				this.render_file_connection();
				this.file_connection_row.expander.subtitle = "Failed: " + rpc.connect_error;
				yield this.reconnect_file_server(false);
				return;
			}
			try {
				yield win.project_manager.rpc_load_projects_from_db();
				var win_cfg = win.window_config();
				yield win.project_manager.restore_active_state(win_cfg.project, win_cfg.file);
			} catch (GLib.Error e) {
				GLib.critical("file server reconnect: %s", e.message);
				win.notification(new OLLMrpc.Notification() {
					method = "Alert.show",
					message = "Could not load projects: " + e.message
				});
			} finally {
				win.notification(new OLLMrpc.Notification() {
					method = "client.project.load_end"
				});
			}
		}
```

ℹ️ `restore_active_state` emits `active_project_changed`, which `SourceView` already answers with `apply_manager_state.begin()`, so the editor refreshes without an explicit call. `Approvals` refreshes through `review_files` on `activate_project`.
ℹ️ In the **Remove** path (Part 3) `this.file_connection_row` is `null` after `render_file_connection()`; only the `remote = false` branch runs there, and its failure branch never touches the row. The `remote = true` failure branches run only from Part 1 / Part 2, where the row exists.
ℹ️ `win.window_config()` returns the `Settings.Window` for this window's uuid: same source `AgentPi.Factory.activate` uses for the startup restore.

---

## Phase E — Android (design only, `⏳`)

- **🔷** `⏳` Replace the `OLLMfiles.ProjectManager` stub in `ollmapp/android/AndroidToolTypes.vala` with the real class.
  - Needs `libocfiles` in the Android `subdir()` list (root `meson.build`) and `ocfiles_vapi_dep` + `--pkg=ocfiles` on `android_poc`.
  - `libocfiles` pulls `tree-sitter`, `sqlite3`, `gmodule-2.0` into the pixiewood cross-build.
- **🔷** `⏳` `OllmchatWindow.initialize_client` (Android): when `url != "" && enabled && approved`, build the HTTPS client and call `project_manager.replace_rpc(rpc)` exactly as §1, `yield rpc.connect(hello)` (no `ClientBoot`), then register `OLLMcoder.AgentPi.Factory`.
  - Needs the **full** liboccoder on Android (today `liboccoder/meson.build` builds only `AgentPi/Skill.vala` + `SkillSet.vala` for `is_android_cross`).
  - `AgentPi.Factory.activate` casts to `OLLMchat.ChatDesktopInterface` (`tab_view`, `window_config`, `schedule_pane_update`, `chat_message_queue`, `notification`); `OllmchatWindow` implements `ChatUserInterface` only.
  - Agent Pi tools `write` / `read` / `bash` are asserted in `register_config` and are desktop tool registrations.
- **💩** `⏳` Give the Android port its own sub-plan (`RPC-8.2.8.6`) once §1–§3 are reviewed. It is a library port, not a wiring change.
- **ℹ️** `ConnectionsPage.render_approved` (from `8.2.8.1`) already references `win.project_manager.rpc`, which the Android stub lacks. Verify the `android_poc` target still compiles before starting Phase E.

---

## Follow-ups (`⏳`, not in this plan)

- **💩** `⏳` Agent Pi guard on the live swap: refuse the toggle while an agent run is in progress (it holds `File` objects from the old server). Today its in-flight RPC fails with `Client: disconnected` and the run errors out; a proper guard needs a "running" query on the agent factory.
- **💩** `⏳` Startup busy label "Connecting to filesystem daemon…" could read "Connecting to file server…" on the remote branch.

---

## Suggested order

1. **✔️** [`RPC-8.2.8.4`](done/RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md) in full (library side)
2. **⏳** Phase D — §2–§3 (Check works against a desktop that has accepted the device; toggle swaps live)
3. **⏳** Phase C — §1 (Linux takeover at startup; verify local fallback when `enabled` is off)
4. **⏳** Phase E — Android sub-plan

---

## LLM notes

- **ℹ️** The Check probe (§3 Part 1) uses `Transport.HttpClient` directly with a fresh `Request`; after 8.2.8.4 §1 it goes out with `id == 0`, which the server echoes.
- **ℹ️** Sanctioned new members: `FileConnectionRow.enabled_switch` (§2), `ConnectionsPage.reconnect_file_server` (§3 Part 4). Nothing else.
- **🚫** New `check_file_connection` / `connect_remote` / `device_cert` helpers, silent fallback to local Unix on TLS failure at startup, gating Linux Agent Pi on the remote connection, multiple file-server URLs, "restart to apply" wording anywhere.
