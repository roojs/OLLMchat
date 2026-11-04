# TlsClient.watch waits on the raw TCP fd

**Status:** ✅ done — superseded by `docs/bugs/done/2026-11-04-FIXED-tlsclient-watch-timeout.md`

**Pointer:** `docs/bug-fix-process.md`. `docs/guide-to-writing-plans.md` — **Checklist for plans**.

ℹ️ Follow-on to `docs/bugs/done/2026-11-04-FIXED-tlsclient-notification.md`. That report added `watch`. This one is why `watch` still misses `agent.run`.
ℹ️ Argus: `/home/alan/gitlive/argusrm/docs/bugs/2026-11-04-command-run-no-agent.md`.

---

## Problem

- 🔷 Argus `Listen.start` connects `TlsClient.notification` and calls `watch`.
- 🔷 The agent log shows `watching app socket`, then osquery `call`s, then `osquery 0`.
- 🔷 The server writes `agent.run` on that same TLS socket.
- 🔷 `Listen.notification` never runs. The controller waits until Ctrl+C.

---

## Evidence

- ✔️ Agent `/var/log/argusrm/agent.log` 17:17:31:
  - `Listen.vala:64: watching app socket`
  - four `OSQuery.sync` `call`s from the worker thread
  - `osquery 0`
  - no `agent.run`
- ✔️ Server wrote `run … on agent 1` at 17:17:32.743, after osquery finished.
- ✔️ `TlsClient.watch` uses `IOChannel.unix_new(this.fd)` on the TCP socket.
- ✔️ `call` reads through `GTlsClientConnection` / `DataInputStream`.
- 💩 `GSocket` and TLS keep application bytes off the raw fd. The channel never sees `IN`.
- 💩 After `IN`, `parse` can `WOULD_BLOCK` once TLS has already eaten the record. The next `IN` never comes.

---

## Root cause

- ✔️ `watch` polls the TCP fd.
- ✔️ Notifications are TLS application data. Readiness belongs on the TLS input stream.

---

## Proposed fix

- 💩 `watch` uses `GLib.PollableInputStream.create_source` on `this.link.get_input_stream()`.
- 💩 Drop the unix / win32 `IOChannel` on `this.fd`.
- 💩 Keep the mutex, `call` removing the source, and `Idle.add` restore.
- 🚫 Do not add helpers. Do not start `watch` from `open`.

### `libocrpc/Transport/TlsClient.vala` — `watch`

**Why:** Idle read must fire when TLS has a notification, not when the TCP fd looks readable.

**Where:** the whole `watch` method.

#### Remove

```vala
		/**
		 * Read notifications while no {@link call} is waiting.
		 *
		 * A second call is ignored. {@link call} removes the
		 * source and queues this again when {@link watching} is
		 * set. Linux and Android use a unix channel. Windows
		 * uses a win32 fd channel.
		 */
		public void watch()
		{
			if (this.watch_id != 0) {
				return;
			}
			this.watching = true;
			this.open();
#if G_OS_WIN32
			var channel = new GLib.IOChannel.win32_new_fd(this.fd);
#else
			var channel = new GLib.IOChannel.unix_new(this.fd);
#endif
			try {
				channel.set_encoding(null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			channel.set_buffered(false);
			this.watch_id = channel.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
				(ch, cond) => {
					if ((cond & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
						this.watch_id = 0;
						return false;
					}
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
		}
```

#### Replace with

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

---

## Attempts / changelog

- ✔️ Applied the `watch` hunk in `libocrpc/Transport/TlsClient.vala`.
- ✔️ `ninja -C build libocrpc/libocrpc.so` and `libocrpc/ocrpc.vapi` succeeded.
- ⏳ `sudo install` of `ocrpc` needs a password on this machine.

---

## Next

- ✅ Done. Idle read is the timeout watch in `docs/bugs/done/2026-11-04-FIXED-tlsclient-watch-timeout.md`.
