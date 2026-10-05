# RPC-1.11.5 — the phone reconnects when the socket drops

> **Do not update `docs/plans/RPC-1.0-summary.md` for this sub-plan** until it is done and archived.

**Status:** applied

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala follows `docs/coding-standards.md`.

**Parent:** [`RPC-1.11.3`](RPC-1.11.3-tcp-client-handover.md)

**Depends on:** [`RPC-1.11.3`](RPC-1.11.3-tcp-client-handover.md) — after the address probe, `ProjectManager` keeps a `Client` on `tcp://`.

---

## Purpose

- **🔷** `✔️` When that connection drops, try to reconnect.
- **🔷** `✔️` On the phone, walking off the local network onto the VPN uses the stored VPN address. VPN up or VPN down drops the current socket and tries the stored addresses a few times.
- **🔷** `✔️` If those tries fail, and the user is actually using the file daemon, tell them it can no longer connect. Follow the existing disabling of `ollmfilesd`: state `UNREACHABLE`, the banner `The desktop environment is unavailable.`, leave Agent Pi, and use Chatter. `AgentDropdown` already hides Agent Pi unless the state is `LIVE` or `SOCKET`.

---

## Current behaviour

- **ℹ️** `probe_addresses` in `ollmapp/android/OllmchatWindow.vala` runs at startup only. It tries each stored address once. None answering sets `UNREACHABLE`, shows `The desktop environment is unavailable.`, and opens Chatter. Nothing retries after a later drop.
- **ℹ️** That failure path is `initialize_client`: `filesd_client.state = UNREACHABLE`, banner `The desktop environment is unavailable.`, session agent `chatter`. `AgentDropdown.wire` hides `agent-pi` for every state except `LIVE` and `SOCKET`.
- **ℹ️** `OLLMrpc.Client.disconnect` sets `connected` false. On the desktop, `on_read` does that when the socket hangs up. This plan does not change that watch.
- **ℹ️** Android `Client.connect` still sets `connected` and then `disconnect`s with `unix IO watch is not available`, and returns false. Startup therefore takes the unavailable path. The handler below is attached only after `connect` returns true, so it does not run on today's phone until a connect stays up.

---

## Phase 1 — retry stored addresses after the socket drops

- **🔷** A drop disconnects the current `tcp://` and tries the stored addresses a few times. VPN up or VPN down is that drop. The try is the stored list, so off the LAN it can hit the VPN address, and when the VPN drops it can hit the local address.
- **💩** `✔️` Three passes. "A few" was not a number.
- **💩** `✔️` A `reconnecting` flag. `replace_rpc` disconnects the old client, and that must not start another try.
- **💩** `✔️` The android window method is named `reconnect`.
- **🚫** Do not watch NetworkManager, VPN, or connectivity. The trigger is `Client.connected` becoming false.
- **🚫** Do not edit `on_read`, `poll_drain_readable`, `call_poll`, `poll_close`, `read_channel`, or the Android IO-watch bail in `Client.connect`.

### 1. `ollmapp/android/OllmchatWindow.vala` — `reconnecting`

**Why:** 💩 Stops the drop handler from running again while a try is already in progress.

**Where:** next to `fog_source`.

**Depends on:** none.

#### Add — after `private uint fog_source = 0;`

```vala
		private bool reconnecting = false;
```

### 2. `ollmapp/android/OllmchatWindow.vala` — `reconnect`

**Why:** 🔷 The drop tries each stored address a few times. 💩 Three passes. A hit connects again. None left, and the user is using the file daemon, follows the startup failure path: `UNREACHABLE`, the banner, Chatter.

**Where:** new method after `probe_addresses`.

**Depends on:** §1.

#### Add — after `probe_addresses`

```vala
		/**
		 * After the desktop socket drops, try each stored address
		 * again. Three passes. A hit replaces the client and
		 * connects. None left, when the user is using the file
		 * daemon, sets state UNREACHABLE, shows the banner, and
		 * opens Chatter.
		 */
		private async void reconnect()
		{
			var config = this.app.config;
			for (var pass = 0; pass < 3; pass++) {
				if (!yield this.probe_addresses(config)) {
					continue;
				}
				var rpc = new OLLMrpc.Client("", "", config.filesd_client.url);
				this.project_manager.replace_rpc(rpc);
				var hello = new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				};
				if (!yield rpc.connect(hello)) {
					continue;
				}
				config.filesd_client.state = FilesdClient.State.LIVE;
				this.app.config.save();
				rpc.notify["connected"].connect(() => {
					if (rpc.connected || this.reconnecting) {
						return;
					}
					this.reconnecting = true;
					this.reconnect.begin();
				});
				this.reconnecting = false;
				return;
			}
			this.reconnecting = false;
			if (config.filesd_client.state == FilesdClient.State.REQUESTED
				|| config.filesd_client.state == FilesdClient.State.DISABLED) {
				return;
			}
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

### 3. `ollmapp/android/OllmchatWindow.vala` — `initialize_client` watches the live client

**Why:** 🔷 After a connect that stayed up, a later drop starts `reconnect`.

**Where:** inside the `is_desktop_available` block, after `yield rpc.connect(hello)`.

**Depends on:** §1 and §2.

#### Add — after `is_desktop_available = yield rpc.connect(hello);`

```vala
				if (is_desktop_available) {
					rpc.notify["connected"].connect(() => {
						if (rpc.connected || this.reconnecting) {
							return;
						}
						this.reconnecting = true;
						this.reconnect.begin();
					});
				}
```

---

## Suggested order

1. ✔️ §1 — `reconnecting`
2. ✔️ §2 — `reconnect`
3. ✔️ §3 — attach the drop handler after a connect that stayed up
