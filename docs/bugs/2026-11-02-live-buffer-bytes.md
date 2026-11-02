# Live buffer repeats the memfd read and the memfd write

**Status:** 🚫 CLOSED 2026-11-02. `from_bytes` and `read_exact` are in `libocrpc/Live/Buffer.vala`. Call sites stay in gnome-shell-rpc.

## Problem

- 🔷 Every gnome-shell-rpc consumer that drains a memfd reply copies the same seek-and-read loop. `OLLMrpc.Live.Buffer` only stores `fd` and has `send` / `receive`.
- 🔷 Every consumer that *sends* a byte array copies the same setup: `memfd_create`, one `Posix.write`, close on a short write, `lseek` to 0, `new OLLMrpc.Live.Buffer(fd)`. The constructor today only accepts an fd.
- 🔷 Expected: one read method and one constructor on `OLLMrpc.Live.Buffer`. Callers keep their own failure (throw, empty reply, warning, return null).
- ℹ️ Call-site replacements live in gnome-shell-rpc `docs/plans/0.9.2-live-buffer-read.md`. Do not edit that tree from this bug.
- ℹ️ `Buffer(int fd)` stays. Wayland stdout and the SCM tests already hold an fd. They are not a byte array.
- 🚫 Do not put the pixels on the bin envelope as `ay`.

## Evidence

- ✔️ `libocrpc/Live/Buffer.vala` constructor is `public Buffer(int fd = -1)`. No read method. No write of bytes.
- ✔️ libocrpc unix builds already pass `--pkg=posix` and `--pkg=linux`. `Linux.memfd_create` is the same call `DrawingArea` uses. `Buffer.vala` is compiled only when `use_unix_sockets` is true, which is the same block that adds `--pkg=linux`.
- ℹ️ Read copies, all seek to 0 then `Posix.read` until the count: stage `paint_to_buffer` (16 and 18), `WindowActor.paint_to_content`, `WindowActor.get_image`, `ShapedTexture.get_image`, `Selection.transfer_async`, `SelectionSource.read_async`.
- ℹ️ Write copies, all `memfd_create` + one `Posix.write` + `lseek`: stage `paint_to_buffer` (16 and 18), both window-actor methods, `ShapedTexture.get_image`, `Selection.transfer`, `SelectionSource.read`, `Clipboard.set_content`, `ImageContent.set_data`, `DrawingArea.send_repaint_pixels`. Five of those still declare a private `memfd_create` extern. `DrawingArea` writes a cairo pointer, not a `uint8[]`.

## Root cause

- ✔️ The memfd is an fd by the time it reaches `Live.Buffer`, so the library never saw the bytes. The read and the create/write were left at every caller.

## Proposed fix

- 💩 Names below are not chosen: `read_exact`, `from_bytes`.
- 💩 `from_bytes` throws `GLib.Error` on `memfd_create` failure, a write that returns `<= 0`, or a failed `lseek`. It closes the fd before throwing. Callers catch and keep their reply.
- 💩 `read_exact` returns false when `fd` is closed or the read stops short. It does not throw, so a paint caller can still return null and a stage caller can still throw its own message.
- ℹ️ `from_bytes` takes a `uint8[]`. `DrawingArea` copies the cairo pointer into an array first. That is one extra copy against today's direct `Posix.write` of the pointer.

### `libocrpc/Live/Buffer.vala` — `from_bytes` and `read_exact`

**Where:** the class body. `from_bytes` follows `Buffer(int)`. `read_exact` follows `receive`.

**Why:** one place owns the memfd create/write and the exact read.

#### Add — `from_bytes` after `Buffer(int)`

Creates a `CLOEXEC` memfd, writes every byte of `data`, and leaves the fd at offset 0.

```vala
		/**
		 * Memfd holding a copy of ''data'',
		 * positioned at offset 0.
		 *
		 * @param data bytes to store
		 * @param name memfd name, visible in ''/proc''
		 * @throws GLib.Error when ''memfd_create'', the write,
		 *   or ''lseek'' fails
		 */
		public Buffer.from_bytes(uint8[] data, string name) throws GLib.Error
		{
			var fd = Linux.memfd_create(name, Linux.MemfdFlags.CLOEXEC);
			if (fd < 0) {
				throw new GLib.IOError.FAILED("memfd_create");
			}
			var put = 0;
			var length = data.length;
			while (put < length) {
				var n = Posix.write(fd, (void*) &data[put], length - put);
				if (n <= 0) {
					Posix.close(fd);
					throw new GLib.IOError.FAILED("memfd short write");
				}
				put += (int) n;
			}
			if (Posix.lseek(fd, 0, Posix.SEEK_SET) < 0) {
				Posix.close(fd);
				throw new GLib.IOError.FAILED("memfd lseek");
			}
			this.fd = fd;
		}
```

#### Add — `read_exact` after `receive`

Reads `length` bytes from `fd` into `dest`, starting at offset 0.

```vala
		/**
		 * Read exactly ''length'' bytes from {@link fd} into
		 * ''dest'', starting at offset 0.
		 *
		 * @param dest caller storage
		 * @param length byte count
		 * @return false when {@link fd} is closed or the read
		 *   stops short
		 */
		public bool read_exact(uint8[] dest, int length)
		{
			if (this.fd < 0) {
				return false;
			}
			Posix.lseek(this.fd, 0, Posix.SEEK_SET);
			var got = 0;
			while (got < length) {
				var n = Posix.read(this.fd, (void*) &dest[got], length - got);
				if (n <= 0) {
					break;
				}
				got += (int) n;
			}
			return got == length;
		}
```

## Attempts / changelog

- ℹ️ First draft of the read loop was `gnome-shell-rpc/docs/plans/0.9.2-live-buffer-read.md`. The library half of that draft is this bug. The plan keeps the call sites.
- ✔️ 2026-11-02: added `Buffer.from_bytes` and `Buffer.read_exact` in `libocrpc/Live/Buffer.vala`, as in the fences above.
- 🚫 CLOSED 2026-11-02. Archived. The call-site plan stays in gnome-shell-rpc.

## Next

- ✔️ The two adds are in `libocrpc/Live/Buffer.vala`.
- ℹ️ `docs/plans/0.9.2-live-buffer-read.md` in gnome-shell-rpc is the call-site half. Not this tree.
