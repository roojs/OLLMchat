# Android remote connection removal and re-add lifecycle

**Status:** ⏳ disconnect give-up must ask Retry or Close before leaving Agent Pi; that dialog is not built yet

**Related:** ℹ️ `docs/bugs/done/2026-10-07-FIXED-android-pair-reply-wire.md`, ℹ️ `docs/bugs/done/2026-10-09-FIXED-file-read-string-limit.md`

## Problem

- **🔷** Removing a live remote desktop on Android must disconnect and clear its project state, hide Agent Pi, and switch back to Chatter.
- **🔷** Re-adding a removed remote desktop with an already-approved certificate must close the desktop Allow New Device window immediately after the PIN succeeds.
- **🔷** Keep a standalone Android regression flow for pairing, removal, approved-certificate re-add, Agent Pi activation, project/file loading, and opening a selected file.
- **🔷** When Android starts in Chatter after the file-daemon connection failure notification, the text editor remains visible even though Agent Pi is unavailable.
- **🔷** A remote desktop can initially report connected, but disabling and re-enabling it fails with `File server: Unacceptable TLS certificate`.
- **🔷** Disabling a working remote desktop must select Just Ask and hide Agent Pi/editor state; re-enabling currently exposes Agent Pi even when TLS reconnection fails.
- **🔷** The phone reports that the pairing number was accepted, but the desktop approved-certificate list does not add the phone.
- **🔷** Opening the project selector can produce no search response, progress indication, toast, or error; restarting the app makes project search work.
- **🔷** A dropped desktop connection is not the Enabled switch. The switch still leaves Agent Pi immediately and selects Just Ask.
- **🔷** After a drop, retry the desktop a few times. Giving up must not turn off Agent Pi or hide the editor by itself.
- **🔷** Giving up shows a dialog in the style of the model-unavailable alert. That alert's Configure action is not part of this dialog.
- **🔷** The dialog offers Retry and Close. Retry runs the connection attempt again. Close is the trigger that deactivates Agent Pi, hides the editor, and starts a new Chatter session. Close does not quit the app.
- **🔷** `reconnect` reports the client state. It does not create a session or pick an agent. `AgentDropdown` already watches `filesd_client.state` and already switches sessions when the agent changes. That is the response to a drop.

## Evidence

- **✔️** On the physical SM-S9380, removing the live remote desktop removed its settings row but left Agent Pi active and visible.
- **✔️** Desktop cache log: `ClientCert.pair` armed a new pairing window at 09:23:32, no `event.pair` arrived, and `ClientCert.pair` cleared it at the 09:24:32 timeout.
- **✔️** Phone log at 09:23:40 shows the re-add changed state to `ENABLED` and sent only authenticated `RPC-Daemon.hello`; it sent no `ClientCert.request_registration`.
- **✔️** A fresh registration at 09:10 received `event.pair`; the desktop immediately called `ClientCert.pair` with an empty PIN and closed correctly.
- **✔️** The initial 07:58 connection-loss notification followed the deliberate `ollmfilesd` service restart at 07:58:36; Android had connected successfully before the restart.
- **✔️** At 08:06:45, disabling the working connection changed filesd state to `DISABLED` and hid Agent Pi from the dropdown, but the active session remained `agent-pi`.
- **✔️** At 08:06:53, the settings-row reconnect failed with `Unacceptable TLS certificate`; 46 milliseconds later the Android window reconnect path completed authenticated hello with the stored credentials and restored state `LIVE`.
- **✔️** The 08:04 approved-certificate re-add sent `ClientCert.pair` over the approved TLS connection, emitted `event.pair`, closed the desktop pairing window, and then completed hello without issuing a duplicate certificate.
- **✔️** A direct `ClientCert.approved_certs` query returns 15 approved rows, but the desktop startup log contains no `ClientCert.approved_certs` request.
- **✔️** After runtime re-add, the project popup logged `filtered=0` and sent no project-list RPC. After restart, startup sent `ProjectManager.rpc_load_projects_from_db`, the project selector loaded, and the physical phone completed `Folder.fetch_files`, project activation, and `File.read`.
- **✔️** The live Android read watch later logged `Try again` and disconnected three times even though each reconnect immediately completed hello, exposing a separate TLS readiness race in the persistent channel.
- **✔️** The updated disable branch ran at 08:32:08, selected Just Ask, disconnected the old RPC, and hid Agent Pi. The old RPC's disconnect notification immediately invoked `reconnect`, which restored `LIVE` and Agent Pi 130 milliseconds later.
- **✔️** The desktop process started at 08:30 from the 07:55 installed binary; the certificate-list fix exists only in the 08:27 build tree and has not yet been installed or tested.
- **ℹ️** Physical browsing reached `File.read` id 9 and then failed because the file body exceeded the bin string cap. That defect is `docs/bugs/done/2026-10-09-FIXED-file-read-string-limit.md`.

