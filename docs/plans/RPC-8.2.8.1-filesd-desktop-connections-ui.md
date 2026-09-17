# 8.2.8.1 — Desktop Connections: File Server + pending banner

**Status:** **PROPOSED** — design decisions locked below; code proposals not yet written

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Depends on:** Phase 1 of parent (**✔️** agent-done) — `RPC-ClientCert.pending_cert` / `client_cert` / int status / IP drop

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **ℹ️** File Server expander + TLS CA key auto-install moved to [`RPC-8.2.8.3-filesd-file-server-tls.md`](RPC-8.2.8.3-filesd-file-server-tls.md).
- **🔷** Preferences-dialog **banner** (same area as `PullManagerBanner` on `SettingsDialog.MainDialog` / `action_bar_area`) for the **latest** pending registration only.
  - Shows enough to decide (IP + short fingerprint + time; requester when present).
  - Buttons: **Accept** / **Reject** / **Ban**.
  - After any action: reload **newest remaining** pending into the same banner; hide when none left.
- **🔷** Approved clients are **the same kind of expandable block** as File Server / Connection.
  - Expand → read-only detail (fingerprint, accepted time, requester, …).
  - Collapse / **Remove** (delete) only — no edit of cert fields.
- **🔷** Row titles for approved clients: **Client 1**, **Client 2**, … for v1 (few clients expected).
  - Prefer a better title when a requester is present (e.g. device model string).
  - Expand `request_registration` (and `client_cert` row) with a **requester** field — best-effort device-extracted string — so clients can send it.
- **🔷** Reject → delete that pending row → banner shows next latest (or hides).
- **🔷** Ban → that **IP** blocked; banner shows next latest (or hides).
- **🔷** Remove approved → `client_cert("remove", id)` → bool.
- **🔷** Pending banner live-update via **daemon broadcast** (not a poll loop).
  - Refresh once when the preferences dialog opens is fine as a bootstrap.
  - Emit **only** when a **new registration request** arrives (`request_registration` inserts a pending row).
  - Method: **`event.client_cert`** — short subject event; the notification payload carries that it is a **request** (e.g. action / property), not a long method name.
  - Accept / Reject / Ban / Remove already happen in the UI that issued the RPC — no broadcast needed for those.

---

## Current behaviour

- **ℹ️** Desktop Connections tab = LLM API `Settings.Connection` rows only (`ConnectionAdd` / `ConnectionRow`).
- **ℹ️** Banner pattern: `PullManagerBanner` prepended on `MainDialog.action_bar_area`.
- **ℹ️** Admin RPC (local Unix): `RPC-ClientCert.pending_cert` → one `ClientCert`; `RPC-ClientCert.client_cert` (`sx`) → bool.
- **ℹ️** No list-approved wire yet — Connections rows need one (or an equivalent) to load `status = 1`.
- **ℹ️** `Https.listen` extracts CA PEM from GResource; CA key still requires a manual file copy (and the nginx doc says so).
- **ℹ️** `OllmfilesdApplication.broadcast` already fans out `OLLMrpc.Notification` on the local listen path.

---

## File Server + TLS — moved to 8.2.8.3

- **ℹ️** File Server expander (edits `Config2.filesd`) and TLS CA key auto-install moved to [`RPC-8.2.8.3-filesd-file-server-tls.md`](RPC-8.2.8.3-filesd-file-server-tls.md) — this plan was large enough already.

## Pending banner

- **🔷** `⏳` One newest `status = 0` via `pending_cert`; Accept / Reject / Ban → `client_cert`.
- **🔷** `⏳` Bootstrap: refresh when preferences opens.
- **🔷** `⏳` Live: subscribe to daemon broadcast on **new pending request** only; then reload newest pending into the banner.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `ollmapp/SettingsDialog/RegistrationBanner.vala` — new widget: show newest pending + Accept/Reject/Ban

