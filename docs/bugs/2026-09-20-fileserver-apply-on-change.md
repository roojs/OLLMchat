# File Server subtitle Off while running; apply only on dialog close

**Status:** ✔️ subtitle + Port suffix applied — await user verify  
**Hit:** 2026-09-20 — Preferences → Connections → File Server  
**Component:** `ollmapp/SettingsDialog/FileServerRow.vala`  
**Plan (persist-on-close superseded):** `docs/plans/RPC-8.2.8.3-filesd-file-server-tls.md`

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

---

## Problem

🔷 On startup, Preferences shows File Server **Off** on the left (expander subtitle). The file server is actually on.

🔷 Closing the dialog as the only apply/restart trigger does not make sense. Changing a toggle or setting Port should restart the service **as soon as the value differs from what the dialog started with**.

**Expected (user):**

- 🔷 Subtitle matches whether the file server is actually running / listening.
- 🔷 Toggles (Enabled, Host, Proxy, systemd) apply immediately when they differ from the last applied `filesd`.
- 🔷 Port applies on blur (focus-out), not on every keystroke.
- 🔷 If anything changed, restart ollmfilesd.
- 🔷 systemd **off:** stop the user unit, then start ollmfilesd **manually**. systemd **on:** stop the manual process, then start the user unit. Toast whether the daemon **stays up**.
- 🔷 Toast the Connections tab for restart progress and stay-up / failure. **No** `Alert.show`.
- 🔷 Toast copy (approved): `Restarting file server…` / `Started systemd user unit` / `Started file server (manual)` / `File server is up` / `File server did not stay up` / `File server listening on {https}` / `File server stopped`.
- 🔷 Toast `timeout = 2` (seconds, Adw literal). No named constant.
- 🔷 Stay-up probe: `ClientBoot.connectable()` (Unix socket). If not up yet, wait 2 seconds and probe again.
- 🔷 Killing the app without a clean dialog close leaving unsaved listen edits on the widgets is **default**. Not a bug.

**Actual:**

- ✔️ Expander subtitle is `"Off"` unless `filesd.enabled && filesd.https != ""`.
- ✔️ Apply/reboot only from `MainDialog.on_closed` → `ConnectionsPage.apply_config()`.
- ✔️ `reboot` is always `kill` + `ensure_daemon` and `Alert.show` on the main window.

---

## Current behaviour (code + this machine)

### Subtitle vs switch vs daemon

- ℹ️ Constructor sets `expander.subtitle = "Off"`. `load_config` (dialog show) sets it again:
  - `"Off"` when `!filesd.enabled` **or** `filesd.https == ""`
  - else the `host:port` string
- ℹ️ Enabled switch is the suffix on the **right**. Subtitle is the **left** text under the title.
- ℹ️ `filesd.enabled` defaults **true** when the JSON key is missing.
- 🔷 HTTPS does **not** disable the standard Unix socket. `ollmfilesd` starts `SocketListen` on `ollmfilesd.sock` unless `--tcp` / `--interactive`. `Https.listen()` runs **after** that and is a second listener. `filesd.unix` is unused for this. The desktop app’s local `ProjectManager` stays on that socket; HTTPS is for remote clients.
- ℹ️ `filesd.systemd` is independent: `Filesd.install()` does `enable --now` / `disable --now`. Turning Enabled off does **not** clear `https` / `proxy` / `systemd`.

### This machine’s `~/.config/ollmchat/config.2.json`

```json
"filesd" : {
    "socket" : "",
    "https" : "",
    "proxy" : true,
    "systemd" : true
}
```

- ✔️ No `enabled` key → loads as `true` → switch **on**, rows shown.
- ✔️ `https` is `""` → subtitle **Off**.
- ✔️ `systemd` is `true` → user unit is supposed to keep ollmfilesd running (unix). HTTPS has nothing to bind.

### Apply / restart today

- ✔️ `reboot` is always `ClientBoot.kill` then `ensure_daemon`. It does not hand off systemd ↔ manual.
- ℹ️ `filesd.install()` is async `spawn_command_line_async` for disable / enable `--now`. `reboot` SIGTERMs the pid and may spawn a second **manual** process while `Restart=on-failure` fights it.
- ✔️ Port is only copied into `filesd.https` when Enabled is on, Host/Port rows are visible, and **both** host and port text are non-empty. Placeholder `8443` is not saved.

### Toasts today

- ℹ️ No `Adw.Toast` / `Adw.ToastOverlay` in the app. Settings `MainDialog` is an `Adw.Dialog` (no `add_toast`).
- ✔️ `FileServerRow.reboot` uses `Alert.show` on the parent window, behind settings.

