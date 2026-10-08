# Android pairing reply fails before certificate storage

**Status:** ✅ fixed — physical phone reaches `LIVE`, exposes Agent Pi, and loads project files; complete file opening also passes on the emulator

**Devices:** SM-S9380 physical phone for the original failure; `emulator-5554` for the controlled current-build flow.
**Related:** ℹ️ `docs/bugs/done/2026-10-05-CLOSED-android-pair-listen.md`, `docs/bugs/2026-10-06-android-live-rpc-read-watch.md`, `docs/bugs/2026-10-08-android-remote-connection-lifecycle.md`, `ollmapp/android/FileConnectionAdd.vala`, `tests/rpc/filesd-pair-test.vala`, `android/pair-listen-probe/`

---

## Problem

- **🔷** Test the complete pairing and use flow on Android before changing product code: discovery, PIN registration, signed certificate and CA storage, authenticated hello, active connection-list entry, Agent Pi activation, browsing files through Agent Pi without errors, and the daemon approved-device list.
- **🔷** On the physical phone, the first Request reported `expected object type byte, got 0x08`; a second Request reported `Server required TLS certificate`.
- **🔷** The physical-phone failure did not add Agent Pi or update the connection state.

Original phone reproduction: uninstall the APK installed from the other machine, install the fresh local APK, open Allow New Device, open Add Remote Desktop, enter the six digits, and press Request twice.

## Evidence

- **✔️** Fresh APK built 2026-10-07 08:17 and installed after removing the differently signed phone APK.
- **✔️** Phone logcat 08:20:24.242: `FileConnectionAdd.vala:96: expected object type byte, got 0x08`.
- **✔️** Daemon at 08:20:24.550 received `ClientCert.request_registration`; at 08:20:24.553 it emitted `event.pair`; the daemon then logged `Unexpected early end-of-stream`.
- **✔️** Phone server directory `9990d325-cda3-40f0-9718-8776736497ce` contained only `client-key.pem`, `client.csr`, and the original `client.pem`; it did not contain `ollmrpc-ca.pem`.
- **✔️** Phone `config.2.json` still had empty `filesd-client.url`, `addresses`, and `server-id`, with state `0`.
- **✔️** Phone logcat 08:20:30.066: `Server required TLS certificate`; daemon at 08:20:30.377: `ssl handshake failed: TLS connection peer did not send a certificate`.
- **✔️** The second phone message was downstream of the first parse failure: no CA was stored, so the retry had no client certificate after pairing had closed.
- **✔️** The daemon used for the original phone failure had a deleted build-tree `libocrpc.so` mapped while the phone contained the fresh 08:17 Android library.
- **✔️** Restarted `ollmfilesd` with the current build-tree `libocrpc` and armed it directly through its Unix socket with PIN `438217`; no desktop app was running.
- **✔️** Published `_rpc._tcp` directly and used the installed app on `emulator-5554`; it discovered `192.168.0.16:8422`, submitted one pairing request, and showed `Remote Desktop: tcp://192.168.0.16:8422` as `Active`.
- **✔️** Emulator logcat at 08:54:03.960 showed filesd state `SOCKET`; Agent Pi became visible and the agent model contained `agent-pi`, `just-ask`, and `chatter`.
- **✔️** A direct local Unix RPC call to `ClientCert.approved_certs` returned the new in-memory row `id=13`, fingerprint `667ce677c5804524c74b4a124143301cb162cf13200602813af3d6a49aa18da3`, requester `ollmchat`; the daemon approved-device list contained 13 rows.
- **✔️** The matching-build emulator flow produced neither `expected object type byte, got 0x08` nor `Server required TLS certificate`.
- **✔️** `android/pair-listen-probe/` still tests only `_rpc._tcp` discovery and PIN-field visibility; there is no standalone Android test app for the complete pairing and sync flow.

## Root cause

