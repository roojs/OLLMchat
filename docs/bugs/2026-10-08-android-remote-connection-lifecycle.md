# Android remote connection removal and re-add lifecycle

**Status:** ⏳ root causes confirmed; fixes approved and proposed

**Related:** ℹ️ `docs/bugs/done/2026-10-07-FIXED-android-pair-reply-wire.md`

## Problem

- **🔷** Removing a live remote desktop on Android must disconnect and clear its project state, hide Agent Pi, and switch back to Chatter.
- **🔷** Re-adding a removed remote desktop with an already-approved certificate must close the desktop Allow New Device window immediately after the PIN succeeds.
- **🔷** Keep a standalone Android regression flow for pairing, removal, approved-certificate re-add, Agent Pi activation, project/file loading, and opening a selected file.

## Evidence

- **✔️** On the physical SM-S9380, removing the live remote desktop removed its settings row but left Agent Pi active and visible.
- **✔️** Desktop cache log: `ClientCert.pair` armed a new pairing window at 09:23:32, no `event.pair` arrived, and `ClientCert.pair` cleared it at the 09:24:32 timeout.
- **✔️** Phone log at 09:23:40 shows the re-add changed state to `ENABLED` and sent only authenticated `RPC-Daemon.hello`; it sent no `ClientCert.request_registration`.
- **✔️** A fresh registration at 09:10 received `event.pair`; the desktop immediately called `ClientCert.pair` with an empty PIN and closed correctly.

## Root cause

- **✔️** The removal callback replaces `config.filesd_client` with a new object. `AgentDropdown.wire` captured the original object and listens to its `state` notification, so replacement emits no notification and the filter continues to expose Agent Pi from stale `LIVE` state.
- **✔️** The removal callback's only live cleanup is `FileConnectionRow.reconnect(false)`, which is compiled out on Android. The remote RPC and project state remain live and no Chatter session is selected.
- **✔️** `FileConnectionAdd.request` skips `ClientCert.request_registration` whenever the per-server CA already exists. Re-adding a removed connection therefore reuses its approved certificate and performs hello without sending the PIN or triggering the daemon's `event.pair`.
- **✔️** `ClientCert.pair` already owns the pairing PIN. The TLS request gate can permit this existing call only after validating an approved certificate, avoiding a new RPC method and duplicate certificate issuance.

## Proposed changes

### Remove the live Android connection

**Why:** Mutating the existing `FilesdClient` emits the state notification observed by `AgentDropdown`. Android must then drop the remote RPC state and select Chatter because it has no local file daemon fallback.

**Where:** `ollmapp/SettingsDialog/ConnectionsPage.vala`, in the `FileConnectionRow.remove_requested` callback.

#### Remove

```vala
				var row = this.file_connection_row;
				this.dialog.app.config.filesd_client =
					new OLLMchat.Settings.FilesdClient();
				this.render_file_connection();
				this.dialog.app.config.save();
				if (!was_live) {
					return;
				}
#if !ANDROID
				row.reconnect.begin(false);
#endif
```

#### Replace with

```vala
#if !ANDROID
				var row = this.file_connection_row;
#endif
				/* AgentDropdown listens to this object. Mutating its state
				 * notifies the filter before the connection data is cleared. */
				client.state = FilesdClient.State.REQUESTED;
				client.url = "";
				client.addresses = "";
				client.server_id = "";
				this.render_file_connection();
				this.dialog.app.config.save();
				if (!was_live) {
					return;
				}
#if ANDROID
				/* Android has no local file daemon to reconnect after removal.
				 * Drop the remote RPC state and return to Chatter. */
				var data_dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "ollmchat");
				this.dialog.parent.project_manager.replace_rpc(
					new OLLMrpc.Client(data_dir, "ollmfilesd.pid", "ollmfilesd.sock"));
				var empty = this.dialog.parent.history_manager.create_new_session();
				empty.project_path = this.dialog.parent.history_manager.session.project_path;
				empty.agent_name = "chatter";
				this.dialog.parent.chat_widget.switch_to_session.begin(empty);
#else
				row.reconnect.begin(false);
#endif
```

### Complete pairing with the existing RPC

**Why:** An approved Android certificate skips registration on re-add, so it must submit the current PIN through the existing `ClientCert.pair` RPC before hello. The normal TLS request gate proves the certificate is approved.

**Where:** `ollmfilesd/SslConnection.vala`, in `allow_request`.

#### Remove

```vala
			switch (request.method) {
				case "ClientCert.client_cert":
				case "ClientCert.pair":
					this.reply(request, new OLLMrpc.Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "local admin only")
					});
					return false;
			}
			if (request.method == "ClientCert.request_registration") {
				return true;
			}
```

#### Replace with