### Why close-apply feels wrong

- 🔷 Changing a switch or Host does nothing to the running daemon until the dialog closes.
- 🔷 Port can be edited and left with focus; close is the only commit.
- 🔷 Unsaved widgets if the process dies without `on_closed` is normal.

---

## Root cause

- ✔️ **Subtitle Off:** `https` on disk is empty. systemd/unix can still be up.
- ✔️ **Late apply:** File Server was wired like LLM connections — one `apply_config` on `MainDialog.on_closed`.

---

## Desired behaviour

🔷 Snapshot is the last applied `filesd` (compare before write, as `apply_config` already does). `load_config` must not apply.

🔷 On **Enabled**, **Host**, **Proxy**, **systemd** change: `apply_config()`. On **Port** `has-focus` becoming false: `apply_config()`. Dialog close still calls `apply_config()` (catches Port still focused). Unchanged values skip restart.

🔷 systemd switch is a **handoff**:

- **Off:** `disable --now`, then `ClientBoot.kill` + `ensure_daemon`.
- **On:** `ClientBoot.kill` (manual), then `Filesd.install()` (`enable --now`).
- systemd **unchanged** and **on:** `systemctl --user restart ollmfilesd.service` (reload config; do not spawn a second manual daemon).
- systemd **unchanged** and **off:** `kill` + `ensure_daemon`.

🔷 Stay-up: `boot.connectable()`. If false, wait 2 seconds, probe again. Toast the result.

🔷 Enabled off still must not wipe Host / Port / Proxy / systemd widgets. Unix socket stays up.

🚫 Turning on HTTPS must not stop `ollmfilesd.sock`.

🚫 `Alert.show` / main-window `ActivityBanner` for this path.

🚫 Named timeout / stay-up `const`. Use literal `2`.

🚫 New methods (`toast`, `handoff`, `stay_up`, `on_*`). Inline in `apply_config` / `reboot` / existing lambdas.

🚫 Fill Port with `8443` as real text.

---

## Proposed fix

### 1. `ollmapp/SettingsDialog/ConnectionsPage.vala` — wrap the tab in `Adw.ToastOverlay`

**Why:** Settings is `Adw.Dialog` (no `add_toast`). Toasts must live on Connections.

**Where:** fields next to `scrolled_window`; constructor where the scrolled window is built and appended; `FileServerRow` construction.

**Depends on:** none.

##### Part 1 — field

#### Add

After `private Gtk.ScrolledWindow scrolled_window;` — overlay the tab is toasted on.

```vala
		private Adw.ToastOverlay toast_overlay;
```

##### Part 2 — wrap scroll

#### Remove

```vala
			this.scrolled_window.set_child(this.group);
			this.scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			this.append(this.scrolled_window);
```

#### Replace with

Put the preferences group in the overlay so File Server toasts show on this tab.

```vala
			this.scrolled_window.set_child(this.group);
			this.scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			this.toast_overlay = new Adw.ToastOverlay();
			this.toast_overlay.set_child(this.scrolled_window);
			this.append(this.toast_overlay);
```

##### Part 3 — pass overlay into `FileServerRow`

#### Remove

```vala
			this.file_server_row = new FileServerRow(
				this.dialog.app.config.filesd, this.dialog.parent);
```

#### Replace with

```vala
			this.file_server_row = new FileServerRow(
				this.dialog.app.config.filesd,
				this.dialog.parent,
				this.toast_overlay);
```

---

### 2. `libollmchat/Settings/Filesd.vala` — `install()`: wait for systemctl

**Why:** UI handoff must finish `disable --now` / `enable --now` before the stay-up probe. Async spawn returns before the unit changes.

**Where:** `install()` disable branch, `daemon-reload`, and `enable --now`.

**Depends on:** none.

##### Part 1 — disable `--now`

#### Remove

```vala
			if (!this.systemd) {
				try {
					GLib.Process.spawn_command_line_async(
						"systemctl --user disable --now ollmfilesd.service"
					);
				} catch (GLib.Error e) {
					GLib.warning("systemd disable failed: %s", e.message);
				}
				return;
			}
```

#### Replace with

Sync so the caller can probe the socket after the unit is down.

```vala
			if (!this.systemd) {
				string sout, serr;
				int status;
				try {
					GLib.Process.spawn_command_line_sync(
						"systemctl --user disable --now ollmfilesd.service",
						out sout, out serr, out status);
				} catch (GLib.Error e) {
					GLib.warning("systemd disable failed: %s", e.message);
				}
				return;
			}
```