- **✔️** `Server required TLS certificate` is a downstream symptom, not the root defect.
- **✔️** The current Android reply parser and current daemon codec interoperate for the complete emulator flow, so the evidence rules out an unconditional current-code Android `0x08` parser defect.
- **✔️** Runtime pairing saves the remote URL and marks filesd state `SOCKET`, but it never replaces or connects the Android window's `ProjectManager.rpc`; the pairing dialog's authenticated hello used a temporary TLS stream that is closed when the dialog returns.
- **✔️** Marking state `SOCKET` exposes Agent Pi even though its project manager still owns the unconnected local-socket client created before pairing; selecting Agent Pi then fails with `ProjectManager.rpc_load_projects_from_db id=1: not connected`.
- **✔️** After wiring runtime pairing into `reconnect`, the fresh emulator flow reached TCP/TLS on every pass but `probe_addresses` failed at `Bin.Stream.parse()` with `GLib.IOError.WOULD_BLOCK` (`Try again`) and ended in state `UNREACHABLE`.
- **✔️** `probe_addresses` uses `connect_to_host_async`, which leaves the Android socket nonblocking, then performs a synchronous hello parse; the working registration path explicitly switches its socket to blocking before the same synchronous protocol exchange.
- **✔️** After making the probe socket blocking, the authenticated hello parsed as a response with no error and an empty `msg`; `probe_addresses` incorrectly rejected it because it required `msg == "ok"`.
- **✔️** The working pairing path and `OLLMrpc.Client.connect` treat hello as successful when `response.error` is null; the daemon does not guarantee an `"ok"` message.
- **✔️** After accepting the real hello contract, the address probe succeeds but the persistent `OLLMrpc.Client` fails with `connect tcp://192.168.0.16:8422: Unacceptable TLS certificate`.
- **✔️** `OLLMrpc.Client.connect` creates its `GLib.TlsClientConnection`, but the adjacent “certificate and database are filled in later” comment has no implementation; the paired per-server client certificate and CA are never supplied to the persistent connection.
- **✔️** After TLS setup, `OLLMrpc.Client.connect` still contains the explicit Android `unix IO watch is not available` disconnect path documented in `2026-10-06-android-live-rpc-read-watch.md`; project and file browsing require the persistent read watch.
- **✔️** With both fixes applied, the persistent client completes TLS and starts the read watch, but its first hello read fails with `Connection is closed`.
- **✔️** The `tls_link` variable is scoped to the remote-TCP block and is released before the client installs the read watch and sends hello; releasing the `GLib.TlsClientConnection` closes the TLS stream even though the underlying socket field remains.
- **✔️** Retaining the TLS connection fixed the live channel on `emulator-5554`: hello replied, `ProjectManager.rpc_load_projects_from_db` replied, state became `LIVE`, and Agent Pi appeared.
- **✔️** Selecting the OLLMchat project exercised `Folder.fetch_files`, `Folder.fetch_pending_approvals`, `ProjectManager.rpc_activate_project`, a second `Folder.fetch_files`, and filesystem scan notifications; the file dropdown displayed repository files and reported 1,818 total / 50 loaded.
- **❌** The full flow is not complete. During that project activation/scan, `/usr/bin/ollmfilesd` emitted invalid-GType criticals, dumped core with `SIGTRAP`, and systemd restarted it. Android logged `TLS connection closed unexpectedly`, reconnected, and lost the selected file state before the chosen file opened.
- **✔️** The retained core resolves to the 15-second vector probe timeout callback at `ollmfilesd/ProjectManager.vala:335`, whose `GLib.error` deliberately terminates the process with `SIGTRAP`.
- **✔️** The vector probe was waiting on model discovery after DNS failed for `ollama.roojs.com`; model availability is external and is not required for project or file RPC.
- **✔️** `BackgroundScan.open_vector_db` already defines unavailable or unconfigured codebase-search models as dimension zero, and `queue_project` already skips dimension zero. `ProjectManager.activate_project` contradicts that contract by treating the same state and a slow probe as fatal process errors.
- **✔️** A controlled repeat with the same config while DNS and the remote model server were available completed project activation and vector work without a critical or crash, confirming that Android transport and filesystem scanning are not the crash source.
- **✔️** After removing the fatal probe timer, flattening the vector tail, and routing unavailable-model state through `Banner.show`, the complete `emulator-5554` flow passed against the build-tree daemon: persistent hello, `LIVE` state, Agent Pi, OLLMchat project selection, 1,854 file entries, `File.read` reply, and rendered file contents.
- **✔️** The build-tree daemon remained alive through project scan, vector startup, file-list loading, and file reading; Android logged no TLS disconnect, critical, warning, or RPC error during the verified flow.
- **✔️** On the physical SM-S9380, pairing stored the connection and changed state to `ENABLED`, but each of the three post-pair probes failed at `bin.parse()` with `GLib.IOError.WOULD_BLOCK` (`Try again`) and ended `UNREACHABLE`.
- **✔️** Setting the raw socket blocking is insufficient for a TLS stream whose reply is not already buffered. The emulator passed because its reply was available immediately; the physical network exposed the race.
- **✔️** `FileConnectionAdd` already handles the same Android TLS/bin behavior by retrying `Bin.Stream.parse()` on `WOULD_BLOCK`, polling the socket fd for readiness, and enforcing a ten-second deadline.
- **✔️** The rebuilt APK on the physical SM-S9380 completed persistent hello, changed filesd state to `LIVE`, exposed Agent Pi, activated OLLMchat, and received replies for repeated `Folder.fetch_files` calls.
- **💩** The original `0x08` failure is most consistent with the stale daemon/client protocol mismatch, but the exact stale server revision and emitted registration-reply bytes were not preserved, so that attribution is not yet proven.