**Why:** the banner is the desktop home of the `requester` string — it displays the pending row's `requester` / IP / short fingerprint / time and issues `client_cert` actions. Copies the `PullManagerBanner`-on-`action_bar_area` placement and the `rpc.call` pattern from `FileHistory.rpc_revert`.
**Where:** new file under `ollmapp/SettingsDialog/` (add to `ollmapp/meson.build` sources alongside the other `SettingsDialog/*.vala` files).
**Depends on:** Registration §1 (`requester` property), Broadcast §1 (emitter).

ℹ️ `MainDialog.parent` is `OllmchatWindow`; `win.project_manager.rpc` is the local Unix `OLLMrpc.Client` (same handle `ProjectsPage` uses). `pending_cert` returns `OLLMrpc.val("o", ClientCert)`; an empty `new ClientCert()` (id `0`) means “no pending” → hide.

#### Add

```vala
public class OLLMapp.SettingsDialog.RegistrationBanner : Gtk.Box
{
	public MainDialog dialog { get; construct; }

	private Gtk.Label label;
	private Gtk.Button accept_button;
	private Gtk.Button reject_button;
	private Gtk.Button ban_button;
	private int64 pending_id = 0;

	public RegistrationBanner(MainDialog dialog)
	{
		Object(
			dialog: dialog,
			orientation: Gtk.Orientation.HORIZONTAL,
			spacing: 12,
			margin_start: 12,
			margin_end: 12,
			margin_top: 12,
			margin_bottom: 12,
			visible: false
		);
		this.label = new Gtk.Label("") {
			hexpand = true,
			xalign = 0,
			ellipsize = Pango.EllipsizeMode.END
		};
		this.append(this.label);
		this.accept_button = new Gtk.Button.with_label("Accept") {
			css_classes = {"suggested-action"}
		};
		this.accept_button.clicked.connect(() => {
			this.act.begin("accept");
		});
		this.append(this.accept_button);
		this.reject_button = new Gtk.Button.with_label("Reject");
		this.reject_button.clicked.connect(() => {
			this.act.begin("reject");
		});
		this.append(this.reject_button);
		this.ban_button = new Gtk.Button.with_label("Ban") {
			css_classes = {"destructive-action"}
		};
		this.ban_button.clicked.connect(() => {
			this.act.begin("ban");
		});
		this.append(this.ban_button);
	}

	public async void refresh()
	{
		var win = this.dialog.parent;
		if (win == null || win.project_manager == null) {
			return;
		}
		OLLMrpc.Response response;
		try {
			response = yield win.project_manager.rpc.call(
				new OLLMrpc.Request() {
					method = "RPC-ClientCert.pending_cert"
				});
		} catch (GLib.Error e) {
			GLib.debug("pending_cert failed: %s", e.message);
			return;
		}
		if (response.retval.type() == GLib.Type.INVALID) {
			return;
		}
		var pending = (OLLMfilesd.ClientCert) response.retval.get_object();
		this.pending_id = pending.id;
		if (pending.id == 0) {
			this.visible = false;
			return;
		}
		var short_fp = pending.fingerprint.length > 12
			? pending.fingerprint.substring(0, 12) : pending.fingerprint;
		var when = new GLib.DateTime.from_unix_local(pending.created)
			.format("%H:%M");
		var who = pending.requester != "" ? pending.requester : "unknown";
		this.label.label = "Pending: %s — %s — fp %s — %s".printf(
			who, pending.ip, short_fp, when);
		this.visible = true;
	}

	private async void act(string action)
	{
		var win = this.dialog.parent;
		if (win == null || win.project_manager == null || this.pending_id == 0) {
			return;
		}
		try {
			yield win.project_manager.rpc.call(new OLLMrpc.Request() {
				method = "RPC-ClientCert.client_cert",
				args = OLLMrpc.args("sx", action, this.pending_id)
			});
		} catch (GLib.Error e) {
			GLib.debug("client_cert %s failed: %s", action, e.message);
			return;
		}
		this.refresh.begin();
	}
}
```

### 2. `ollmapp/SettingsDialog/MainDialog.vala` — `construct`: create + prepend the registration banner

**Why:** place the banner in `action_bar_area` (same area as `PullManagerBanner`), above the page action widgets.
**Where:** `construct`, immediately after `this.progress_banner.visible = false;` (and before `main_box.append(this.action_bar_area);`).
**Depends on:** §1.