##### Part 2 — `daemon-reload`

#### Remove

```vala
				try {
					GLib.Process.spawn_command_line_async(
						"systemctl --user daemon-reload"
					);
				} catch (GLib.Error e) {
					GLib.warning("systemd daemon-reload failed: %s", e.message);
				}
```

#### Replace with

```vala
				string reload_out, reload_err;
				int reload_status;
				try {
					GLib.Process.spawn_command_line_sync(
						"systemctl --user daemon-reload",
						out reload_out, out reload_err, out reload_status);
				} catch (GLib.Error e) {
					GLib.warning("systemd daemon-reload failed: %s", e.message);
				}
```

##### Part 3 — enable `--now`

#### Remove

```vala
			try {
				GLib.Process.spawn_command_line_async(
					"systemctl --user enable --now ollmfilesd.service"
				);
			} catch (GLib.Error e) {
				GLib.warning("systemd enable failed: %s", e.message);
			}
```

#### Replace with

```vala
			string en_out, en_err;
			int en_status;
			try {
				GLib.Process.spawn_command_line_sync(
					"systemctl --user enable --now ollmfilesd.service",
					out en_out, out en_err, out en_status);
			} catch (GLib.Error e) {
				GLib.warning("systemd enable failed: %s", e.message);
			}
```

---

### 3. `ollmapp/SettingsDialog/FileServerRow.vala` — live apply, handoff, toast

**Why:** Apply on toggle/blur; systemd handoff vs bounce; Connections toast; no `Alert.show`.

**Where:** fields; constructor; `load_config`; `apply_config`; `reboot`.

**Depends on:** §1 overlay, §2 sync `install()`.

##### Part 1 — class doc

#### Remove

```vala
	 * those rows and sets {@link OLLMchat.Settings.Filesd.enabled}
	 * false without clearing their values. The Connections page
	 * calls {@link apply_config} on close, which writes
	 * {@link filesd} and {@link reboot}s if listen fields changed.
	 * {@link load_config} fills the IP dropdown and listen fields
	 * when the settings dialog is shown.
```

#### Replace with

```vala
	 * those rows and sets {@link OLLMchat.Settings.Filesd.enabled}
	 * false without clearing their values. Toggles and Port blur
	 * call {@link apply_config}, which writes {@link filesd} and
	 * {@link reboot}s if listen fields changed. Dialog close still
	 * calls {@link apply_config}. {@link load_config} fills widgets
	 * when the settings dialog is shown and must not reboot.
```

##### Part 2 — fields

#### Add

After `public OllmchatWindow win { get; private set; }` — overlay from Connections; skip apply while loading; systemd value before this apply (handoff vs restart).

```vala
		public Adw.ToastOverlay toast_overlay { get; private set; }
		private bool loading = false;
		private bool was_systemd = false;
```

##### Part 3 — constructor signature

#### Remove

```vala
		 * @param filesd Config listen settings (enabled, https, proxy, systemd)
		 * @param win Host window for ProjectManager reconnect
		 */
		public FileServerRow(OLLMchat.Settings.Filesd filesd, OllmchatWindow win)
		{
			this.filesd = filesd;
			this.win = win;
```

#### Replace with

```vala
		 * @param filesd Config listen settings (enabled, https, proxy, systemd)
		 * @param win Host window for ProjectManager reconnect
		 * @param toast_overlay Connections-tab overlay for restart toasts
		 */
		public FileServerRow(
			OLLMchat.Settings.Filesd filesd,
			OllmchatWindow win,
			Adw.ToastOverlay toast_overlay)
		{
			this.filesd = filesd;
			this.win = win;
			this.toast_overlay = toast_overlay;
```

##### Part 4 — apply on toggle / Port blur (constructor, after systemd row)

#### Remove

```vala
			this.enabled_switch.notify["active"].connect(() => {
				this.proxy_row.visible = this.enabled_switch.active;
				this.systemd_row.visible = this.enabled_switch.active;
				this.host_row.visible = false;
				this.port_row.visible = false;
				if (!this.enabled_switch.active) {
					return;
				}
				if (this.host_dropdown.model.get_n_items() == 0) {
					return;
				}
				this.host_row.visible = true;
				this.port_row.visible = true;
			});
		}
```

#### Replace with

Visibility first; `apply_config` unless `load_config` is filling widgets.