## Proposed changes

- **🔷** Keep the direct test controls in `tests/rpc/filesd-pair-test.vala`: `--arm-only` arms pairing without the desktop UI and `--list-approved` verifies the daemon's live approved-device list.
- **🔷** Add a standalone Android full-flow test that records discovery, registration reply parsing, certificate persistence, authenticated hello, active connection-list state, Agent Pi activation, and successful file browsing through Agent Pi.
- **🔷** After Android runtime pairing, keep Agent Pi hidden while filesd state is `ENABLED`, invoke the existing Android reconnect path to replace and connect the persistent `ProjectManager.rpc`, and expose Agent Pi only after that path sets state `LIVE`.
- **🔷** Stop `probe_addresses` from publishing the transient `SOCKET` state; its one-shot hello only proves an address and is not the persistent RPC connection required by Agent Pi.
- **🔷** In the Android-only address probe, switch the socket returned by `connect_to_host_async` to blocking before the synchronous TLS/bin hello, matching the proven registration path without changing shared RPC code.
- **🔷** Accept the probe hello when it is a response without `response.error`, matching the real daemon hello contract; do not require the optional `response.msg` to equal `"ok"`.
- **🔷** Add a `configure_tls` signal on `OLLMrpc.Client` and emit it before the remote TCP TLS handshake so the owning application can supply the paired server's credentials without adding forbidden TLS properties to the shared client.
- **🔷** In both Android persistent-client construction sites, load the certificate directory identified by `filesd_client.server_id` and configure the client's TLS connection with that client certificate and CA.
- **🔷** Apply the existing `2026-10-06-android-live-rpc-read-watch.md` proposal: remove the Android disconnect branch and use the shared IOChannel readiness watch, while `Bin.Stream` continues reading the selected TLS stream.
- **🔷** Keep the `GLib.TlsClientConnection` in a private `OLLMrpc.Client` field for the lifetime of the live RPC connection, and release it during `disconnect`.
- **🔷** Remove the fatal vector-probe timer from `ProjectManager.rpc_activate_project`; the HTTP connection already owns its request timeout, and this asynchronous vector work must not kill unrelated project/file RPC.
- **🔷** Report dimension-zero vector availability to the connected client with the existing `Banner.show` notification path, then allow the existing `queue_project` contract to skip indexing.
- **🔷** Flatten the vector tail of `rpc_activate_project` with an early return when no scanner is configured and sequential readiness checks.
- **🔷** Make `probe_addresses` use the existing `FileConnectionAdd` reply-wait pattern: retry `Bin.Stream.parse()` after `WOULD_BLOCK`, poll the raw fd only for readiness, and stop after ten seconds.
- **🚫** Do not replace `GLib.IOChannel` or alter the shared RPC codec based on the historical `0x08` result; reproduce the failure with matching current binaries and capture the raw reply before proposing such a change.
- **🚫** Do not disable certificate validation, trust every certificate, or add `tls_certificate` / `tls_database` properties to `OLLMrpc.Client`.
- **🚫** Do not suppress the invalid-GType diagnostics; they remain evidence of a model-discovery failure path, but they are not a valid reason for the file daemon to terminate.

### Connect Android after the pairing dialog closes

**Why:** The pairing hello runs on a temporary TLS stream. Android must connect the window's persistent RPC before Agent Pi is exposed.

**Where:** `ollmapp/SettingsDialog/ConnectionsPage.vala`, in the `FileConnectionAdd.dialog_closed` signal after copying the registered server details.

#### Remove

