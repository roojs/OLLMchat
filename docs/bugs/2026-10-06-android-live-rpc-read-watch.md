# Android live RPC client has no read watch

**Status:** ⏳ root cause confirmed; fix proposed — await apply approval

**Device:** SM-S9380, `adb-R5CY134DA0W`.  
**Related:** ℹ️ `docs/bugs/done/2026-10-06-CLOSED-certificate-not-registered.md`, `libocrpc/Client.vala`, `docs/plans/RPC-1.11.3-tcp-client-handover.md`, `docs/plans/RPC-1.11.5-phone-reconnect.md`

---

## Problem

- **🔷** After pairing succeeds, the phone must keep the TLS RPC connection to `ollmfilesd` open and load projects.
- **🔷** The phone instead reports the desktop environment as unavailable.

Reproduction: pair the phone, close the pairing dialog, and let Android startup initialize the stored `tcp://` file-daemon connection.

## Evidence

- **✔️** 2026-10-06 17:01:54 phone log: `Factory.vala:244: ProjectManager.rpc_load_projects_from_db id=1: not connected`.
- **✔️** `OLLMrpc.Client.connect` completes the TCP and TLS setup, sets `connected = true`, then the Android branch sets `connect_error = "unix IO watch is not available"`, disconnects, and returns `false`.
- **✔️** The non-Android branch creates the steady-state reader with `GLib.IOChannel.unix_new(fd)`.
- **✔️** Android `libocrpc/meson.build` includes `gio-unix-2.0`; Android does not exclude the Unix IOChannel API.
- **✔️** The current Android `libocrpc.so` already references `g_io_channel_unix_new`. `Transport.Connection` and `Live.BufferStream` compile the same call without an Android guard.
- **ℹ️** The pairing dialog has its own one-shot registration and hello reads. It does not exercise the steady-state `OLLMrpc.Client` reader.
- **ℹ️** RPC-1.11.3 deliberately left the existing `IOChannel` watch alone. RPC-1.11.5 deliberately left the Android bail in place, so its reconnect handler cannot run until `Client.connect` can remain connected.

## Root cause

- **✔️** Android steady-state RPC reading was never implemented. This is not a certificate selection, registration, TLS-handshake, or reconnect bug.
- **✔️** `Client.connect` contains an explicit temporary Android failure path. There is no captured compiler or runtime failure from `GLib.IOChannel.unix_new`; the branch prevents Android from attempting the shared read path that is already present in its build.

## Proposed fix

- **💩** Remove the unproven Android bail and use the existing `GLib.IOChannel` client read path on Android.
- **💩** Add comments at the platform boundary explaining that Android supplies the Unix IOChannel API and that the fd is only the readiness source; `Bin.Stream` still reads the plaintext or decrypted TLS stream selected above.
- **🚫** Do not edit `poll_drain_readable`, `on_read`, `call_poll`, `poll_close`, or `read_channel`. They are shared RPC and GNOME Shell polling code, and this defect does not require changing them.
- **🚫** Do not add polling, a timer, or another one-shot read in the Android application. The live reader belongs in `OLLMrpc.Client`.
- **🚫** Do not change certificate paths, registration, TLS acceptance, or the reconnect policy for this fix.

### 1. `libocrpc/Client.vala` — `connect`: use the shared IOChannel read path on Android

**Why:** The Android branch currently disconnects a successfully established TLS socket without attempting the same IOChannel watch already compiled into Android `libocrpc`.

**Where:** `connect`, immediately after `this.connected = true`; remove the Android bail and its `#else`, leaving the existing read-watch setup shared.

**Depends on:** none.

##### Part 1 — remove the Android bail and explain the shared path

#### Remove

```vala
#if ANDROID
			this.connect_error = "unix IO watch is not available";
			GLib.critical("connect %s: %s",
				this.socket_path, this.connect_error);
			this.disconnect();
			return false;
#else
```

#### Replace with

```vala
			// Android's GLib provides the Unix IOChannel API used below.
			// Keep one socket watch so every platform uses on_read and the
			// same RPC parser and disconnect path.
			// The channel only watches the socket fd for readiness; Bin.Stream
			// reads the plaintext or TLS input stream selected above.
```

##### Part 2 — make the existing hello sequence common to both platforms

#### Remove

```vala
			return true;
#endif
```

#### Replace with

```vala
			return true;
```

## Attempts / changelog

- **✔️** Separated this defect from the per-server certificate investigation.
- **✔️** Confirmed the failure is the explicit Android branch in `libocrpc/Client.vala`, after TLS setup and before the hello request.
- **✔️** Rejected the first `GLib.SocketSource` proposal after reviewing the shared-library boundary. The Android build already contains `g_io_channel_unix_new`.
- **✔️** Revised the proposal to use the existing shared read path and leave `poll_drain_readable` unchanged.

## Next

- **⏳** **🔷** Await approval to apply §1.
- **⏳** **🔷** After approval, rebuild the Android library and verify hello, project loading, notifications, and reconnect after a dropped socket.
