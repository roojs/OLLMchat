# Restarting the file server drops the open chat session

**Status:** ⏳ desktop drops the socket and does not connect again; reconnect is proposed and not applied

## Problem

- 🔷 Reboot `ollmfilesd` while the desktop chat is already connected.
- 🔷 That session then cannot use the file server.
- 🔷 Expected: the open session picks the new server back up, and file tools work again.
- 🔷 Actual: the session stays unable to use the file server.
- 🔷 A new chat process can hello the new daemon.
- 🔷 The already-open session does not.

## Evidence

- ℹ️ Reported on 2026-10-27 while restarting the daemon for `docs/bugs/2026-10-27-agent-pi-tool-calls-failed.md`.
- ℹ️ `~/.cache/ollmchat/ollmfilesd.debug.log` starts over at 16:09:56 with `listening on …/ollmfilesd.sock`.
- ℹ️ A `RPC-Daemon.hello` arrives at 16:10:01.
- ℹ️ `~/.cache/ollmchat/ollmchat.debug.log` starts over at 16:11:00.
- ℹ️ That file is a new chat process: it loads config, then `connect ok hello id=1` at 16:11:02.
- ℹ️ The session that was already open across the reboot is not in this file.
- ✔️ `libocrpc/Client.vala` `on_read` calls `disconnect()` on socket `HUP` or `ERR`.
- ✔️ `disconnect()` sets `connected` false, clears proxies, and closes the socket.
- ✔️ `disconnect()` does not open a new socket.
- ✔️ `libocfiles/ProjectManager.vala` emits `client.filesd.unreachable` when an RPC failure arrives and `rpc.connected` is already false.
- ✔️ Desktop `ollmapp/Window.vala` shows the banner "The file service is not connected." for that notification.
- ✔️ That banner only dismisses. It has no reconnect.
- ✔️ `ollmapp/Window.vala` `initialize_client` hellos once at startup and does not watch `connected`.
- ✔️ `ollmapp/Agent/Manager.vala` `on_unavailable` returns immediately when `is_android` is false.
- ✔️ The Retry or Close dialog, `client.filesd.retry`, and the Chatter close path are Android-only.
- ✔️ The only `client.filesd.retry` handler is `ollmapp/android/OllmchatWindow.vala`, which calls `reconnect()`.
- ✔️ After a successful Android hello, `notify["connected"]` calls `reconnect()` when the socket drops.
- ℹ️ `docs/plans/FILES-2.10.4.8-per-client-project-notifications.md` lists "Daemon restart — clients re-watch on reconnect" as a test that is not implemented yet.

## Root cause

- 💩 The open session's debug log was not kept, so this is from the code path rather than that log.
- 💩 Desktop `disconnect()` leaves `connected` false.
- 💩 Nothing on the desktop calls `connect()` again.
- 💩 The next file call stays on that dead client.

## Proposed fix

- 🔷 After the desktop hello has succeeded, watch `project_manager.rpc.notify["connected"]`.
- 🔷 When `connected` becomes false, call `connect()` again on that same client.
- 🔷 Use the same hello (`RPC-Daemon.hello`) and the same boot choice as startup.
- 🔷 Local socket passes a new `OLLMrpc.ClientBoot`. A URL client passes `null`.
- 💩 Try three times, 500 ms apart, because the new daemon may not be listening at the instant of `HUP`.
- 💩 Stop when hello succeeds.
- 💩 If all three fail, emit `client.filesd.unreachable` so the existing banner shows.
- 💩 The call that was in flight when the daemon died still fails. The next file call is the one that should work.
- 🚫 Do not `replace_rpc`. That drops the open project and the open file.
- 🚫 Do not add a desktop Retry dialog. `on_unavailable` does not run on desktop, and the session is supposed to pick the server up itself.
- 🚫 Do not treat a fresh chat launch as proof. That path hellos on startup and hides this failure.
- 🚫 Do not paper over a dead client with a local fallback that skips the file server.
- 🚫 Do not add a method. The block stays inline in `initialize_client`.

### `ollmapp/Window.vala` — `initialize_client`: connect again after the socket drops

**Why:** Startup hellos once. `disconnect()` does not open a new socket, and desktop never watches `connected`.

**Where:** `initialize_client`, after `rpc.connect` has returned true, before `project_manager.notification` is forwarded.

**Depends on:** none.

#### Add

```vala
			var reconnecting = false;
			var left = 0;
			var attempt = (GLib.Func) null;
			attempt = () => {
				var again = new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				};
				this.project_manager.rpc.connect.begin(again,
					config.filesd_client.url == ""
						? new OLLMrpc.ClientBoot() : null,
					(obj, res) => {
						if (this.project_manager.rpc.connect.end(res)) {
							reconnecting = false;
							return;
						}
						left--;
						if (left > 0) {
							GLib.Timeout.add(500, () => {
								attempt();
								return false;
							});
							return;
						}
						reconnecting = false;
						this.notification(new OLLMrpc.Notification() {
							method = "client.filesd.unreachable"
						});
					});
			};
			this.project_manager.rpc.notify["connected"].connect(() => {
				if (this.project_manager.rpc.connected || reconnecting) {
					return;
				}
				reconnecting = true;
				left = 3;
				attempt();
			});
```

## Attempts / changelog

- ℹ️ 2026-10-27: bug recorded from the report. No product code changed.
- ℹ️ 2026-10-27: report rewritten to one sentence per bullet. The desktop Retry and Chatter claims were wrong and are withdrawn.

## Next

- 💩 ⏳ Apply the `initialize_client` block only after this proposal is accepted.
- 💩 ⏳ Restart `ollmfilesd` while the desktop chat stays open. Keep both debug logs. Run one file call from that same session.
- 💩 ⏳ Confirm a later `connect ok hello` in the still-open chat log, then a successful file call.
