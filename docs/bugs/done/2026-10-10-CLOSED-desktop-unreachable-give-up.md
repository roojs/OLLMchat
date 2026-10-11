# Desktop give-up does not call the agent manager

**Status:** 🚫 CLOSED — user closed it. Working well enough. Not a line-by-line phone pass.

**Related:** ℹ️ `docs/bugs/done/2026-10-08-CLOSED-android-remote-connection-lifecycle.md`, ℹ️ `docs/bugs/done/2026-10-10-CLOSED-agent-manager.md`

## Problem

- **🔷** The flow is a dropped remote desktop. The phone retries, then gives up.
- **🔷** Give-up is not the Enabled switch and not removing the connection. Those still leave Agent Pi immediately. Give-up does not.
- **🔷** Give-up sets the connection `UNREACHABLE` and tells the agent manager with `client.filesd.unreachable`. The editor stays up.
- **🔷** The manager asks Retry or Close. No Configure. Close does not quit. Close leaves Agent Pi and starts a Chatter session. Retry runs the connection attempt again.
- **🔷** What fails: after the retries, `OllmchatWindow.reconnect` shows a banner and starts that Chatter session itself. Startup does the same when the desktop is already unreachable. The manager is never called.
- **🔷** The window also ignores `client.filesd.retry`, so Retry would have nowhere to go.

## Evidence

- **✔️** `Agent.Manager` listens for `client.filesd.unreachable` and shows Retry / Close. Retry emits `client.filesd.retry`. Close starts Chatter. Nothing in the window emits `client.filesd.unreachable`.
- **✔️** `OllmchatWindow.reconnect`, after the probes fail, sets `UNREACHABLE`, emits `Banner.show` with "The desktop environment is unavailable.", creates a session, sets `agent_name` to `chatter`, and switches to it.
- **✔️** The startup branch `is_desktop_connected && !is_desktop_available` does that same banner and Chatter switch.
- **✔️** The window notification handler acts on `Banner.show` and `Alert.show` only.
- **ℹ️** Removing the connection still returns to Chatter on purpose. That is the closed lifecycle bug, not this give-up.

## Root cause

- **✔️** Give-up owns the session change. The manager is the object that was added to own it, and give-up never notifies it.

## Proposed fix

**Why:** The manager already shows the dialog. Give-up only has to report the drop.

**Where:** `ollmapp/android/OllmchatWindow.vala`, in `reconnect` after the probes fail, in the startup unavailable branch, and on the window `notification` handler.

#### Remove

```vala
			this.notification(new OLLMrpc.Notification() {
				method = "Banner.show",
				message = "The desktop environment is unavailable."
			});
			var empty = this.history_manager.create_new_session();
			empty.project_path = this.history_manager.session.project_path;
			empty.agent_name = "chatter";
			yield this.chat_widget.switch_to_session(empty);
```

#### Replace with

```vala
			this.notification(new OLLMrpc.Notification() {
				method = "client.filesd.unreachable",
			});
```

The same replacement applies to the startup unavailable branch, which is not inside an async method, so it has no `yield` on the session switch.

#### Add

On the window `notification` handler, before the banner check:

```vala
				if (notif.method == "client.filesd.retry") {
					this.reconnect.begin();
					return;
				}
```

## Phone 2026-10-10 17:05

- **🔷** Boot showed Retry / Close.
- **🔷** Connections still listed the desktop as Active. The probe had failed, and the host was up.
- **🔷** Turning Enabled on opened the same dialog. Enabled must not.
- **🔷** Close must mark the connection disabled. It started Chatter and left the switch on.
- **✔️** Logcat pid 10362: TCP to the desktop succeeded, then state `UNREACHABLE`, with no hello error logged. `probe_addresses` dropped `hello.error` and used the same give-up as a dead host.
- **✔️** 17:08:27 `FileConnectionAdd.vala:96: certificate not registered`. Removing the connection cleared `server-id` and left `ollmrpc-ca.pem` in the desktop directory, so the PIN took the stored-certificate path. That path is rejected when the desktop does not know the certificate.

## Attempts / changelog

- **✔️** `reconnect` and the startup unavailable branch emit `client.filesd.unreachable` and no longer start Chatter. The window runs `reconnect` again for `client.filesd.retry`.
- **✔️** Enabled calls `reconnect(false)`, so a miss does not open the dialog. Close sets `DISABLED`, drops the remote RPC on Android, and starts Chatter. The row says Unreachable or Disabled instead of Active.
- **✔️** Hello and pair return the RPC code. The dialog picks its sentence from that code. Add retries registration on `CERT_NOT_REGISTERED`. `try_connection` returns only the code. `FilesdClient.remove()` deletes that desktop's certificates.
- **✔️** `meson test -C build test-rpc-filesd-pair-flow` drives `FilesdClient.try_connection` against this tree's `ollmfilesd`: PIN register and hello, stored certificate, wrong PIN, unregistered certificate then re-register, `remove()`, pair again, and a dead port. It passed.

## Next

- **ℹ️** Closed. Pairing regression is `meson test -C build test-rpc-filesd-pair-flow`. Several desktop records are [`RPC-8.2.8.15`](../plans/RPC-8.2.8.15-android-filesd-client-records.md).