```vala
			this.enabled_switch.notify["active"].connect(() => {
				this.proxy_row.visible = this.enabled_switch.active;
				this.systemd_row.visible = this.enabled_switch.active;
				this.host_row.visible = false;
				this.port_row.visible = false;
				if (this.enabled_switch.active && this.host_dropdown.model.get_n_items() > 0) {
					this.host_row.visible = true;
					this.port_row.visible = true;
				}
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.host_dropdown.notify["selected"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.proxy_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.systemd_switch.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.apply_config();
			});
			this.port_entry.notify["has-focus"].connect(() => {
				if (this.loading || this.port_entry.has_focus) {
					return;
				}
				this.apply_config();
			});
		}
```

##### Part 5 — `load_config` skip apply

#### Add

First line of `load_config()` — ignore switch/dropdown notifies while filling.

```vala
			this.loading = true;
```

#### Remove

```vala
			if (!this.enabled_switch.active) {
				return;
			}
			if (ips.length == 0) {
				return;
			}
			this.host_row.visible = true;
			this.port_row.visible = true;
```

#### Replace with

One exit: clear `loading` after widgets are filled so later toggles apply.

```vala
			if (this.enabled_switch.active && ips.length > 0) {
				this.host_row.visible = true;
				this.port_row.visible = true;
			}
			this.loading = false;
```

##### Part 6 — `apply_config` remember previous systemd

#### Add

Immediately after `var prev_enabled = this.filesd.enabled;` — reboot uses this to choose handoff vs `systemctl restart`.

```vala
			this.was_systemd = prev_systemd;
```

##### Part 7 — `reboot` docblock

#### Remove

```vala
		 * Spawn failure
		 * raises ''Alert.show'' on the window and returns. If this
```

#### Replace with

```vala
		 * Spawn or stay-up failure toasts
		 * ''File server did not stay up'' on Connections. If this
```

##### Part 8 — `reboot` body: toast + systemd handoff + stay-up

#### Remove

```vala
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var boot = new OLLMrpc.ClientBoot(data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
			yield boot.kill();
			try {
				yield boot.ensure_daemon();
			} catch (GLib.Error e) {
				GLib.critical("file server restart: %s", e.message);
				this.win.notification(new OLLMrpc.Notification() {
					method = "Alert.show",
					message = "File daemon is not up: " + e.message
				});
				return;
			}
```

#### Replace with

In-progress toast, then handoff or bounce, then Unix-socket stay-up. No `Alert.show`.

```vala
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var boot = new OLLMrpc.ClientBoot(data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
			var toast = new Adw.Toast("Restarting file server…") { timeout = 2 };
			if (this.filesd.systemd && !this.was_systemd) {
				toast.title = "Started systemd user unit";
			}
			if (!this.filesd.systemd) {
				toast.title = "Started file server (manual)";
			}
			this.toast_overlay.add_toast(toast);
			if (this.filesd.systemd && this.was_systemd) {
				string sout, serr;
				int status;
				try {
					GLib.Process.spawn_command_line_sync(
						"systemctl --user restart ollmfilesd.service",
						out sout, out serr, out status);
				} catch (GLib.Error e) {
					GLib.warning("systemd restart failed: %s", e.message);
				}
			}
			if (this.filesd.systemd && !this.was_systemd) {
				yield boot.kill();
				this.filesd.install();
			}
			if (!this.filesd.systemd) {
				this.filesd.install();
				yield boot.kill();
				try {
					yield boot.ensure_daemon();
				} catch (GLib.Error e) {
					GLib.critical("file server restart: %s", e.message);
					this.toast_overlay.add_toast(
						new Adw.Toast("File server did not stay up") { timeout = 2 });
					return;
				}
			}
			if (!boot.connectable()) {
				GLib.Timeout.add_seconds(2, () => {
					this.reboot.callback();
					return false;
				});
				yield;
			}
			if (!boot.connectable()) {
				this.toast_overlay.add_toast(
					new Adw.Toast("File server did not stay up") { timeout = 2 });
				return;
			}
			var done = "File server is up";
			if (!this.filesd.enabled || this.filesd.https == "") {
				done = "File server stopped";
			}
			if (this.filesd.enabled && this.filesd.https != "") {
				done = "File server listening on " + this.filesd.https;
			}
			this.toast_overlay.add_toast(new Adw.Toast(done) { timeout = 2 });
```

**Keep** the existing Unix reconnect (`project_manager.rpc.http != null` through `rpc.connect`) after that block.

---

## Attempts / changelog