## Root cause

- **✔️** The removal callback replaces `config.filesd_client` with a new object. `AgentDropdown.wire` captured the original object and listens to its `state` notification, so replacement emits no notification and the filter continues to expose Agent Pi from stale `LIVE` state.
- **✔️** The removal callback's only live cleanup is `FileConnectionRow.reconnect(false)`, which is compiled out on Android. The remote RPC and project state remain live and no Chatter session is selected.
- **✔️** `FileConnectionAdd.request` skips `ClientCert.request_registration` whenever the per-server CA already exists. Re-adding a removed connection therefore reuses its approved certificate and performs hello without sending the PIN or triggering the daemon's `event.pair`.
- **✔️** `ClientCert.pair` already owns the pairing PIN. The TLS request gate can permit this existing call only after validating an approved certificate, avoiding a new RPC method and duplicate certificate issuance.
- **✔️** The Enabled switch calls `FileConnectionRow.reconnect(true)` on Android. That path constructs a generic remote `OLLMrpc.Client` without the stored client certificate and CA, so it emits the TLS error before the separately triggered Android window reconnect succeeds.
- **✔️** Disabling the switch changes only `FilesdClient.state`; unlike removal or unreachable reconnect handling, it does not disconnect the RPC or replace the active Agent Pi session with Just Ask.
- **✔️** `ConnectionsPage` calls `render_approved` during construction, before the desktop project manager is available, so it returns immediately. `load_config` wires `event.pair` later but neither loads nor refreshes the approved list.
- **✔️** Runtime reconnect sets state `LIVE` after hello but does not call `ProjectManager.rpc_load_projects_from_db`; the project selector therefore remains empty until startup performs that load.
- **✔️** `switch_to_session` creates the replacement agent through `ensure_agent_handler` and does not emit `agent_deactivated`. `AgentPi.Factory.deactivate` is what calls `schedule_pane_update(false)`. A Chatter or Just Ask switch therefore leaves the editor pane up. The signal is now emitted when the agent name changes. Phone not retested.
- **✔️** `OllmchatWindow.reconnect` tries three passes, then sets `UNREACHABLE`, shows `The desktop environment is unavailable.`, and switches to Chatter immediately. There is no Retry or Close choice, so the editor is not waiting on the user.
- **✔️** The same session construction is copied in the startup unavailable branch, in `FileConnectionRow` on disable, and in `ConnectionsPage` on removal. `AgentDropdown.wire` already refreshes the agent list from `filesd_client.state` and is the code that calls `switch_to_session` for an agent change.
- **✔️** The persistent Android IO watch can call `Bin.Stream.parse` before TLS has decrypted readable application data; `GLib.IOError.WOULD_BLOCK` is currently treated as a fatal transport error instead of a readiness retry.
- **✔️** `OllmchatWindow.reconnect` checks `DISABLED` only after exhausting probes. A disconnect callback can therefore enter the probe/connect loop while disabled and restore the connection that the user just turned off.
- **ℹ️** The `File.read` body-size failure is tracked in `docs/bugs/done/2026-10-09-FIXED-file-read-string-limit.md`. It is not part of this lifecycle.

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

### Keep the Enabled switch on the Android lifecycle path

**Why:** The settings-row reconnect does not configure Android's stored TLS credentials. Disabling must also disconnect and clear Agent Pi state instead of only hiding its dropdown row.

**Where:** `ollmapp/SettingsDialog/FileConnectionRow.vala`, in the Enabled switch callback after saving the new state.

#### Remove

```vala
				if (this.client.state != FilesdClient.State.ENABLED) {
					return;
				}
				this.reconnect.begin(true);
```

#### Replace with

```vala
#if ANDROID
				if (this.client.state == FilesdClient.State.DISABLED) {
					/* Android has no local file daemon after remote disable.
					 * Clear remote project state and return to Just Ask. */
					manager.replace_rpc(new OLLMrpc.Client(
						GLib.Path.build_filename(
							GLib.Environment.get_user_data_dir(), "ollmchat"),
						"ollmfilesd.pid", "ollmfilesd.sock"));
					var empty = this.win.history_manager.create_new_session();
					empty.project_path = this.win.history_manager.session.project_path;
					empty.agent_name = "just-ask";
					this.win.chat_widget.switch_to_session.begin(empty);
					return;
				}
				this.win.reconnect.begin();
#else
				if (this.client.state != FilesdClient.State.ENABLED) {
					return;
				}
				this.reconnect.begin(true);
#endif
```

