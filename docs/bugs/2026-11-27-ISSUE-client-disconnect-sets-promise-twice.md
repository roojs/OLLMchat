# Disconnect aborts by setting a promise that is already set

**Status:** ✔️

## User decisions required

None.

## User reported

- 🔷 Android registration worked the first time. After the record was deleted, the second attempt showed a zero-x-zero byte error.
- 🔷 The phone has crashes and disconnects as well.

## Success scenario

- Dropping the RPC connection while a call is outstanding does not abort the process.
- The waiting call receives `Client: disconnected`.
- A second `disconnect` from that waiter returns without setting the same promise again.
- A blocking `call_sync` that is inside its private loop wakes up and sees that response.

## Current behavior

- What you said
  - The first registration on the phone worked.
  - Deleting that record and registering again failed, and the phone showed a zero-x-zero byte error.
  - The phone also crashes and disconnects.
- Observable product outcome
  - The phone process `org.roojs.argus` aborts on the GTK thread while the RPC client is disconnecting.
  - The abort is `gee_promise_set_value` asserting that the promise is still in its initial state.
  - The same abort is on the stack twice: `disconnect` sets the promise, and the waiter that runs inside that set calls `disconnect` again.

## Codebase observed behavior

- [`libocrpc/Client.vala`](../../libocrpc/Client.vala) `disconnect` walks `pending` and calls `promise.set_value` before `pending.clear()`.

```vala
foreach (var entry in this.pending) {
	GLib.warning("disconnect abort %s id=%d socket_path=%s",
		entry.request.method, entry.request.id, this.socket_path);
	entry.done_response = new Response() {
		id = entry.request.id,
		error = new Error.INTERNAL_ERROR("Client: disconnected")
	};
	entry.promise.set_value(entry.done_response);
}
this.pending.clear();
```

- [`libocrpc/Client.vala`](../../libocrpc/Client.vala) `connect` waits for hello and, when that reply has an error, calls `disconnect` again.

```vala
if (hello.error != null) {
	this.connect_error = hello.error.message != ""
		? hello.error.message
		: "could not start or reach the filesystem daemon (ollmfilesd)";
	GLib.critical(
		"hello failed id=%d: %s",
		hello_request.id,
		this.connect_error
	);
	this.disconnect();
	return false;
}
```

- `Gee.Promise.set_value` runs waiters on the same thread. The hello waiter is still inside the first `disconnect`, `pending` still holds that promise, and the second `disconnect` sets it again.
- [`libocrpc/Client.vala`](../../libocrpc/Client.vala) `complete_pending` quits `sync_loop` after setting the promise. `disconnect` does not, so a `call_sync` blocked in `sync_loop.run()` is not woken by the abort path.

## Debugging

### Current debug output

- Source: phone crash buffer, `adb logcat -b crash`, 2026-11-27, process `org.roojs.argus`.

```text
signal 6 (SIGABRT), code -1 (SI_QUEUE), fault addr --------
#01 pc … libglib-2.0.so (g_assertion_message+408)
#02 pc … libglib-2.0.so (g_assertion_message_expr+132)
#03 pc … libgee-0.8.so (gee_promise_set_value+320)
#04 pc … libocrpc.so (oll_mrpc_client_disconnect+1092)
#15 pc … libgee-0.8.so (gee_promise_set_value+160)
#16 pc … libocrpc.so (oll_mrpc_client_disconnect+1092)
```

- Takeaway: one disconnect is still inside `set_value` when a second disconnect sets the same promise.

- Source: `/tmp/argus-promise-reenter.vala`, Gee promise, waiter calls `set_value` again on the list that still holds the promise.

```text
ERROR:promise.c:676:gee_promise_future_set_value: assertion failed: (_state == State.INIT)
Bail out! ERROR:promise.c:676:gee_promise_future_set_value: assertion failed: (_state == State.INIT)
Aborted
```

- Takeaway: clearing the list before `set_value` lets the same waiter run and return. That run printed `fixed ok`.

### Debug code added (remove when complete)

None.

## Proposed fix

### ✔️ Phase 1 — `libocrpc/Client.vala` `disconnect`: finish the close before waking waiters

**Why:** `set_value` resumes the waiter immediately. That waiter must see a client that is already closed, and an empty pending list, so it cannot set the same promise. `call_sync` must also leave `sync_loop.run()`.