#### Add

```vala
			this.registration_banner = new RegistrationBanner(this);
			this.action_bar_area.prepend(this.registration_banner);
```

### 3. `ollmapp/SettingsDialog/MainDialog.vala` — fields: registration banner + once-wire flag

**Why:** hold the banner reference and a guard so the `rpc.notification` subscription is connected once.
**Where:** near the `private PullManagerBanner progress_banner;` declaration.
**Depends on:** §2.

#### Add

```vala
		private RegistrationBanner registration_banner;
		private bool registration_wired = false;
```

### 4. `ollmapp/SettingsDialog/MainDialog.vala` — `show_dialog`: bootstrap + subscribe to `event.client_cert`

**Why:** refresh newest pending when the dialog opens (bootstrap) and on each daemon `event.client_cert` broadcast (live update — no poll loop).
**Where:** `show_dialog`, immediately after `this.progress_banner.initialize_existing_pulls();`.
**Depends on:** §2, Broadcast §1.

ℹ️ The subscription is connected once (`registration_wired`) and routes only `event.client_cert` to `registration_banner.refresh` — Accept/Reject/Ban/Remove are issued from this same UI, so no broadcast is needed for them.

#### Add

```vala
			if (this.parent.project_manager != null && !this.registration_wired) {
				this.registration_wired = true;
				this.parent.project_manager.rpc.notification.connect((notif) => {
					if (notif.method == "event.client_cert") {
						this.registration_banner.refresh.begin();
					}
				});
			}
			this.registration_banner.refresh.begin();
```

## Approved client expanders

- **🔷** `⏳` Same expandable-block UX as File Server / Connection (not a table, not a special widget class for “banned”).
- **🔷** `⏳` Expand = read-only detail; Remove = `client_cert("remove", id)` → bool.
- **🔷** `⏳` Titles: **Client N** for v1; upgrade label when a requester is present.
- **🔷** `⏳` Wire to list approved rows (`status = 1`) for the Connections tab (thin list wire on `ClientCert`, or equivalent — needed for the expanders).

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `ollmfilesd/ClientCert.vala` — `rpc_register`: register `approved_certs`

**Why:** the Connections tab needs a list of `status = 1` rows to render the approved expanders; today only `pending_cert` (one pending) exists.
**Where:** `rpc_register`, the `OLLMrpc.Request.add_class(...)` call.
**Depends on:** Registration §1.

#### Remove

```vala
			OLLMrpc.Request.add_class(
				"RPC-ClientCert", typeof(ClientCert),
				"request_registration", "s",
				"pending_cert", "",
				"client_cert", "sx"
			);
```

#### Replace with

```vala
			OLLMrpc.Request.add_class(
				"RPC-ClientCert", typeof(ClientCert),
				"request_registration", "s",
				"pending_cert", "",
				"client_cert", "sx",
				"approved_certs", ""
			);
```

### 2. `ollmfilesd/ClientCert.vala` — `approved_certs`: return `status = 1` rows

**Why:** thin list wire for the Connections tab; mirrors `ProjectManager.rpc_load_projects_from_db` (`retval = OLLMrpc.val("o", list)` with `Gee.ArrayList<GLib.Object>`).
**Where:** new handler, after the `pending_cert` method.
**Depends on:** §1.

#### Add

```vala
		/**
		 * Approved client certs for the Connections tab expanders.
		 *
		 * @param request inbound RPC (local Unix / bin)
		 */
		public void approved_certs(OLLMrpc.Request request)
		{
			var rows = new Gee.ArrayList<ClientCert>();
			ClientCert.query(this.app.project_manager.db).select(
				"WHERE status = 1 ORDER BY created DESC", rows);
			var list = new Gee.ArrayList<GLib.Object>();
			foreach (var row in rows) {
				list.add(row);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", list)
			});
		}
```

### 3. `ollmapp/SettingsDialog/ConnectionsPage.vala` — fields: track approved expander rows

**Why:** re-render must clear the previous approved expanders before appending fresh ones.
**Where:** near the `private Gee.HashMap<string, ConnectionRow> rows = …` declaration.
**Depends on:** none.