### Load the approved-certificate list after the project manager exists

**Why:** The constructor's early `render_approved` call runs before the desktop project manager exists. Settings load must fetch the list, and successful pairing must refresh it.

**Where:** `ollmapp/SettingsDialog/ConnectionsPage.vala`, in `load_config`.

#### Remove

```vala
			if (this.pair_wired || this.dialog.parent.project_manager == null) {
				return;
			}
			this.pair_wired = true;
			this.dialog.parent.project_manager.notification.connect((notif) => {
				if (notif.method != "event.pair") {
					return;
				}
				this.pairing_dialog.result(notif.action);
			});
```

#### Replace with

```vala
			if (this.dialog.parent.project_manager == null) {
				return;
			}
			this.render_approved.begin();
			if (this.pair_wired) {
				return;
			}
			this.pair_wired = true;
			this.dialog.parent.project_manager.notification.connect((notif) => {
				if (notif.method != "event.pair") {
					return;
				}
				this.pairing_dialog.result(notif.action);
				if (notif.action == "done") {
					this.render_approved.begin();
				}
			});
```

### Load projects on every successful Android reconnect

**Why:** `ProjectManager.replace_rpc` clears cached projects. Runtime reconnect must reload them and expose progress or failure before publishing `LIVE`.

**Where:** `ollmapp/android/OllmchatWindow.vala`, in `reconnect` after persistent hello succeeds.

#### Add

```vala
				this.notification(new OLLMrpc.Notification() {
					method = "client.project.load_start"
				});
				try {
					yield this.project_manager.rpc_load_projects_from_db();
				} catch (GLib.Error e) {
					this.notification(new OLLMrpc.Notification() {
						method = "Alert.show",
						message = "Could not load projects: " + e.message
					});
				}
				this.notification(new OLLMrpc.Notification() {
					method = "client.project.load_end"
				});
```

### Keep the persistent TLS read watch on `WOULD_BLOCK`

**Why:** Raw socket readiness can be consumed by TLS without producing decrypted application data. The persistent event-loop watch must wait for the next readiness event instead of disconnecting a healthy RPC channel.

**Where:** `libocrpc/Client.vala`, in `poll_drain_readable`.

#### Remove

```vala
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				this.disconnect();
				return true;
			}
```

#### Replace with

```vala
			} catch (GLib.IOError e) {
				if (e.code == GLib.IOError.WOULD_BLOCK) {
					/* TLS consumed raw readiness without yielding application
					 * data. Keep the event-loop watch for the next readiness. */
					return true;
				}
				GLib.warning("%s", e.message);
				this.disconnect();
				return true;
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				this.disconnect();
				return true;
			}
```

### Do not reconnect while the remote desktop is disabled

**Why:** Replacing the live RPC during disable emits its disconnect notification. `reconnect` must reject that stale callback before probing or connecting.

**Where:** `ollmapp/android/OllmchatWindow.vala`, at the start of `reconnect`.

#### Add

```vala
			switch (config.filesd_client.state) {
				case FilesdClient.State.REQUESTED:
				case FilesdClient.State.DISABLED:
					this.reconnecting = false;
					return;
				default:
					break;
			}
```

### Emit the agent change when the session switch changes agents

**Why:** `AgentPi.Factory.deactivate` hides the editor pane. `switch_to_session` never emits `agent_deactivated`, so Chatter and Just Ask leave that pane up.

**Where:** `libollmchat/History/Manager.vala`, in `switch_to_session`.

#### Remove

```vala
			this.session.deactivate();
```

#### Replace with

```vala
			var previous_agent_name = this.session.agent_name;
			this.session.deactivate();
```

#### Remove

```vala
			loaded_session.ensure_agent_handler();

			this.session_activated(loaded_session);
```

#### Replace with

```vala
			loaded_session.ensure_agent_handler();
			/* The replacement session already carries its agent name, so
			 * activate_agent emits nothing. Pane hide listens here. */
			if (previous_agent_name != ""
				&& previous_agent_name != loaded_session.agent_name) {
				this.agent_deactivated(this.agent_factories.get(previous_agent_name));
			}
			if (previous_agent_name != loaded_session.agent_name) {
				this.agent_activated(this.get_active_agent());
			}

			this.session_activated(loaded_session);
```

### Report a dropped desktop without switching session in the window

**Why:** `reconnect` is the client retry. `AgentDropdown` is what changes the agent and the session. Giving up only publishes `UNREACHABLE`. The dropdown's existing state listener asks Retry or Close.