**Where:** [`libocrpc/Client.vala`](../../libocrpc/Client.vala). The flag sits directly after the `pending` property. `disconnect` is replaced as a whole.

**Depends on:** none.

#### Add — `closing`, after the `pending` property

Stops a waiter that calls `disconnect` from entering the method again while the first call is still waking promises.

```vala
private bool closing = false;
```

#### Remove

```vala
		public void disconnect()
		{
			if (!this.connected &&
				this.socket == null &&
				this.read_watch_id == 0 &&
				this.bin == null) {
				return;
			}
			GLib.debug("disconnect socket_path=%s pending=%u",
				this.socket_path,this.pending.size);
				
			this.sending = false;
			this.connected = false;
			if (this.read_watch_id != 0) {
				GLib.Source.remove(this.read_watch_id);
				this.read_watch_id = 0;
			}
			this.read_channel = null;
			foreach (var entry in this.pending) {
				GLib.warning("disconnect abort %s id=%d socket_path=%s",
					entry.request.method, entry.request.id, this.socket_path);
				entry.done_response = new Response() {
					id = entry.request.id,
					error = new Error.INTERNAL_ERROR("Client: disconnected")
				};
				entry.promise.set_value(entry.done_response);
			}
			this.pending.clear();
			this.proxies.clear();
			this.bin = null;
			this.input = null;
			this.output = null;
			this.tls_connection = null;
			if (this.buffer_stream != null) {
				this.buffer_stream.close();
				this.buffer_stream = null;
			}
			if (this.socket != null) {
				try {
					this.socket.close();
				} catch (GLib.Error e) {
				}
				this.socket = null;
			}
		}
```

#### Replace with

```vala
		public void disconnect()
		{
			if (this.closing) {
				return;
			}
			if (!this.connected &&
				this.socket == null &&
				this.read_watch_id == 0 &&
				this.bin == null) {
				return;
			}
			this.closing = true;
			GLib.debug("disconnect socket_path=%s pending=%u",
				this.socket_path, this.pending.size);
			this.sending = false;
			this.connected = false;
			if (this.read_watch_id != 0) {
				GLib.Source.remove(this.read_watch_id);
				this.read_watch_id = 0;
			}
			this.read_channel = null;
			var aborted = new Gee.ArrayList<PendingWrite>();
			aborted.add_all(this.pending);
			this.pending.clear();
			this.proxies.clear();
			this.bin = null;
			this.input = null;
			this.output = null;
			this.tls_connection = null;
			if (this.buffer_stream != null) {
				this.buffer_stream.close();
				this.buffer_stream = null;
			}
			if (this.socket != null) {
				try {
					this.socket.close();
				} catch (GLib.Error e) {
				}
				this.socket = null;
			}
			foreach (var entry in aborted) {
				GLib.warning("disconnect abort %s id=%d socket_path=%s",
					entry.request.method, entry.request.id, this.socket_path);
				entry.done_response = new Response() {
					id = entry.request.id,
					error = new Error.INTERNAL_ERROR("Client: disconnected")
				};
				entry.promise.set_value(entry.done_response);
			}
			if (this.sync_loop != null) {
				this.sync_loop.quit();
			}
			this.closing = false;
		}
```

## LLM

- ℹ️ Phone: `SM-S9380`, package `org.roojs.argus`, wireless adb `192.168.88.145`. Crash buffer times 16:02:19, 16:09:06, and 16:12:21 are the promise abort. 16:02:30 is a different abort, `winpr_jni_attach_thread` from `freerdp_settings_new` inside `argus_controller_rdp_screen_configure`. That one is FreeRDP, not this library.
- ℹ️ Argus server log `/var/log/argusrm/server.log` shows the controller connection closing around those same minutes (`closing connection` after `Offering.enroll` / hello). The phone dies in the client close that follows.
- ℹ️ A literal `expected object type byte, got 0x00` line was not in the phone crash buffer. The abort text that was captured is the Gee promise assertion.
- ℹ️ Throwaway: `/tmp/argus-promise-reenter.vala`. `buggy` aborts. `fixed` prints `fixed ok`. Not part of the library.
- ℹ️ `docs/bug-fix-process.md`
- ℹ️ `libocrpc/Client.vala`
- ✔️ Applied in `libocrpc/Client.vala`. Meson version and changelog heading are `1.4.20`.