```vala
				this.dialog.app.config.filesd_client.state = FilesdClient.State.SOCKET;
				this.dialog.app.config.save();
				this.render_file_connection();
```

#### Replace with

```vala
#if ANDROID
				/* The Android pairing hello uses a temporary TLS stream.
				 * Connect the persistent RPC before exposing Agent Pi. */
				this.dialog.app.config.filesd_client.state = FilesdClient.State.ENABLED;
#else
				this.dialog.app.config.filesd_client.state = FilesdClient.State.SOCKET;
#endif
				this.dialog.app.config.save();
				this.render_file_connection();
#if ANDROID
				this.dialog.parent.reconnect.begin();
#endif
```

### Reuse the Android reconnect path for runtime pairing

**Why:** Startup and dropped connections already use this path to probe addresses, replace `ProjectManager.rpc`, authenticate it, and set state `LIVE`; runtime pairing needs the same persistent connection.

**Where:** `ollmapp/android/OllmchatWindow.vala`, the existing `reconnect` method declaration and docblock.

#### Remove

```vala
		/**
		 * After the desktop socket drops, try each stored address
		 * again. Three passes. A hit replaces the client and
		 * connects. None left, when the user is using the file
		 * daemon, sets state UNREACHABLE, shows the banner, and
		 * opens Chatter.
		 */
		private async void reconnect()
```

#### Replace with

```vala
		/**
		 * Connects Android's persistent desktop RPC after pairing or a drop.
		 *
		 * Pairing verifies certificates on a temporary TLS stream. This path
		 * probes stored addresses, replaces ''ProjectManager.rpc'', connects
		 * it, and sets filesd state ''LIVE'' before Agent Pi is exposed.
		 *
		 * @since 1.0
		 */
		public async void reconnect()
```

### Keep address probing from exposing Agent Pi

**Why:** A successful one-shot hello proves the address and certificate but does not mean the persistent `ProjectManager.rpc` is connected.

**Where:** `ollmapp/android/OllmchatWindow.vala`, at the successful end of `probe_addresses`.

#### Remove

```vala
				config.filesd_client.state = FilesdClient.State.SOCKET;
```

### Wait for the synchronous probe reply

**Why:** Android's async socket connect leaves the socket nonblocking, but this probe performs a synchronous TLS handshake and bin reply parse. The registration path already proves that switching this Android socket to blocking makes the same exchange reliable.

**Where:** `ollmapp/android/OllmchatWindow.vala`, in `probe_addresses` immediately after `connect_to_host_async` succeeds and before creating the TLS connection.

#### Add

```vala
				/* The async Android connect leaves this socket nonblocking.
				 * The probe uses a synchronous TLS and bin reply exchange. */
				try {
					conn.socket.blocking = true;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					continue;
				}
```

### Use the daemon hello response contract

**Why:** A successful daemon hello guarantees no wire error, not an `"ok"` message. Requiring `hello.msg == "ok"` rejects a valid authenticated response.

**Where:** `ollmapp/android/OllmchatWindow.vala`, in `probe_addresses` after checking `hello.error`.

#### Remove

```vala
				if (hello.msg != "ok") {
					continue;
				}
```

### Wait for TLS application data on a physical device

**Why:** Making the raw socket blocking does not guarantee that Android's TLS input stream has decrypted application data when `Bin.Stream.parse()` first runs. The pairing flow already proves the required poll-and-retry pattern.

**Where:** `ollmapp/android/OllmchatWindow.vala`, in `probe_addresses` after writing `RPC-Daemon.hello`.

#### Remove

```vala
				OLLMrpc.Bin.Serializable parsed;
				try {
					parsed = bin.parse();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					continue;
				}
				var hello = parsed as OLLMrpc.Response;
				if (hello == null) {
					continue;
				}
```

#### Replace with

```vala
				OLLMrpc.Response? hello = null;
				var hello_wait = GLib.get_monotonic_time() + 10 * 1000000;
				while (hello == null) {
					try {
						hello = bin.parse() as OLLMrpc.Response;
					} catch (GLib.IOError e) {
						if (e.code != GLib.IOError.WOULD_BLOCK
							|| GLib.get_monotonic_time() >= hello_wait) {
							GLib.warning("%s", e.message);
							break;
						}
						var hello_poll = GLib.PollFD();
						hello_poll.fd = conn.socket.fd;
						hello_poll.events = GLib.IOCondition.IN;
						GLib.poll(new GLib.PollFD[] { hello_poll }, 200);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						break;
					}
				}
				if (hello == null) {
					continue;
				}
```

