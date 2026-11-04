# TlsClient.watch dies on `Socket I/O timed out`

**Status:** ✅ done

**Pointer:** `docs/bug-fix-process.md`. `docs/guide-to-writing-plans.md` — **Checklist for plans**.

ℹ️ Follow-on to `docs/bugs/done/2026-11-04-FIXED-tlsclient-watch-raw-fd.md`.
  That report switched `watch` to `PollableInputStream.create_source`.
  The source still fires, `parse` then hits the 10s socket timeout,
  and `watch` removes itself.
ℹ️ Argus proof: `/home/alan/gitlive/argusrm/agent/tests/watch.vala`.
  `meson test -C /home/alan/gitlive/argusrm/build agent-watch` printed
  `ok agent.run` and exited 0.

---

## Problem

- 🔷 Argus `Listen.start` connects `notification` and calls `watch`.
- 🔷 After osquery `call`s, the server writes `agent.run`.
- 🔷 `Listen.notification` never runs. Ten seconds later the agent
  logs `TlsClient.vala:266: Socket I/O timed out`.
- 🔷 The controller waits until Ctrl+C.

---

## Evidence

- ✔️ Agent 17:37: `watching app socket` after `osquery 0`.
- ✔️ Server: `run command 1 on agent 1`.
- ✔️ No `agent.run` on the agent.
- ✔️ Line 266 is the `watch` callback `GLib.warning` when `parse`
  throws anything except `WOULD_BLOCK`.
- ✔️ `GSocket.timeout` is 10 seconds from `open`. `parse` is a
  blocking read. `TIMED_OUT` is not `WOULD_BLOCK`, so the source
  returns false and `watch_id` is cleared.
- ✔️ A local copy of this class that polls every 50ms, sets
  `blocking = false` while idle, and keeps the source on
  `WOULD_BLOCK` and `TIMED_OUT`, delivered `agent.run` after a
  worker `call`.

---

## Root cause

- ✔️ `create_source` is not enough. `parse` still blocks on the
  TLS stream with a 10s socket timeout.
- ✔️ `TIMED_OUT` kills `watch`. Later `agent.run` bytes sit unread.

---

## Proposed fix

- 🔷 `watch` is a 50ms timeout. Each tick parses with the socket
  non-blocking. `WOULD_BLOCK` and `TIMED_OUT` keep the source.
- 🔷 `call` sets the socket blocking again after it removes the
  source.
- 🚫 Do not add helpers. Do not start `watch` from `open`.
- 🚫 Do not keep the Argus-local `TlsClient` after this lands.

### `libocrpc/Transport/TlsClient.vala` — `call` after removing watch

**Why:** Idle `watch` leaves the socket non-blocking. The reply wait
needs a blocking read.

**Where:** after `this.watch_id = 0;` in `call`.

#### Add

```vala
			this.socket.socket.blocking = true;
```

### `libocrpc/Transport/TlsClient.vala` — `watch`

**Why:** A timeout tick can parse after `call` restores the watch.
A timed-out read must not drop the source.

**Where:** the whole `watch` method.

#### Remove

```vala
		/**
		 * Read notifications while no {@link call} is waiting.
		 *
		 * A second call is ignored. {@link call} removes the
		 * source and queues this again when {@link watching} is
		 * set. The source is the TLS input stream, not the
		 * raw TCP fd.
		 */
		public void watch()
		{
			if (this.watch_id != 0) {
				return;
			}
			this.watching = true;
			this.open();
			var pollable = (GLib.PollableInputStream) this.link.get_input_stream();
			var source = pollable.create_source();
			source.set_callback(() => {
				this.mutex.lock();
				try {
					var parsed = this.bin.parse();
					var notif = parsed as Notification;
					if (notif != null) {
						this.notification(notif);
					}
				} catch (GLib.Error e) {
					if (e.code != GLib.IOError.WOULD_BLOCK) {
						GLib.warning("%s", e.message);
						this.watch_id = 0;
						this.mutex.unlock();
						return false;
					}
				}
				this.mutex.unlock();
				return true;
			});
			this.watch_id = source.attach();
		}
```

#### Replace with

```vala
		/**
		 * Read notifications while no {@link call} is waiting.
		 *
		 * A second call is ignored. {@link call} removes the
		 * source and queues this again when {@link watching} is
		 * set. The source is a timeout. A would-block or
		 * timed-out read keeps the source.
		 */
		public void watch()
		{
			if (this.watch_id != 0) {
				return;
			}
			this.watching = true;
			this.open();
			this.socket.socket.blocking = false;
			this.watch_id = GLib.Timeout.add(50, () => {
				if (this.watch_id == 0) {
					return false;
				}
				this.mutex.lock();
				if (this.watch_id == 0) {
					this.mutex.unlock();
					return false;
				}
				this.socket.socket.blocking = false;
				try {
					var parsed = this.bin.parse();
					var notif = parsed as Notification;
					if (notif != null) {
						this.notification(notif);
					}
				} catch (GLib.Error e) {
					if (e.code == GLib.IOError.WOULD_BLOCK ||
						e.code == GLib.IOError.TIMED_OUT) {
						this.mutex.unlock();
						return true;
					}
					GLib.warning("%s", e.message);
					this.watch_id = 0;
					this.mutex.unlock();
					return false;
				}
				this.mutex.unlock();
				return true;
			});
		}
```

---

## Attempts / changelog

- ✔️ Raw-fd `IOChannel` missed TLS application data.
- ✔️ `create_source` on the TLS input still timed out `parse`
  and dropped the watch.
- ✔️ Timeout poll + keep-on-timeout delivered `agent.run` in
  the Argus loopback.

---

## Next

- ✅ Done. Argus then drops `Argus.Agent.TlsClient` and uses `OLLMrpc.Transport.TlsClient` again.