#### Add

```vala
		private Gee.ArrayList<Adw.ExpanderRow> approved_rows =
			new Gee.ArrayList<Adw.ExpanderRow>();
```

### 4. `ollmapp/SettingsDialog/ConnectionsPage.vala` — `render_approved` + `remove_approved`: load + render approved expanders

**Why:** render each approved client as a read-only `Adw.ExpanderRow` (title = `requester` or `Client N`, subtitle = fingerprint, detail rows IP / accepted time, Remove button → `client_cert("remove", id)` then refresh). Mirrors the `ConnectionRow` expander pattern but read-only.
**Where:** new methods, after the `add_connection_row` method. `render_approved` is `public` so the registration banner can trigger it after an Accept.
**Depends on:** §1, §2, Registration §1.

ℹ️ Client reads the list as `(Gee.ArrayList<OLLMfilesd.ClientCert>) response.retval.get_object()` (same cast shape as `ProjectManager.rpc_load_projects_from_db`'s `(Gee.ArrayList<Folder>)`).

#### Add

```vala
		public async void render_approved()
		{
			var win = this.dialog.parent;
			if (win == null || win.project_manager == null) {
				return;
			}
			OLLMrpc.Response response;
			try {
				response = yield win.project_manager.rpc.call(
					new OLLMrpc.Request() {
						method = "RPC-ClientCert.approved_certs"
					});
			} catch (GLib.Error e) {
				GLib.debug("approved_certs failed: %s", e.message);
				return;
			}
			foreach (var row in this.approved_rows) {
				this.boxed_list.remove(row);
			}
			this.approved_rows.clear();
			if (response.retval.type() == GLib.Type.INVALID) {
				return;
			}
			var clients = (Gee.ArrayList<OLLMfilesd.ClientCert>) response.retval.get_object();
			var n = 0;
			foreach (var client in clients) {
				n++;
				var title = client.requester != "" ? client.requester
					: "Client %d".printf(n);
				var expander = new Adw.ExpanderRow() {
					title = title,
					subtitle = client.fingerprint,
					can_focus = false,
					focus_on_click = false
				};
				var ip_row = new Adw.ActionRow() { title = "IP" };
				ip_row.add_suffix(new Gtk.Label(client.ip) {
					xalign = 1, selectable = true
				});
				expander.add_row(ip_row);
				var when_row = new Adw.ActionRow() { title = "Accepted" };
				var when = new GLib.DateTime.from_unix_local(client.created)
					.format("%Y-%m-%d %H:%M");
				when_row.add_suffix(new Gtk.Label(when) { xalign = 1 });
				expander.add_row(when_row);
				var remove_button = new Gtk.Button.with_label("Remove") {
					css_classes = {"destructive-action"}
				};
				var id = client.id;
				remove_button.clicked.connect(() => {
					this.remove_approved.begin(id);
				});
				var button_row = new Adw.ActionRow();
				button_row.add_suffix(remove_button);
				expander.add_row(button_row);
				this.approved_rows.add(expander);
				this.boxed_list.append(expander);
			}
		}

		private async void remove_approved(int64 id)
		{
			var win = this.dialog.parent;
			if (win == null || win.project_manager == null) {
				return;
			}
			try {
				yield win.project_manager.rpc.call(new OLLMrpc.Request() {
					method = "RPC-ClientCert.client_cert",
					args = OLLMrpc.args("sx", "remove", id)
				});
			} catch (GLib.Error e) {
				GLib.debug("client_cert remove failed: %s", e.message);
				return;
			}
			this.render_approved.begin();
		}
```

### 5. `ollmapp/SettingsDialog/ConnectionsPage.vala` — constructor: bootstrap `render_approved`

**Why:** load approved expanders when the page is first built, same as `render_connections` is called at construction.
**Where:** constructor, immediately after `this.render_connections();`.
**Depends on:** §4.

#### Add

```vala
			this.render_approved.begin();
```

### 6. Banner → approved refresh after Accept

**Why:** after the registration banner Accepts a pending client, that row becomes approved and should appear in the Connections tab.
**Where:** `RegistrationBanner.act`, after `this.refresh.begin();` (the pending reload).
**Depends on:** Pending banner §1, Approved §4.

- **⏳** `RegistrationBanner.act` should also trigger `ConnectionsPage.render_approved` after a successful Accept. `connections_page` is currently `private` on `MainDialog`, so this needs either exposing it or a small `MainDialog` relay method — pick one during implementation (do **not** add both).

## Registration requester

- **🔷** `⏳` Add a **requester** string on the `client_cert` row + `request_registration` payload — best-effort extracted by the client from the device, **not** a fixed enum and **not** user-entered text.
  - Ideal: device model identifier (e.g. Android `Build.MODEL` → `SM-A110O`-style Samsung phone name); fall back to whatever is reasonably extractable on the platform (Linux DMI product / Windows hostname / etc.); empty when nothing usable.
- **🔷** `⏳` Desktop treats it as an opaque display string — banner + approved expander show it verbatim; Android plan sends it ([`8.2.8.2`](RPC-8.2.8.2-filesd-android-file-connection.md)).
- **🚫** Desktop does **not** populate `requester` — it only stores (from the client's `request_registration` call) and displays it. Extraction from the device (`Build.MODEL` / DMI / hostname) lives in [`8.2.8.2`](RPC-8.2.8.2-filesd-android-file-connection.md).

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `ollmfilesd/ClientCert.vala` — `ClientCert`: add `requester` property

**Why:** the descriptor rides on the `ClientCert` row the desktop already serializes (`bin_default_write_prop` covers any non-`app` property), so `pending_cert` + approved rows carry it to the UI with no extra wire.
**Where:** class body, after the `created` property.
**Depends on:** none.

#### Add

```vala
		public string requester { get; set; default = ""; }
```

### 2. `ollmfilesd/ClientCert.vala` — `rpc_register`: widen `request_registration` arg signature

**Why:** the client must send the descriptor on the call; today `request_registration` has no typed args (`""`).
**Where:** `rpc_register`, the `OLLMrpc.Request.add_class(...)` call.
**Depends on:** §1.

#### Remove

```vala
			OLLMrpc.Request.add_class(
				"RPC-ClientCert", typeof(ClientCert),
				"request_registration", "",
				"pending_cert", "",
				"client_cert", "sx"
			);
```

#### Replace with

```vala
			OLLMrpc.Request.add_class(
				"RPC-ClientCert", typeof(ClientCert),
				"request_registration", "s",
				"pending_cert", "",
				"client_cert", "sx"
			);
```

### 3. `ollmfilesd/ClientCert.vala` — `request_registration`: accept + persist descriptor

**Why:** store the caller-supplied descriptor on the pending row.
**Where:** `request_registration` — signature line, and the `new ClientCert() { … }` insert.
**Depends on:** §1, §2.

#### Remove

```vala
		public void request_registration(OLLMrpc.Request request)
		{
```

#### Replace with

```vala
		public void request_registration(OLLMrpc.Request request, string requester)
		{
```

#### Remove

```vala
			var row = new ClientCert() {
				fingerprint = reply.cert_fingerprint,
				status = 0,
				ip = reply.client_ip,
				created = new GLib.DateTime.now_utc().to_unix()
			};
```

#### Replace with

```vala
			var row = new ClientCert() {
				fingerprint = reply.cert_fingerprint,
				status = 0,
				ip = reply.client_ip,
				created = new GLib.DateTime.now_utc().to_unix(),
				requester = requester
			};
```

### 4. `ollmfilesd/ClientCert.vala` — `init_db`: add column + migrate existing DBs

**Why:** new column must be in `CREATE TABLE` for fresh DBs and added via `ALTER TABLE` for existing installs.
**Where:** `init_db`, the `CREATE TABLE IF NOT EXISTS client_cert (...)` exec.
**Depends on:** §1.

#### Remove

```vala
			if (Sqlite.OK != db.db.exec(
				"CREATE TABLE IF NOT EXISTS client_cert (" +
				"id INTEGER PRIMARY KEY, " +
				"fingerprint TEXT NOT NULL UNIQUE, " +
				"status INTEGER NOT NULL DEFAULT 0, " +
				"ip TEXT NOT NULL DEFAULT '', " +
				"created INT64 NOT NULL DEFAULT 0" +
				");",
				null, out errmsg)) {
				GLib.warning("Failed to create client_cert table: %s", db.db.errmsg());
			}
```

#### Replace with

```vala
			if (Sqlite.OK != db.db.exec(
				"CREATE TABLE IF NOT EXISTS client_cert (" +
				"id INTEGER PRIMARY KEY, " +
				"fingerprint TEXT NOT NULL UNIQUE, " +
				"status INTEGER NOT NULL DEFAULT 0, " +
				"ip TEXT NOT NULL DEFAULT '', " +
				"created INT64 NOT NULL DEFAULT 0, " +
				"requester TEXT NOT NULL DEFAULT ''" +
				");",
				null, out errmsg)) {
				GLib.warning("Failed to create client_cert table: %s", db.db.errmsg());
			}
			db.db.exec(
				"ALTER TABLE client_cert ADD COLUMN requester TEXT NOT NULL DEFAULT ''",
				null, out errmsg);
```

ℹ️ The trailing `ALTER TABLE … ADD COLUMN` errors harmlessly on DBs that already have the column (idempotent), so no extra guard is needed.

## Broadcast

- **🔷** `⏳` On new pending insert in `request_registration`, broadcast `OLLMrpc.Notification` with method **`event.client_cert`** (via `OllmfilesdApplication.broadcast`).
  - Payload property indicates **request** (registration requested) — do not encode that in a long method name.
- **🔷** `⏳` Desktop banner listens for `event.client_cert` and refreshes newest pending.
  - Listen-side fence lives in **Pending banner** §4 (`MainDialog.show_dialog`): the `registration_wired` once-wire + `if (notif.method == "event.client_cert") this.registration_banner.refresh.begin();`. Not duplicated here.
- **🚫** Broadcast on Accept / Reject / Ban / Remove / approved-list changes — caller already knows.
- **🚫** Polling while the dialog is open as the primary design (bootstrap-on-open is OK).
- **🚫** Long method names like `event.client_cert.request_registration` — keep method short; put the kind on the notification data.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `ollmfilesd/ClientCert.vala` — `request_registration`: broadcast on pending insert

**Why:** the desktop banner must wake without polling the moment a new pending row is created; `OllmfilesdApplication.broadcast` fans the notification out on the local Unix listen (the desktop admin path).
**Where:** `request_registration`, immediately after `ClientCert.query(db).insert(row);` and before `request.reply(...)`.
**Depends on:** Registration §3 (same method).

ℹ️ `broadcast` only reaches `this.app.listen` (Unix socket / stdio), not `https_listen` — the desktop UI is the local admin, so that is the right path. The early-return branches (already-registered, IP banned, too many pending) intentionally do **not** broadcast.

#### Add

```vala
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.client_cert",
				object_type = "ClientCert",
				action = "request"
			});
```

---

## Notes

- **ℹ️** Pattern: `PullManagerBanner` on `MainDialog.action_bar_area` — registration banner lives there, not a Connections-tab pending list.
- **🔷** **No** pending-registration list, table, or multi-row pending UI — banner only, one at a time.
- **🔷** Registered client rows are **not** `Settings.Connection` (LLM API). Parallel expandable blocks on the same tab.
- **⏳** Code proposals — ready to draft fences (requester + `event.client_cert` broadcast both settled).

---

## LLM notes

- **ℹ️** Parent Phase 1 owns int status / HTTPS accept drop — extend registration for the requester here; do not re-open ban-drop design.
- **🚫** Unban UI.
- **🚫** Pending list UI (of any kind).
- **🚫** Mixing banned-IP rows into the registered-connection list as editable connections.
- **🚫** Showing banned IPs as “banned certificates”.
- **🚫** Putting file-server listen settings into `Settings.Connection` LLM map.
- **🚫** Operator hand-copy of CA key as the supported enable path.
- **🚫** Poll loop as the live-update mechanism.
- **💩** Live HTTPS rebind without daemon restart when `filesd.https` changes from the UI.