### Let the application configure the shared client's TLS connection

**Why:** The shared client owns the long-lived TLS connection but cannot know which application-managed paired server certificate directory to use. A signal keeps certificate selection in the application and avoids adding TLS state properties to `OLLMrpc.Client`.

**Where:** `libocrpc/Client.vala`, after the existing `failed` signal and immediately after creating `tls_link`.

#### Add

```vala
		/**
		 * Lets the owner supply credentials for a remote TCP TLS connection.
		 *
		 * Emitted after the TLS connection is created and before its handshake.
		 * The owner may set the client certificate and trust database selected
		 * for the remote server.
		 *
		 * @param connection TLS connection about to handshake
		 */
		public signal void configure_tls(GLib.TlsClientConnection connection);
```

#### Add

```vala
					this.configure_tls(tls_link);
```

### Supply the paired server credentials on Android

**Why:** Android stores one certificate directory per paired server. Both startup and reconnect must configure the persistent client from the selected `server_id`.

**Where:** `ollmapp/android/OllmchatWindow.vala`, both blocks that construct a persistent `OLLMrpc.Client`.

#### Remove

```vala
				// Certificate for this server is filled in later on the handshake.
				var rpc = new OLLMrpc.Client("", "", config.filesd_client.url);
```

#### Replace with

```vala
				var persistent_tls = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat",
						config.filesd_client.server_id),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
				};
				persistent_tls.ensure();
				var rpc = new OLLMrpc.Client("", "", config.filesd_client.url);
				rpc.configure_tls.connect((connection) => {
					connection.certificate = persistent_tls.certificate;
					connection.database = persistent_tls.trust;
				});
```

#### Remove

```vala
				var rpc = new OLLMrpc.Client("", "", config.filesd_client.url);
				this.project_manager.replace_rpc(rpc);
```

#### Replace with

```vala
				var persistent_tls = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat",
						config.filesd_client.server_id),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
				};
				persistent_tls.ensure();
				var rpc = new OLLMrpc.Client("", "", config.filesd_client.url);
				rpc.configure_tls.connect((connection) => {
					connection.certificate = persistent_tls.certificate;
					connection.database = persistent_tls.trust;
				});
				this.project_manager.replace_rpc(rpc);
```

### Keep the Android client alive for project and file RPC

**Why:** The Android library already provides `g_io_channel_unix_new`; the fd is only the readiness source, while `Bin.Stream` reads the decrypted TLS stream selected above.

**Where:** `libocrpc/Client.vala`, immediately after `this.connected = true` and at the end of the hello sequence.

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

#### Remove

```vala
			return true;
#endif
```

#### Replace with

```vala
			return true;
```

### Retain the TLS stream for the live connection

**Why:** The input and output wrappers do not keep the parent `GLib.TlsClientConnection` alive. Releasing the block-local TLS connection closes the stream before hello is sent.

**Where:** `libocrpc/Client.vala`, next to the socket field, after a successful TLS handshake, and in `disconnect`.

#### Add

```vala
		private GLib.TlsClientConnection? tls_connection;
```

#### Add

```vala
					this.tls_connection = tls_link;
```

#### Add

```vala
			this.tls_connection = null;
```

### Keep model availability from terminating file RPC

**Why:** Codebase-search model discovery is optional asynchronous work. A slow or unavailable model endpoint must not terminate `ollmfilesd` after project activation has already succeeded.

**Where:** `ollmfilesd/ProjectManager.vala`, in `rpc_activate_project` before `queue_project`.

#### Remove

```vala
			if (this.vector_scan != null) {
				if (this.vector_db == null
					|| this.vector_db.dimension == 0) {
					var probe_timeout_id = GLib.Timeout.add_seconds (15, () => {
						GLib.error (
							"vector embed probe timed out after 15 s; "
							+ "restart ollmfilesd after codebase_search config is fixed "
							+ "(TODO: reload daemon when app notifies config change)"
						);
						return false;
					});
					yield this.vector_scan.open_vector_db ();
					GLib.Source.remove (probe_timeout_id);
					if (this.vector_db == null
						|| this.vector_db.dimension == 0) {
						GLib.error (
							"vector embed unavailable; restart ollmfilesd after "
							+ "codebase_search config is fixed "
							+ "(TODO: reload daemon when app notifies config change)"
						);
					}
				}
				this.vector_scan.queue_project (project);
			}
```

