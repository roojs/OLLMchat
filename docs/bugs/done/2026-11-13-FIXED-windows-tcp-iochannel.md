# Windows TCP `TcpListen` and `Client` use `IOChannel.unix_new` on Winsock sockets

**Status:** ✅ 2026-11-13. User closed it. `Connection.start()`, `Client.connect()`, and `Client.call_poll()` use `GLib.IOChannel.win32_socket` / `win32_get_fd` under `#if G_OS_WIN32`.

**Pointer:** `docs/bug-fix-process.md`. Related Windows fix: [2026-11-12-FIXED-windows-args-va-list.md](2026-11-12-FIXED-windows-args-va-list.md).

---

## Problem

- 🔷 Argus Remote Manager is replacing its custom Windows desktop–service named pipe (`argus-tray.exe` <-> `argus-agent.exe`) with `OLLMrpc` (`libocrpc`) over `OLLMrpc.Transport.TcpListen` (`127.0.0.1:4142`) and `OLLMrpc.Client` (`tcp://127.0.0.1:4142`).
- 🔷 `OLLMrpc.Transport.Connection.start()` and `OLLMrpc.Client.connect()` wrap `socket.get_fd()` with `GLib.IOChannel.unix_new(fd)` unconditionally, which does not work for Winsock `SOCKET` handles on Windows (`G_OS_WIN32`).
- 🔷 `OLLMrpc.Client.call_poll()` also calls `this.read_channel.unix_get_fd()` unconditionally.

## Evidence

- ✔️ `libocrpc/Transport/Connection.vala:178-179`:
  - Calls `this.stream.get_socket().get_fd()` and passes it to `new GLib.IOChannel.unix_new(fd)` without `#if G_OS_WIN32`.
- ✔️ `libocrpc/Client.vala:452-453`:
  - Calls `this.socket.get_socket().get_fd()` and passes it to `new GLib.IOChannel.unix_new(fd)` without `#if G_OS_WIN32`.
- ✔️ `libocrpc/Client.vala:1073`:
  - Calls `this.read_channel.unix_get_fd()` without `#if G_OS_WIN32`.
- ℹ️ On Windows (`giowin32.c`), `g_io_channel_unix_new` is for C-runtime file descriptors (`_get_osfhandle`), whereas Winsock `SOCKET` handles from `GLib.Socket.get_fd()` require `g_io_channel_win32_new_socket` (`GLib.IOChannel.win32_socket` in `glib-2.0.vapi`) and `g_io_channel_win32_get_fd` (`GLib.IOChannel.win32_get_fd`).
- ℹ️ `libocrpc/meson.build:115` already defines `-D G_OS_WIN32` when `host_machine.system() == 'windows'`.

## Root cause

- ✔️ `Connection.start()`, `Client.connect()`, and `Client.call_poll()` assume `GLib.Socket.get_fd()` returns a POSIX/CRT fd that `GLib.IOChannel.unix_new` can watch, instead of selecting `GLib.IOChannel.win32_socket` / `win32_get_fd` under `#if G_OS_WIN32`.

## Proposed fix

- 🔷 Under `#if G_OS_WIN32`, use `new GLib.IOChannel.win32_socket(fd)` in `libocrpc/Transport/Connection.vala` and `libocrpc/Client.vala`, and `this.read_channel.win32_get_fd()` in `libocrpc/Client.vala`.
- 🔷 Keep Linux and Android on `GLib.IOChannel.unix_new(fd)` / `unix_get_fd()`.
- 🚫 Do not rewrite `libocrpc` socket watches onto a separate Windows-only transport class (`TcpListen` and `Client` already share this watch path).

Edits are **Remove** / **Replace with** from the tree. Verify surrounding lines before applying.

### 1. `libocrpc/Transport/Connection.vala` — `start()`: use `win32_socket` on Windows

**Why:** `TcpListen` accepts `GLib.SocketConnection` instances on Windows; `Connection.start()` needs a Win32 socket `IOChannel` to receive `IN` / `HUP` / `ERR` readiness on the main loop.

**Where:** `libocrpc/Transport/Connection.vala`, inside `start()`.

**Depends on:** none.

#### Remove

```vala
				var fd = this.stream.get_socket().get_fd();
				this.channel = new GLib.IOChannel.unix_new(fd);
```

#### Replace with

```vala
				var fd = this.stream.get_socket().get_fd();
#if G_OS_WIN32
				this.channel = new GLib.IOChannel.win32_socket(fd);
#else
				this.channel = new GLib.IOChannel.unix_new(fd);
#endif
```

### 2. `libocrpc/Client.vala` — `connect()` and `call_poll()`: use `win32_socket` and `win32_get_fd` on Windows

**Why:** `OLLMrpc.Client` connecting to `tcp://127.0.0.1:<port>` on Windows needs `win32_socket` for `this.read_channel` so `on_read` and `call_sync` receive socket events.

**Where:** `libocrpc/Client.vala`, inside `connect()` and `call_poll()`.

**Depends on:** none.

##### Part 1 — `connect()`

#### Remove

```vala
			var fd = this.socket.get_socket().get_fd();
			this.read_channel = new GLib.IOChannel.unix_new(fd);
```

#### Replace with

```vala
			var fd = this.socket.get_socket().get_fd();
#if G_OS_WIN32
			this.read_channel = new GLib.IOChannel.win32_socket(fd);
#else
			this.read_channel = new GLib.IOChannel.unix_new(fd);
#endif
```

##### Part 2 — `call_poll()`

#### Remove

```vala
			if (this.read_channel != null) {
				poll_fd = this.read_channel.unix_get_fd();
				poll_source.fd = poll_fd;
```

#### Replace with

```vala
			if (this.read_channel != null) {
#if G_OS_WIN32
				poll_fd = this.read_channel.win32_get_fd();
#else
				poll_fd = this.read_channel.unix_get_fd();
#endif
				poll_source.fd = poll_fd;
```

## Attempts / changelog

- ℹ️ 2026-11-13: Opened from Argus Windows desktop–service IPC investigation (`argusrm/docs/bugs/2026-11-13-windows-tray-waiting-for-service.md`). No `OLLMchat` code edited yet.
- ✔️ 2026-11-13: Applied `### 1`–`### 2` (`#if G_OS_WIN32` `GLib.IOChannel.win32_socket` / `win32_get_fd` vs `unix_new` / `unix_get_fd`) in `libocrpc/Transport/Connection.vala` and `libocrpc/Client.vala`.

## Next

- ✅ 2026-11-13. User closed it. Rebuild/publish the `OLLMchat` Windows MSYS package (`libocrpc`) on release.