- ℹ️ 8.2.8.3 shipped apply-on-close + `reboot` via `ClientBoot`.
- ℹ️ Enabled switch later: off keeps `https`; subtitle Off unless enabled **and** `https` set.
- ✔️ 2026-09-20: behaviour + fences in this log. Not applied.
- ✔️ 2026-09-20: applied Connections toast overlay, sync `Filesd.install()`, live apply / systemd handoff / stay-up toasts. `loading` / `was_systemd` are two field declarations (Vala members are not comma locals). `ninja -C build ollmapp/ollmchat` succeeded.
- 🔷 2026-09-20: subtitle should say running socket vs socket+HTTPS, not Off while unix is up. Port not sensitive again — see `docs/bugs/2026-09-19-fileserver-port-not-sensitive.md`.
- ✔️ 2026-09-20: subtitle from `connectable()` + enabled/`https`; Port matches ConnectionRow suffix. Compiles.
- 🔷 2026-09-20: `Off` is not meaningful. Use `Not running` (pairs with `Running (…)`). Not `Cannot connect` unless the user prefers that.
- ✔️ 2026-09-20 logs: `ollmfilesd.service` **disabled** / **inactive**, journal **empty**. Process is `ollmfilesd --debug` (app spawn). Config `systemd: true`. Subtitle would have lied “via systemd”.
- 🔷 Status: systemd vs on startup. Toasts: `Starting via systemd…` / `Starting on startup…`, not generic “file server starting”.
- 💩 Flip systemd while `reboot` is in flight stacked async handoffs + toasts (`was_systemd` stomped). Queue one follow-up reboot.
- ✔️ 2026-09-20: subtitle from `systemctl is-active` + socket; toast copy; one reboot at a time. Compiles.

## Subtitle (user 2026-09-20)

🔷 Left subtitle is daemon listen mode, not the Enabled switch (that is HTTPS):

- `Not running` — Unix socket not connectable (`connectable()` false)
- `Running (socket only)` — `ClientBoot.connectable()`, HTTPS not bound (`!enabled` or `https == ""`)
- `Running (socket and HTTPS)` — connectable, Enabled on, `https` set

🔷 Probe in `load_config` and after `reboot` stay-up. Do not key Off off empty `https` alone.

🚫 New subtitle helper. Inline at those two sites.

🚫 Do not wipe Host/Port when Enabled is off.

### `FileServerRow.load_config` — subtitle from socket

#### Remove

```vala
			this.enabled_switch.active = this.filesd.enabled;
			this.expander.subtitle = "Off";
			if (this.filesd.enabled && this.filesd.https != "") {
				this.expander.subtitle = this.filesd.https;
			}
```

#### Replace with

```vala
			this.enabled_switch.active = this.filesd.enabled;
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat");
			var boot = new OLLMrpc.ClientBoot(data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
			var up = boot.connectable();
			this.expander.subtitle = "Not running";
			if (up) {
				this.expander.subtitle = "Running (socket only)";
			}
			if (up && this.filesd.enabled && this.filesd.https != "") {
				this.expander.subtitle = "Running (socket and HTTPS)";
			}
```

### `FileServerRow.apply_config` — reboot owns subtitle

#### Remove

```vala
			this.expander.subtitle = "Off";
			if (this.filesd.enabled && this.filesd.https != "") {
				this.expander.subtitle = this.filesd.https;
			}
			if (this.filesd.enabled != prev_enabled
```

#### Replace with

```vala
			if (this.filesd.enabled != prev_enabled
```

### `FileServerRow.reboot` — subtitle after stay-up

#### Add

After each `File server did not stay up` toast, before `return` — socket did not stay up.

```vala
				this.expander.subtitle = "Not running";
```

(two `return` sites: `ensure_daemon` catch, and second `connectable` fail)

#### Add

After the stay-up success check (`if (!boot.connectable()) { … return; }`) — socket is up; HTTPS is config.

```vala
			this.expander.subtitle = "Running (socket only)";
			if (this.filesd.enabled && this.filesd.https != "") {
				this.expander.subtitle = "Running (socket and HTTPS)";
			}
```

## Next

- 🔷 `⏳` systemd row stays visible when File Server Enabled is off; toggling systemd still writes `filesd.systemd` and reboots. Host / Port / Proxy still hide.
- 🔷 `⏳` User verify: subtitle Not running / on startup / via systemd; toasts `Starting via systemd…` / `Starting on startup…`; one toast sequence per toggle.
- 💩 Toast still says `File server stopped` when HTTPS is off and unix is up — leave unless the user wants that copy changed.
- 🚫 Do not archive 8.2.8.3 until that verify. Do not promote ✔️ to ✅.
