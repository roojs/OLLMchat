# TlsClient drops notifications and has no idle read

**Status:** ✅ done — library hunks applied; later watch reports superseded the idle read

**Pointer:** `docs/bug-fix-process.md`. `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala must follow `docs/coding-standards.md`.

ℹ️ Filed from Argus. `docs/bugs/done/2026-11-02-FIXED-tls-one-shot-rpc.md` said libocrpc is not edited from the Argus tree. This is that library report.
ℹ️ Argus plan: `/home/alan/gitlive/argusrm/docs/plans/2.4-listen.md`.

---

## Problem

- 🔷 `Transport.TlsClient.call` writes one request and waits for a `Response`.
  - `parse` that is not a `Response` is skipped.
  - A `Notification` on that stream is dropped.
- 🔷 After `call` returns, nothing reads the socket.
  - A later server notification sits in the TCP buffer.
- 🔷 Argus `Command.run` writes `agent.run` on the agent's app socket.
  - The agent uses `TlsClient` for that socket.
  - `Listen.start` cannot pull the notification.
  - The controller waits until Ctrl+C.
- 🔷 Reproduce from Argus:
  - `sudo argus-controller --agent 1 --command "ls -l /home/alan"`
  - Server: `run … on agent 1`.
  - Agent log has no command.

---

## Why this is a libocrpc bug

- 💩 `OLLMrpc.Client` already demuxes `Notification` on a read watch.
  - `TlsClient` was added as the TLS caller that does not hello.
  - It still has to leave `Notification` on the same stream.
- 💩 Argus cannot read the socket. `bin` and `fd` are private.
- 💩 Switching the Argus app socket to `Client` would hello, connect async, and race the osquery worker `call`.
- 🚫 Do not copy a poll loop into Argus `Listen.start`.

---

## Evidence

- ✔️ `libocrpc/Transport/TlsClient.vala` `call`:
  - `if (!(parsed is Response)) { continue; }`
  - No `notification` signal.
  - No idle watch.
- ✔️ `OLLMrpc.Client.dispatch_message` emits `notification` for a `Notification`.
- ✔️ Argus `agent/Listen.vala` `start` logs and returns.
  - `notification` already handles `agent.run` and `agent.send`.
- ✔️ Osquery and `Command.stdout` also `call` on that `TlsClient`.
  - A watch that stays up while `call` runs can steal the `Response`.
  - Osquery `call`s from a worker thread.

---

## Root cause

- ✔️ `TlsClient` is request/response only.
- ✔️ The stream also carries client notifications.
- ✔️ There is no public read of those messages.

---

## Proposed fix

- 💩 `notification` signal, same name as `OLLMrpc.Client`.
- 💩 `call` emits that signal when `parse` returns a `Notification`.
  - It no longer skips those messages.
- 💩 `watch` reads while idle and emits the same signal.
- 💩 `call` removes the watch, then puts it back when `watching` is set.
  - Restore with `GLib.Idle.add` so a worker thread does not attach the watch to the wrong context.
- 💩 One `GLib.Mutex` around `write` / `parse` in `call` and in the watch.
- 🔷 The mutex is one `TlsClient`, not every caller of the process.
  - A chatty command is one `call` per chunk, until that reply.
  - It is not the whole command.
  - Another `TlsClient` or another connection is not held.
- 💩 Named API this report adds:
  - `notification`
  - `watch`
  - `watch_id`
  - `watching`
  - `mutex`
- 🚫 Do not add `on_read` or pause helpers.
- 🚫 Do not change `Client`.
- 🚫 Do not start `watch` from `open`. Registration and download only `call`.

### `libocrpc/Transport/TlsClient.vala` — class overview

**Why:** `call` is no longer response-only.

**Where:** the class docblock.

**Depends on:** none.

#### Remove

```vala
	 * TCP TLS client that sends a {@link OLLMrpc.Request} and
	 * returns that {@link OLLMrpc.Response}.
```

#### Replace with

```vala
	 * TCP TLS client that sends a {@link OLLMrpc.Request} and
	 * returns that {@link OLLMrpc.Response}. {@link watch} reads
	 * {@link OLLMrpc.Notification} while idle. {@link call} emits
	 * {@link notification} for those messages instead of dropping them.
```

### `libocrpc/Transport/TlsClient.vala` — signal and watch state

**Why:** A long-lived caller connects the signal and starts the idle read.

**Where:** after `tls_database`, before `connected`. Then after `fd`.

**Depends on:** none.

#### Add — signal after `tls_database`

```vala
		/**
		 * A notification parsed on this stream.
		 *
		 * {@link call} emits this when the next message is a
		 * {@link OLLMrpc.Notification}. {@link watch} emits the
		 * same signal while idle.
		 *
		 * @param notif the decoded notification
		 */
		public signal void notification(Notification notif);

```

#### Add — private watch state after `fd`

```vala
		private uint watch_id = 0;
		private bool watching = false;
		private GLib.Mutex mutex;
```

### `libocrpc/Transport/TlsClient.vala` — `call`

**Why:** A notification during a later `call` must not be dropped. The idle watch must not steal the `Response`.

**Where:** the whole `call` method.

**Depends on:** the signal and watch fields.

#### Remove

```vala
		public Response call(Request request) throws GLib.Error
		{
			this.open();
			this.bin.write(request);
			var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					var parsed = this.bin.parse();
					if (!(parsed is Response)) {
						continue;
					}
					return (Response) parsed;
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK ||
						GLib.get_monotonic_time() >= reply_wait) {
						throw e;
					}
					var reply_poll = GLib.PollFD();
					reply_poll.fd = this.fd;
					reply_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
				}
			}
		}
```

#### Replace with

```vala
		public Response call(Request request) throws GLib.Error
		{
			this.open();
			if (this.watch_id != 0) {
				GLib.Source.remove(this.watch_id);
				this.watch_id = 0;
			}
			this.mutex.lock();
			this.bin.write(request);
			var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					var parsed = this.bin.parse();
					var notif = parsed as Notification;
					if (notif != null) {
						this.notification(notif);
						continue;
					}
					if (!(parsed is Response)) {
						continue;
					}
					this.mutex.unlock();
					if (this.watching) {
						GLib.Idle.add(() => {
							this.watch();
							return false;
						});
					}
					return (Response) parsed;
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK ||
						GLib.get_monotonic_time() >= reply_wait) {
						this.mutex.unlock();
						if (this.watching) {
							GLib.Idle.add(() => {
								this.watch();
								return false;
							});
						}
						throw e;
					}
					var reply_poll = GLib.PollFD();
					reply_poll.fd = this.fd;
					reply_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
				}
			}
		}
```

### `libocrpc/Transport/TlsClient.vala` — `watch`

**Why:** After the last `call` the socket is idle. Nothing reads a later notification unless this runs.

**Where:** after `call`.

**Depends on:** the signal and watch fields.

#### Add — idle read on the socket fd

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

---

## Attempts / changelog

- ✔️ Applied the `TlsClient` hunks in `libocrpc/Transport/TlsClient.vala`.
- ✔️ `ninja -C build libocrpc/libocrpc.so` and `libocrpc/ocrpc.vapi` succeeded.
  - `watch` calling `open` is the existing unhandled-error warning.
- ⏳ `sudo install` of `ocrpc` needs a password on this machine.

---

## Next

- ✅ Done. Follow-ons: `docs/bugs/done/2026-11-04-FIXED-tlsclient-watch-raw-fd.md`, `docs/bugs/done/2026-11-04-FIXED-tlsclient-watch-timeout.md`.