#### Replace with

```vala
			if (this.vector_scan == null) {
				return;
			}
			if (this.vector_db == null || this.vector_db.dimension == 0) {
				yield this.vector_scan.open_vector_db ();
			}
			if (this.vector_db == null || this.vector_db.dimension == 0) {
				this.notification(new OLLMrpc.Notification() {
					method = "Banner.show",
					message = "Codebase search model is unavailable. Update the tool model in Settings."
				});
			}
			this.vector_scan.queue_project (project);
```

## Attempts / changelog

- **✔️** Captured physical-phone logcat, daemon log, certificate directory, and config after the failed requests.
- **✔️** Restarted the daemon on the current library and stopped the mistakenly started desktop app.
- **✔️** Completed the controlled current-build flow on `emulator-5554` using only the app, direct daemon Unix RPC, direct Avahi publication, and log capture.
- **✔️** Extended `test-rpc-filesd-pair` with direct `--arm-only` and `--list-approved` operations.
- **✔️** Reproduced the acceptance-test failure on `emulator-5554`: selecting Agent Pi and opening the project selector reports `ProjectManager.rpc_load_projects_from_db id=1: not connected` while `ollmfilesd` remains active and listening.
- **✔️** Fresh-installed the first reconnect fix on `emulator-5554`; state stayed `ENABLED` while Agent Pi remained hidden, but all three address probes failed with `Try again` and correctly ended `UNREACHABLE`.
- **✔️** With a blocking probe socket, captured a valid response with `error == null` and `msg == ""`, proving the remaining rejection was the probe's incorrect message requirement.
- **✔️** After accepting that hello, captured the persistent client failure `Unacceptable TLS certificate`, while the manually configured probe continued to authenticate with the same stored credentials.
- **✔️** Added the TLS configuration hook and shared Android read watch; the emulator completed TLS and logged `read watch started`, then failed the first hello read with `Connection is closed`, exposing the block-scoped TLS lifetime bug.
- **✔️** Retained the TLS connection; emulator startup then completed persistent hello, loaded projects, switched to `LIVE`, and exposed Agent Pi.
- **✔️** Selected OLLMchat and loaded its file list through the persistent RPC connection.
- **❌** Opening a listed file did not complete because `ollmfilesd` crashed and restarted during the preceding project scan. Journal evidence: `type id '0' is invalid`, `cannot initialize GValue with type '(null)'`, core dump, `status=5/TRAP`; Android then reconnected successfully but the selected file state had been cleared.
- **✔️** Symbolized the retained core and identified `ProjectManager.vala:335` as the fatal frame; the later process death was the timeout callback's `GLib.error`, not a TLS or file-parser crash.
- **✔️** Repeated project activation directly through `ollmfilesd --interactive` with the current data directory; filesystem and vector work completed when the configured model endpoint was reachable.
- **✔️** Built `ollmfilesd`, ran it directly without the desktop app, relaunched the installed app on `emulator-5554`, selected OLLMchat, opened a listed Markdown file, and confirmed `File.read` id 7 replied and the editor rendered the contents.
- **✔️** Installed the APK on the physical SM-S9380 and reproduced the post-pair failure: state `ENABLED`, three `Try again` parse failures, state `UNREACHABLE`, and the desktop-unavailable banner.
- **✔️** Implemented the documented `FileConnectionAdd` poll-and-retry pattern in `probe_addresses` and built the APK successfully.
- **✔️** Reconnected the physical phone, installed the rebuilt APK through the standard script, completed persistent hello, reached `LIVE`, exposed Agent Pi, activated OLLMchat, and received repeated `Folder.fetch_files` replies.

## Current state

- **✅** The original physical-phone pairing and reconnect failures are fixed: pairing persists, authenticated reconnect reaches `LIVE`, Agent Pi appears, and project files load.
- **✔️** Complete file opening passes on `emulator-5554`: a selected Markdown file produced a `File.read` reply and rendered without a daemon or client error.
- **ℹ️** Removal, approved-certificate re-add, and the remaining full-flow regression harness are tracked in `2026-10-08-android-remote-connection-lifecycle.md`.

## Next

- **ℹ️** Continue with `docs/bugs/2026-10-08-android-remote-connection-lifecycle.md`.