**Where:** `ollmapp/android/OllmchatWindow.vala`, in `reconnect`, after the three passes fail.

#### Remove

```vala
			config.filesd_client.state = FilesdClient.State.UNREACHABLE;
			this.app.config.save();
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
			config.filesd_client.state = FilesdClient.State.UNREACHABLE;
			this.app.config.save();
			this.notification(new OLLMrpc.Notification() {
				method = "client.filesd.unreachable"
			});
```

**Where:** `ollmapp/AgentDropdown.vala`, in the `filesd_client.notify["state"]` handler, after the list filter refresh.

#### Add

```vala
#if ANDROID
				if (active.name != "agent-pi") {
					return;
				}
				switch (filesd_client.state) {
					case FilesdClient.State.UNREACHABLE:
						break;
					default:
						return;
				}
				var alert = new Adw.AlertDialog(
					"Desktop Unavailable",
					"The desktop environment is unavailable."
				);
				alert.add_response("close", "Close");
				alert.add_response("retry", "Retry");
				alert.set_response_appearance("retry", Adw.ResponseAppearance.SUGGESTED);
				var desktop = this.host as OLLMchat.ChatDesktopInterface;
				alert.choose.begin((Gtk.Window) this.host, null, (obj, res) => {
					if (alert.choose.end(res) == "retry") {
						desktop.notification(new OLLMrpc.Notification() {
							method = "client.filesd.retry"
						});
						return;
					}
					var empty = this.host.history_manager.create_new_session();
					empty.project_path = this.host.history_manager.session.project_path;
					empty.agent_name = "chatter";
					this.host.chat_widget.switch_to_session.begin(empty);
				});
#endif
```

**Where:** `ollmapp/android/OllmchatWindow.vala`, in the `notification` handler.

#### Add

```vala
				if (notif.method == "client.filesd.retry") {
					this.reconnecting = true;
					this.reconnect.begin();
					return;
				}
```

- **🚫** Do not create a session inside `reconnect` or the startup unavailable branch.
- **🚫** Do not add Configure. That belongs to the model and connection startup alerts.
- **🚫** Do not quit the app on Close. `AndroidStartup.show_settings` quits when the user declines Configure. This Close only leaves Agent Pi.
- **🚫** Do not show this dialog from the Enabled switch. Disable still selects Just Ask immediately.

## Attempts / changelog

- **✔️** Correlated physical-phone logcat with `/home/alan/.cache/ollmchat/ollmchat.debug.log`.
- **✔️** Confirmed fresh registration closes the window and approved-certificate reuse does not emit `event.pair`.
- **✔️** Built and installed the current Android APK through the standard scripts, installed the current desktop build, and restarted `ollmfilesd`.
- **✔️** Physical-phone testing reproduced the startup editor-state mismatch, TLS failure after disable/re-enable, missing approved-certificate row after accepted PIN, and silent project-selector failure until restart.
- **✔️** The follow-up proposals are in the working tree: removal returns to Chatter, approved re-add calls `ClientCert.pair`, the Enabled switch uses the Android reconnect path and selects Just Ask on disable, `load_config` loads and refreshes the approved list, runtime reconnect loads projects before `LIVE`, `reconnect` returns immediately while `REQUESTED` or `DISABLED`, and the persistent read watch keeps `WOULD_BLOCK`.
- **ℹ️** That tree has not been installed or run on the phone. The 08:30 desktop process was still the 07:55 binary, so the certificate-list load was not in that pass.
- **ℹ️** The `File.read` body longer than 32767 bytes was split out and closed in `docs/bugs/done/2026-10-09-FIXED-file-read-string-limit.md`. The codec round-trip passed. The phone file open was not repeated.
- **✔️** `switch_to_session` now emits `agent_deactivated` and `agent_activated` when the agent name changes. `AgentPi.Factory.deactivate` hides the editor pane on the way to Chatter or Just Ask.
- **ℹ️** Pattern for the give-up dialog is `AndroidStartup.show_settings`: `Adw.AlertDialog` with Close plus one suggested action. That action is Configure and declining it quits. The disconnect dialog keeps Close and uses Retry instead.

## Next

- **🔷** ⏳ After the three reconnect passes fail, publish `client.filesd.unreachable` and let `AgentDropdown` ask Retry or Close. Leave Agent Pi only on Close.
- **🔷** ⏳ Install this tree on the phone and desktop, then rerun removal, approved-certificate re-add, disable/enable, the approved list, project search, and a dropped connection.
- **🔷** ⏳ Complete the standalone Android full-flow regression harness.