```vala
			switch (request.method) {
				case "ClientCert.client_cert":
					this.reply(request, new OLLMrpc.Response() {
						error = new OLLMrpc.Error(
							(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "local admin only")
					});
					return false;
			}
			/* Approved TLS clients use ClientCert.pair to finish a pairing
			 * window. Let it pass through certificate validation below. */
			if (request.method == "ClientCert.request_registration") {
				return true;
			}
```

**Where:** `ollmfilesd/ClientCert.vala`, in `pair`.

#### Remove

```vala
			listen.pin = pin;
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
```

#### Replace with

```vala
			if (!(request.connection is SslConnection)) {
				listen.pin = pin;
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				return;
			}
			if (pin != listen.pin) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "number rejected")
				});
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.pair",
					action = "rejected"
				});
				return;
			}
			listen.pin = "";
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.pair",
				action = "done"
			});
```

**Where:** `ollmapp/android/FileConnectionAdd.vala`, before the existing registration branch.

#### Remove

```vala
			if (!GLib.FileUtils.test(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"),
					GLib.FileTest.EXISTS)) {
				var pin = this.pin_entry.text.strip();
				if (pin.length != 6) {
					this.error_occurred("Enter the six digits");
					return;
				}
```

#### Replace with

```vala
			var pin = this.pin_entry.text.strip();
			if (pin.length != 6) {
				this.error_occurred("Enter the six digits");
				return;
			}
			var has_credentials = GLib.FileUtils.test(
				GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), GLib.FileTest.EXISTS);
			if (!has_credentials) {
```

**Where:** `ollmapp/android/FileConnectionAdd.vala`, before the existing `RPC-Daemon.hello` write.

#### Remove

```vala
			if (has_credentials) {
				try {
					bin2.write(new OLLMrpc.Request() {
						method = "ClientCert.pair",
						args = OLLMrpc.args("s", pin)
					});
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return;
				}
				OLLMrpc.Bin.Serializable pair_parsed;
				var pair_wait = GLib.get_monotonic_time() + 10 * 1000000;
				while (true) {
					try {
						pair_parsed = bin2.parse();
					} catch (GLib.IOError e) {
						if (e.code != GLib.IOError.WOULD_BLOCK
							|| GLib.get_monotonic_time() >= pair_wait) {
							this.error_occurred(e.message);
							return;
						}
						var pair_poll = GLib.PollFD();
						pair_poll.fd = again.socket.fd;
						pair_poll.events = GLib.IOCondition.IN;
						GLib.poll(new GLib.PollFD[] { pair_poll }, 200);
						continue;
					} catch (GLib.Error e) {
						this.error_occurred(e.message);
						return;
					}
					if (!(pair_parsed is OLLMrpc.Response)) {
						continue;
					}
					break;
				}
				var pair_response = (OLLMrpc.Response) pair_parsed;
				if (pair_response.error != null) {
					this.error_occurred(pair_response.error.message);
					return;
				}
			}
```

#### Replace with

```vala
			if (has_credentials
				&& !this.complete_pairing(bin2, again.socket, pin)) {
				return;
			}
```

**Where:** `ollmapp/android/FileConnectionAdd.vala`, after `request`.

#### Add

```vala
		/**
		 * Completes a new pairing window with stored credentials.
		 *
		 * The server validates the stored certificate before accepting the
		 * current PIN through ''ClientCert.pair''.
		 *
		 * @param bin authenticated TLS bin stream
		 * @param socket raw socket polled while TLS buffers the reply
		 * @param pin current pairing PIN
		 * @return true when the server accepts the pairing
		 */
		private bool complete_pairing(
			OLLMrpc.Bin.Stream bin,
			GLib.Socket socket,
			string pin
		) {
			try {
				bin.write(new OLLMrpc.Request() {
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				});
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return false;
			}
			var wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					var response = bin.parse() as OLLMrpc.Response;
					if (response == null) {
						continue;
					}
					if (response.error != null) {
						this.error_occurred(response.error.message);
						return false;
					}
					return true;
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK
						|| GLib.get_monotonic_time() >= wait) {
						this.error_occurred(e.message);
						return false;
					}
					var poll = GLib.PollFD();
					poll.fd = socket.fd;
					poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { poll }, 200);
					continue;
				} catch (GLib.Error e) {
					this.error_occurred(e.message);
					return false;
				}
			}
		}
```

## Attempts / changelog

- **✔️** Correlated physical-phone logcat with `/home/alan/.cache/ollmchat/ollmchat.debug.log`.
- **✔️** Confirmed fresh registration closes the window and approved-certificate reuse does not emit `event.pair`.

## Next

- **🔷** ⏳ Apply the approved changes, rebuild and install through the standard scripts, then verify removal and approved-certificate re-add on the physical phone.
- **🔷** ⏳ Complete the standalone Android full-flow regression harness.
