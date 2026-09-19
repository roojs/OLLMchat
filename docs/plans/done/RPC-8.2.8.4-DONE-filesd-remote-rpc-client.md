# 8.2.8.4 — DONE — Remote file connection: HTTPS RPC client + `ProjectManager.replace_rpc`

**Status:** **DONE** ✔️ — Phases A and B in tree (awaiting user **✅**)

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](../RPC-8.2.8-filesd-connections-ui.md)

**Split from:** [`RPC-8.2.8.2-DONE-filesd-android-file-connection.md`](RPC-8.2.8.2-DONE-filesd-android-file-connection.md) Phase 2. Library half; the UI half is [`RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md`](RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md).

**Depends on:**

- `8.2.8.2` Phase 1 (in tree) — `Transport.Cert` with `ensure()` / `ensure_trust()`, `Transport.HttpClient` bin POST

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Landed (tree)

- `libocrpc/Client.vala` — `http` property, HTTPS hello in `connect()`, `send_http()` forward, `disconnect()` fails pending
- `libocrpc/Transport/HttpClient.vala` — `call()` no longer sets `Request.id`
- `libocfiles/ProjectManager.vala` — `notification` signal + `replace_rpc()`
- listeners moved: `ollmapp/Window.vala`, `liboccoder/Approvals.vala`, `liboccoder/SourceView.vala`, `ollmapp/SettingsDialog/MainDialog.vala`

---

## Purpose

- **🔷** `✔️` `OLLMfiles.ProjectManager` can talk to a remote `ollmfilesd` over **HTTPS** with the device client cert, through its existing `rpc` field, with no change to libocfiles callers.
- **🔷** `✔️` The client behind `ProjectManager.rpc` can be swapped **live** (`replace_rpc`): old client disconnected, cached server state cleared, listeners keep working.
- **💩** `✔️` `OLLMrpc.Client` gains an `http` property so `ProjectManager.rpc` can POST bin RPC to the `Transport.HttpServer` gate.
  - The existing `Protocol.HTTP` path is the Hugging Face GET/JSON client and cannot talk to `ollmfilesd`.
- **💩** `✔️` `OLLMrpc.Client.disconnect()` bug fix: it aborts the process when calls are pending instead of failing them (§0). Standalone bug; a prerequisite for any live swap.
- **💩** `✔️` `ProjectManager.notification` signal replaces the four direct `rpc.notification` hooks so listeners survive the swap.
- **ℹ️** Gate behaviour: [`ollmfilesd/Https.vala`](../../../ollmfilesd/Https.vala) `allow_rpc`.
  - Approved certs pass every non-admin method.
  - Unknown certs may only call `request_registration`.

---

## Current behaviour

- **ℹ️** `OLLMfiles.ProjectManager()` always builds `OLLMrpc.Client(data_dir, "ollmfilesd.pid", "ollmfilesd.sock")` (Unix socket). `rpc` is `{ get; private set; }`.
- **ℹ️** `OLLMrpc.Client.Protocol.HTTP` sends `GET base_url + method + querystring` JSON (libochf Hub). It never POSTs a bin `Request` to `/rpc` and never sends a hello.
- **ℹ️** `OLLMrpc.Transport.HttpClient.call` is the bin POST `/rpc` peer of `HttpServer` (session + sequence headers, mTLS). It is used once, by `FileConnectionAdd.request()`.
- **ℹ️** `HttpClient.call` assigns `request.id = this.next_id++` unconditionally.
- **ℹ️** `OLLMrpc.Client.disconnect()` calls `GLib.error(...)` when `pending.size > 0`, then (unreachably) fails each pending entry with `Response.error = "Client: disconnected"` and clears the list.
  - `on_read` (HUP/ERR) and the poll loop call `disconnect()`, so a daemon dying mid-call **aborts ollmchat**.
- **ℹ️** Four sites hold lambdas on `project_manager.rpc.notification`:
  - `ollmapp/Window.vala` (forwards to `Window.notification`)
  - `liboccoder/Approvals.vala` (`event.project.invalidate_cache` → `review_files.refresh`)
  - `liboccoder/SourceView.vala` (`event.project.invalidate_cache` → file dropdown / buffer reload)
  - `ollmapp/SettingsDialog/MainDialog.vala` (`event.client_cert` → registration banner)
- **ℹ️** `ProjectManager` caches server state in `projects` (`ProjectList`, a `GLib.ListModel` with `append` / `remove`, no `clear`), `file_cache`, `active_project`, `active_file`, `review_files`. `activate_project(null)` and `remove_project` issue RPC on `this.rpc`.
- **ℹ️** Startup load sequence lives in `OLLMcoder.AgentPi.Factory.activate` (and `AgentFactory` / `Skill.Factory`): `client.project.load_start`, `rpc_load_projects_from_db()`, `restore_active_state(win_cfg.project, win_cfg.file)`, `apply_manager_state()`, `client.project.load_end`.

---

## Design decisions

- **💩** Bridge, not a new protocol: `OLLMrpc.Client.http` (nullable `Transport.HttpClient`).
  - When set on an HTTPS `socket_path`, `connect()` sends the hello through it and `send_http()` forwards every `call()`.
  - `HttpClient.call` no longer touches `Request.id`, so `Client.complete_pending` matches the id `Client.call` assigned.
  - Nullable property matches the existing `Client` fields (`bin`, `socket`, `http_session`). Alternative: default `new HttpClient("")` + `base_url != ""` test.
- **💩** Live swap = `ProjectManager.replace_rpc()` does the **state** work (disconnect old, clear caches, swap, re-forward notifications). The **caller** does the **network** work (connect with hello, reload projects, restore active state).
  - `connect()` needs a hello request and a `ClientBoot?`; restore needs `Settings.Window` paths. Both are caller knowledge.
  - Matches how `AgentPi.Factory.activate` already drives the startup load.
- **💩** `ProjectManager.notification` forwarding signal rather than re-hooking four lambdas.
  - The four sites become `project_manager.notification.connect(…)` and never learn about the swap.
  - `ProjectManager.remove_project` / `activate_project` emit `this.rpc.notification(...)` locally for banners; those keep working because the forward is a plain signal connection on the current client.
- **💩** Alternatives to `replace_rpc` considered:
  - Named constructor `ProjectManager.remote(OLLMrpc.Client rpc)`. Cannot do the live case at all.
  - Optional parameter `public ProjectManager(OLLMrpc.Client? rpc = null)`. Same.
  - Public setter `{ get; set; }`. A setter cannot disconnect the old client, clear state, or re-forward signals.
  - Method `replace_rpc(OLLMrpc.Client rpc)` (chosen, user-named). `rpc` stays `private set`; the method owns the state transition.

---

## ✔️ Phase A — `libocrpc`: bin POST RPC through `OLLMrpc.Client`

### Goal

- **💩** `✔️` `OLLMrpc.Client.disconnect()` fails pending calls instead of aborting the process (bug fix, §0).
- **💩** `✔️` `Transport.HttpClient.call` stops numbering requests (transport only; the owner of the `Request` owns its id).
- **💩** `✔️` `OLLMrpc.Client.http` property, hello over HTTPS in `connect()`, forwarding in `send_http()`.
- **💩** `✔️` Class docblock example for the HTTPS RPC mode.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### ✔️ 0. `libocrpc/Client.vala` — `disconnect()`: fail pending calls, do not abort

**Why:** bug, independent of this plan. `disconnect()` has two contradictory blocks. The first `GLib.error`s when `pending.size > 0`. The second (a few lines later) walks `pending`, completes each entry with `Response.error = "Client: disconnected"`, and clears the list. The second is the intended behaviour and is unreachable while the first exists. `on_read` (HUP/ERR) and the poll loop call `disconnect()`, so a daemon dying with any call in flight aborts ollmchat instead of surfacing an error to the caller. For this plan it also blocks a live `replace_rpc`.
**Where:** `disconnect()`, the block between `if (!this.connected) { return; }` and the `GLib.debug("disconnect socket_path=…")` call.
**Depends on:** none. Can land as its own commit before anything else here.

#### Remove

```vala
			if (this.pending.size > 0) {
				GLib.error(
					"disconnected with %u pending RPC call(s)",
					this.pending.size
				);
			}
```

ℹ️ Pure deletion. The `foreach (var entry in this.pending)` abort loop and `this.pending.clear()` below already do the right thing and already log each aborted call with `GLib.warning("disconnect abort …")`.
ℹ️ `tests/rpc/*` call `rpc.disconnect()` after awaiting their calls (`pending` empty), so behaviour there is unchanged. A test for "disconnect with one pending call yields `Client: disconnected`" is listed under **Follow-ups**.

### ✔️ 1. `libocrpc/Transport/HttpClient.vala` — `call()`: do not renumber the request

**Why:** `OLLMrpc.Client.call` assigns `request.id` before `send_head` and `complete_pending` looks the entry up by that id. Renumbering here would orphan the pending entry (or collide with another queued id). `HttpClient` is a transport: the caller that owns the `Request` owns its id. The server echoes whatever id it receives, and `HttpClient.call` returns that response straight to its awaiting caller, so standalone callers (`FileConnectionAdd.request()`, the Check probe in `8.2.8.5`) work with id `0`.
**Where:** the `next_id` field, the first statement of `call()`, and the `@param request` line in its docblock.
**Depends on:** none.

#### Remove

```vala
		private int next_id = 1;
```

#### Remove

```vala
		 * @param request wire request; {@link OLLMrpc.Request.id} set here
```

#### Replace with

```vala
		 * @param request wire request; the caller owns
		 *   {@link OLLMrpc.Request.id} (''0'' is fine for one-shot calls)
```

#### Remove

```vala
			request.id = this.next_id++;
```

ℹ️ Pure deletion; the next statement (`if (this.tls_database != null) {`) becomes the first line of `call()`.

### ✔️ 2. `libocrpc/Client.vala` — `http` property, `connect()`, `send_http()`

**Why:** `ProjectManager.rpc` is an `OLLMrpc.Client`; every libocfiles call goes through `rpc.call()`. Forwarding to a `Transport.HttpClient` makes the remote server a drop-in for the Unix socket without touching libocfiles callers.
**Where:** class docblock, property block after `pass_data_dir`, the `Protocol.HTTP` branch in `connect()`, first statement of `send_http()`.
**Depends on:** §1.

##### Part 1 — class docblock example

#### Add — after the `== HTTPS ==` example's closing ` * }}}` line and before ` * @see Request`

```vala
	 *
	 * == HTTPS RPC (ollmfilesd gate) ==
	 *
	 * {{{
	 * var http = new OLLMrpc.Transport.HttpClient("https://host:8443") {
	 *     bin_body = true,
	 *     tls_certificate = leaf.certificate,
	 *     tls_database = leaf.ensure_trust()
	 * };
	 * var rpc = new OLLMrpc.Client("", "", "https://host:8443") {
	 *     http = http
	 * };
	 * if (!yield rpc.connect(new OLLMrpc.Request() {
	 *     method = "RPC-Daemon.hello",
	 *     args = OLLMrpc.args("is", 1, "ollmchat")
	 * })) {
	 *     GLib.error("%s", rpc.connect_error);
	 * }
	 * }}}
```

##### Part 2 — property

#### Add — after `public bool pass_data_dir { get; set; default = false; }`

```vala

		/**
		 * Bin POST transport to a {@link Transport.HttpServer} (the
		 * ''ollmfilesd'' HTTPS gate).
		 *
		 * When set on an HTTPS {@link socket_path}, {@link connect}
		 * sends the hello through it and {@link call} POSTs each request
		 * instead of the Hub GET path. Set
		 * {@link Transport.HttpClient.tls_certificate} and
		 * {@link Transport.HttpClient.tls_database} before {@link connect}.
		 */
		public Transport.HttpClient? http { get; set; default = null; }
```

##### Part 3 — `connect()`: hello over HTTPS

#### Remove

```vala
			if (this.protocol == Protocol.HTTP) {
				this.http_session = new Soup.Session();
				this.connected = true;
				this.connect_error = "";
				return true;
			}
```

#### Replace with

```vala
			if (this.protocol == Protocol.HTTP && this.http != null) {
				try {
					yield this.http.call(hello_request);
				} catch (GLib.Error e) {
					this.connect_error = e.message;
					GLib.critical("connect %s: %s", this.socket_path, this.connect_error);
					return false;
				}
				this.connected = true;
				this.connect_error = "";
				return true;
			}
			if (this.protocol == Protocol.HTTP) {
				this.http_session = new Soup.Session();
				this.connected = true;
				this.connect_error = "";
				return true;
			}
```

##### Part 4 — `send_http()`: forward to `http`

#### Add — first statement of `send_http()`, before `var query_obj = head.request.args.get(0).get_object();`

```vala
			if (this.http != null) {
				this.complete_pending(head.request.id, yield this.http.call(head.request), null);
				return;
			}
```

ℹ️ `HttpClient.call` throws on `Response.error`; `send_head` already catches and routes that through `complete_pending(id, null, e)`, so `Client.call` throws with the server message (domain collapses to `RpcErrorCode.INTERNAL_ERROR`).
ℹ️ `hello_request.id` stays `0` on the HTTPS path (the socket path's `hello_request.id = this.next_id++` line is below this branch and is not reached). `Client.next_id` starts at `1` for the first `call()`.

---

## ✔️ Phase B — `libocfiles` + listeners: `ProjectManager.replace_rpc()`

### Goal

- **💩** `✔️` Give callers a way to hand `ProjectManager` a different `OLLMrpc.Client` (HTTPS with `http` set, or a fresh Unix one) **at any time**: before the first `connect()` (startup) or on a live session.
- **💩** `✔️` `ProjectManager.notification` signal so the four `rpc.notification` listeners survive a swap.
- **💩** `✔️` Move those four listeners (`Window`, `Approvals`, `SourceView`, `MainDialog`) to the new signal.

### Context

- **ℹ️** `ProjectManager.rpc` is `{ get; private set; }` with no docblock. The only constructor builds the Unix client itself. There is **no injection point** today.
- **ℹ️** A post-construction swap before `connect()` is free:
  - `OLLMrpc.Client(data_dir, pid, socket_name)` only builds paths and calls `GLib.Object(…)`. No socket, no daemon spawn until `connect()`.
  - `ReviewFiles` reads `this.manager.rpc` at call time; `DeleteManager` never touches `rpc`. Neither snapshots the client at construction.
- **ℹ️** A swap on a **live** client has three extra jobs, all in the client process:
  - **Old client.** `disconnect()`; with §0 in place every in-flight call fails with `Client: disconnected` and the caller sees a normal error.
  - **Listeners.** Four sites hold lambdas on the old client's `notification` signal. A forwarding signal on `ProjectManager` fixes that once, for all of them.
  - **Cached state.** `projects`, `file_cache`, `active_project`, `active_file`, `review_files` describe the old server. Clear them and emit `active_file_changed(null)` / `active_project_changed(null)` so `SourceView`, the project dropdown and `Approvals` drop their views.
    - `ProjectList` has no `clear()`; `remove(item)` emits `items_changed` per row, so a `while (get_n_items() > 0) remove(get_item(0))` loop is the in-tree way.
  - **Not** in `replace_rpc`: `connect()`, `rpc_load_projects_from_db()`, `restore_active_state()`. Those stay with the caller (`8.2.8.5`).

### ✔️ 3a. `libocfiles/ProjectManager.vala` — `notification` signal + forward from the constructor

**Why:** listeners that connect straight to `rpc.notification` are bound to one client object and go deaf on a swap. A signal on the manager is stable across swaps; §3 re-forwards the new client into it.
**Where:** signal after `file_metadata_changed`; forward as the last statement of `ProjectManager()`.
**Depends on:** none.

#### Add — after the `file_metadata_changed` signal (after its closing `;` and blank line)

```vala
		/**
		 * Server notification from the current {@link rpc}, re-emitted
		 * here so listeners survive {@link replace_rpc}. Connect to this,
		 * not to ''rpc.notification''.
		 *
		 * @param notif the notification as received
		 */
		public signal void notification(OLLMrpc.Notification notif);

```

#### Remove — end of `ProjectManager()`

```vala
			this.delete_manager = new DeleteManager(this);
			this.review_files = new ReviewFiles(this);
		}
```

#### Replace with

```vala
			this.delete_manager = new DeleteManager(this);
			this.review_files = new ReviewFiles(this);
			this.rpc.notification.connect((notif) => {
				this.notification(notif);
			});
		}
```

### ✔️ 3. `libocfiles/ProjectManager.vala` — `replace_rpc()`: swap the client, live or not

**Why:** `rpc` is `private set` and the constructor hard-wires the Unix socket (see **Context**). This is the one place that knows every field the old server populated. It does the state transition; the caller does the network calls.
**Where:** after the closing `}` of `public ProjectManager()`, before the `activate_file` docblock.
**Depends on:** §0 (safe `disconnect()`), §3a.

#### Add — after the default constructor

```vala

		/**
		 * Swap the RPC client.
		 *
		 * The constructor picks the local Unix-socket client. Call this to
		 * point the manager at a remote ''ollmfilesd'' (an HTTPS
		 * {@link OLLMrpc.Client} with {@link OLLMrpc.Client.http} set) or
		 * back to a fresh Unix client. Works before the first
		 * {@link OLLMrpc.Client.connect} (startup) or on a live session:
		 * the old client is disconnected (in-flight calls fail with
		 * ''Client: disconnected''), cached project state is cleared with
		 * {@link active_file_changed} / {@link active_project_changed}
		 * emitted as ''null'', and {@link notification} is re-forwarded
		 * from ''rpc''.
		 *
		 * The caller then runs {@link OLLMrpc.Client.connect},
		 * {@link rpc_load_projects_from_db} and
		 * {@link restore_active_state}; this method does not touch the
		 * network. Check {@link File.buffer} ''is_modified'' on
		 * {@link active_file} '''before''' calling: the buffer is dropped.
		 *
		 * @param rpc replacement client, not yet connected
		 */
		public void replace_rpc(OLLMrpc.Client rpc)
		{
			if (this.rpc.connected) {
				this.rpc.disconnect();
			}
			if (this.active_file != null) {
				this.active_file.is_active = false;
				this.active_file = null;
				this.active_file_changed(null);
			}
			if (this.active_project != null) {
				this.active_project.is_active = false;
				this.active_project = null;
				this.active_project_changed(null);
			}
			while (this.projects.get_n_items() > 0) {
				this.projects.remove((Folder) this.projects.get_item(0));
			}
			this.file_cache.clear();
			this.review_files.clear();
			this.rpc = rpc;
			this.rpc.notification.connect((notif) => {
				this.notification(notif);
			});
		}
```

ℹ️ `active_file` / `active_project` are cleared by hand rather than through `activate_file(null)` / `activate_project(null)`: `activate_project` fires `RPC-ProjectManager.rpc_activate_project` on `this.rpc`, which is the client being thrown away (or, after the swap, one that is not connected yet).
ℹ️ The old client's `notification` lambda is not disconnected. The old `OLLMrpc.Client` is unreferenced after the swap and finalises; `disconnect()` already removed its read watch and closed the socket, so it cannot emit again.
ℹ️ `disconnect()` on a never-connected Unix client is a no-op (`if (!this.connected) return;`), so the startup path in `8.2.8.5` pays nothing.

### ✔️ 3b. `ollmapp/Window.vala` — `initialize_client()`: listen on the manager

**Why:** listener move (see §3a). Without it the main window stops receiving `event.*` after the first swap.
**Where:** `initialize_client()`, the `rpc.notification.connect` block after the `Preparing agents…` busy label.
**Depends on:** §3a.

#### Remove

```vala
			this.project_manager.rpc.notification.connect((notif) => {
```

#### Replace with

```vala
			this.project_manager.notification.connect((notif) => {
```

### ✔️ 3c. `liboccoder/Approvals.vala` — constructor: listen on the manager

**Why:** listener move (see §3a).
**Where:** constructor, after `this.project_manager.review_files.refreshed.connect(…)`.
**Depends on:** §3a.

#### Remove

```vala
			this.project_manager.rpc.notification.connect((notif) => {
```

#### Replace with

```vala
			this.project_manager.notification.connect((notif) => {
```

### ✔️ 3d. `liboccoder/SourceView.vala` — constructor: listen on the manager

**Why:** listener move (see §3a).
**Where:** constructor, after `header_bar.append(this.file_dropdown);`.
**Depends on:** §3a.

#### Remove

```vala
			this.manager.rpc.notification.connect((notif) => {
```

#### Replace with

```vala
			this.manager.notification.connect((notif) => {
```

### ✔️ 3e. `ollmapp/SettingsDialog/MainDialog.vala` — `present_dialog()`: listen on the manager

**Why:** listener move (see §3a).
**Where:** the `registration_wired` block.
**Depends on:** §3a.

#### Remove

```vala
				this.parent.project_manager.rpc.notification.connect((notif) => {
```

#### Replace with

```vala
				this.parent.project_manager.notification.connect((notif) => {
```

ℹ️ `ProjectManager.remove_project` and `activate_project` call `this.rpc.notification(new OLLMrpc.Notification() { method = "Alert.show" … })` to raise banners. Those keep working: the emit goes through the current client's signal, which §3a / §3 forward to `ProjectManager.notification`.

---

## Follow-ups (`⏳`, not in this plan)

- **💩** `⏳` `tests/rpc/client-disconnect-pending-test.vala`: one call in flight, `disconnect()`, assert the caller gets `RpcErrorCode.INTERNAL_ERROR` "Client: disconnected" and the process is still alive (covers §0).
- **💩** `⏳` `tests/rpc/http-https-test.vala`: hello round-trip through `OLLMrpc.Client` with `http` set against `HttpServer` (covers §1–§2).
- **💩** `⏳` Server → client events over HTTPS. `ollmfilesd` broadcasts `event.filesystem.scan_*`, `event.vector.*`, `event.project.invalidate_cache` to socket connections; there is no push channel on the POST transport, so the remote client misses them. Options: long-poll `/events`, or SSE on `HttpServer`.

---

## Suggested order

1. **✔️** Phase A — §0 (`disconnect()` fix; own commit), then §1–§2 (`libocrpc`)
2. **✔️** Phase B — §3a, §3, §3b–§3e (`libocfiles` + the four listeners; app behaves as before with only the Unix client)
3. **✅** Then [`RPC-8.2.8.5`](RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) wires it into the desktop.

---

## LLM notes

- **ℹ️** `FileConnectionAdd.request()` (Phase 1) uses `Transport.HttpClient` directly with a fresh `Request`; after §1 it goes out with `id == 0`, which the server echoes. Set `id = 1` in the initializer if you want it distinguishable in daemon debug logs.
- **ℹ️** Do not route `RPC-ClientCert.pending_cert` / `client_cert` over HTTPS; the gate rejects them (`local admin only`).
- **ℹ️** Sanctioned new members: `OLLMrpc.Client.http` (§2), `ProjectManager.notification` + `replace_rpc` (§3a, §3). Nothing else.
- **🚫** `ProjectList.clear()`, a public setter on `ProjectManager.rpc`, a named constructor `ProjectManager.remote`, an idle/`pending_count` property on `OLLMrpc.Client` (not needed once §0 lands), `Protocol.HTTPS_RPC` enum value.
