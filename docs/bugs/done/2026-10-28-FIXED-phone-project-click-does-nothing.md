# Phone project click does nothing after Agent Pi starts

**Status:** ✅ User verified on the phone, 2026-10-29. Project navigation works.

## Problem

- 🔷 Phone SM-S9380, wireless debugging, `org.roojs.ollmchat.androidpoc` pid 13308, launch 2026-10-28 08:54:03.
- 🔷 Expected: a saved desktop connection that is switched on is probed at startup. When that probe reaches `LIVE`, Agent Pi opens and the project button shows the project list. A connection whose saved state is `DISABLED` stays off and opens Just Ask.
- 🔷 Actual: startup opened Just Ask and did not probe the desktop. The saved file connection was already disabled. Turning Enabled on did reach `LIVE` and did switch the session to Agent Pi. Closing Connections and tapping the project did nothing.
- 🔷 2026-10-28: disabled at startup is standard. It is not part of this bug.
- 🔷 `smallestScreenWidthDp=384`. The tablet cutoff is 600, so this window is the phone form. The log line is `android tablet:` because that is the message in `ollmapp_android_is_tablet`, including when the result is false.

## Evidence — startup did not check the desktop

- ℹ️ `adb -s adb-R5CY134DA0W-LrNhQc._adb-tls-connect._tcp logcat -d --pid=13308`
- ✔️ 08:54:04 `Startup: run connections=1`, then `initialize_model ok model=ornith-1.5:35b`. No `OllmchatWindow.vala:677` probe warning before the agent list.
- ✔️ 08:54:06 `agent-pi list state=OLL_MCHAT_SETTINGS_FILESD_CLIENT_STATE_DISABLED show=false`. The visible rows are Just Ask and Chatter. The bound row is Just Ask.
- ✔️ `initialize_client` probes only when `filesd_client.state` is `ENABLED`, `LIVE`, or `SOCKET` (`ollmapp/android/OllmchatWindow.vala`). `DISABLED` skips `probe_addresses` and skips the Agent Pi session. The "Checking desktop environment…" label is set only on that probe path. This launch did not decide the desktop was unavailable. It kept the saved off switch and opened Just Ask.
- 🚫 🔷 2026-10-28: leaving a `DISABLED` connection off, with no probe, is what the code does today. That skip is not the project-click defect.

## Startup retry

- 🔷 2026-10-28: at boot, probe a paired desktop whose saved state is `DISABLED`. A hello that succeeds turns it `LIVE` and opens Agent Pi. A miss leaves it `DISABLED` and opens Just Ask, with no unreachable dialog.
- ℹ️ `initialize_client` probes `ENABLED`, `LIVE`, and `SOCKET` only. `DISABLED` skips `probe_addresses`. The saved `addresses` lines are the hosts to try. `REQUESTED` and an empty `addresses` stay unprobed.
- ℹ️ A miss, a drop, and the Enabled switch all store `DISABLED`. Startup also rewrites `UNREACHABLE` to `DISABLED` before the probe. The boot try covers both a switch the user left off and the 08:55:13 give-up.
- 🔷 A miss that started as `DISABLED` does not emit `client.filesd.unreachable`. A miss that started as `ENABLED`, `LIVE`, or `SOCKET` still does.
- ℹ️ One pass of `probe_addresses`, two seconds per stored host. Four dead hosts hold the "Checking desktop environment…" label for about eight seconds.
- 🔷 Six states. Startup rewrites `UNREACHABLE` to `DISABLED` before this check, so the probe sees five. The only state that must not be probed is `REQUESTED`. The condition is `addresses != ""` and state is not `REQUESTED`. No switch.

### `ollmapp/android/OllmchatWindow.vala`

#### Remove

```vala
			var is_desktop_connected = false;
			var is_desktop_available = false;
			if (config.filesd_client.addresses != ""
				&& (config.filesd_client.state == FilesdClient.State.ENABLED
					|| config.filesd_client.state == FilesdClient.State.LIVE
					|| config.filesd_client.state == FilesdClient.State.SOCKET)) {
				is_desktop_connected = true;
				this.startup_status_label.label = "Checking desktop environment…";
				is_desktop_available = yield this.probe_addresses(config);
				this.startup_status_label.label = "Opening chat…";
			}
```

#### Replace with

```vala
			var is_desktop_connected = false;
			var is_desktop_available = false;
			var was_disabled = config.filesd_client.state == FilesdClient.State.DISABLED;
			if (config.filesd_client.addresses != ""
				&& config.filesd_client.state != FilesdClient.State.REQUESTED) {
				is_desktop_connected = true;
				this.startup_status_label.label = "Checking desktop environment…";
				is_desktop_available = yield this.probe_addresses(config);
				this.startup_status_label.label = "Opening chat…";
			}
```

#### Remove

```vala
			if (is_desktop_connected && !is_desktop_available) {
				config.filesd_client.state = FilesdClient.State.DISABLED;
				this.app.config.save();
				this.unavailable_notice = true;
				this.notification(new OLLMrpc.Notification() {
					method = "client.filesd.unreachable",
					id = this.probe_code
				});
			}
```

#### Replace with

```vala
			if (is_desktop_connected && !is_desktop_available) {
				config.filesd_client.state = FilesdClient.State.DISABLED;
				this.app.config.save();
				if (!was_disabled) {
					this.unavailable_notice = true;
					this.notification(new OLLMrpc.Notification() {
						method = "client.filesd.unreachable",
						id = this.probe_code
					});
				}
			}
```

## Evidence — enable did connect, then the project tap sent nothing

- ✔️ 08:54:16 tap, then `filesd state=ENABLED session=just-ask`. Agent Pi stays hidden (`show=false`) until the hello finishes. That matches the filter: only `LIVE` and `SOCKET` list Agent Pi.
- ✔️ 08:54:16 `connect ok hello id=1` on the persistent client. 08:54:16 `ProjectManager.rpc_load_projects_from_db` id=2 replied 08:54:18.
- ✔️ 08:54:18 `filesd state=LIVE session=just-ask`, then Agent Pi is listed and bound at position 0. `History.Manager` starts an Agent Pi session when state becomes `LIVE` and the current session is not already Agent Pi.
- ✔️ 08:54:18 `ProjectManager.rpc_load_projects_from_db` id=3, from `AgentPi.Factory.activate`, replied 08:54:19. No later project or file RPC in this process.
- ✔️ Taps at 08:54:20, 08:54:22, and 08:54:23 produced no application line and no `Gdk` popup. `ProjectSelector` logs `recent=`, `recent clicked`, `all clicked`, and `focus leave` when those controls run. None of those lines appear. `choose` is what sends `activate_project`. It did not run.
- ✔️ 08:54:24 a `Gdk` popup, 204×179 at (90, 19) on a 384×750 window. That is the agent `Gtk.DropDown`, not the project pull-over. A project pull-over is a `Gtk.Box` covering the coder, not a small popup under the header.
- ✔️ 08:54:18, in the same instant `CoderView` is constructed: `invalid cast from 'GtkTextBuffer' to 'GtkSourceBuffer'`, then `signal 'cursor-moved' is invalid` for that `GtkTextBuffer`, then `g_signal_connect_data` on a NULL instance. That is `new GtkSource.View()` inside `SourceView`. It does not open or hide the project list.

## Evidence — the pull-over is never parented

- ✔️ Phone and tablet `ProjectSelector.button.clicked` sets `this.selector.kind`, shows the project page, and sets `this.selector.visible = true`. It returns before `this.list.visible = true`. `this.list` is the desktop sheet. On the phone it stays hidden, which is the intended branch.
- ✔️ `CoderView` constructs `SelectorPull` and passes it into `ProjectSelector` and, on the phone, `File.Pullout`. The phone branch then does `this.append(header)` and `this.append(editor_layer)` only. The tablet branch overlays the file sheet. Neither branch appends or overlays `this.selector`.
- ✔️ `examples/oc-test-source-diff.vala` does parent it: `cover.add_overlay(this.selector_pull)` when `show_pull` is set. The product coder view does not.
- ✔️ A `Gtk.Widget` with no parent is not mapped. `visible = true` on that pull-over changes nothing on screen and sends no RPC. That is the tap at 08:54:20–23.

## Root cause

- ✔️ The phone project button opens `SelectorPull`, and `CoderView` never puts that pull-over in the window. The tap runs the button handler and the list stays off screen.
- 🚫 Do not add a click guard, a fallback empty project, or a second list. The desktop sheet is already parented and is the wrong surface for this form.
- 💩 The `GtkSource.View` buffer cast at construction is a separate failure in the same second. It is not why the project list stays hidden.
- 💩 After the activity stopped at 08:54:44, the desktop socket `tcp://192.168.0.16:8422` closed at 08:54:49 (`hup=true err=true`). Reconnect then timed out on `192.168.0.16`, `10.0.3.1`, `172.17.0.1`, and `10.9.188.16`, three passes, and at 08:55:13 set `DISABLED` while `session=agent-pi`, which hid Agent Pi again. That is later than the dead project tap. Leave it out of this fix.

## Proposed fix

- 🔷 Parent `SelectorPull` on the phone and tablet coder the same way the source-diff test window does: an overlay over the header and the editor, with the pull-over on top.
- 🚫 Do not parent it on the desktop form. Desktop keeps `projects.list`.

### `liboccoder/CoderView.vala`

#### Remove

```vala
			if (form == Form.TABLET) {
				var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
					hexpand = true,
					vexpand = true,
				};
				column.append(header);
				column.append(editor_layer);
				var cover = new Gtk.Overlay() {
					hexpand = true,
					vexpand = true,
					child = column,
				};
				var sheet = ((File.Overlay) this.files).list;
				sheet.halign = Gtk.Align.FILL;
				sheet.valign = Gtk.Align.FILL;
				cover.add_overlay(sheet);
				this.append(cover);
			}
			if (form != Form.TABLET) {
				this.append(header);
				this.append(editor_layer);
			}
```

#### Replace with

```vala
			if (form == Form.TABLET) {
				var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
					hexpand = true,
					vexpand = true,
				};
				column.append(header);
				column.append(editor_layer);
				var cover = new Gtk.Overlay() {
					hexpand = true,
					vexpand = true,
					child = column,
				};
				var sheet = ((File.Overlay) this.files).list;
				sheet.halign = Gtk.Align.FILL;
				sheet.valign = Gtk.Align.FILL;
				cover.add_overlay(sheet);
				cover.add_overlay(this.selector);
				this.append(cover);
			}
			if (form == Form.PHONE) {
				var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
					hexpand = true,
					vexpand = true,
				};
				column.append(header);
				column.append(editor_layer);
				var cover = new Gtk.Overlay() {
					hexpand = true,
					vexpand = true,
					child = column,
				};
				cover.add_overlay(this.selector);
				this.append(cover);
			}
			if (form == Form.DESKTOP) {
				this.append(header);
				this.append(editor_layer);
			}
```

## Attempts / changelog

- ℹ️ 2026-10-28: phone logcat for pid 13308.
- ✔️ 2026-10-28: `CoderView` overlays `SelectorPull` on phone and tablet. `initialize_client` probes any paired state except `REQUESTED`. `was_disabled` stays on one line. A miss that started disabled does not show the unreachable dialog.
- 🔷 2026-10-28: user asked for a boot probe of a disabled paired desktop. Success turns it live. A miss stays disabled and does not show the unreachable dialog.

## Next

- ✅ 2026-10-29: user confirmed phone project navigation works.
- 🔷 The boot probe of a disabled paired desktop was not called out again. It stays in this log as part of the same change.
- 💩 The `GtkTextBuffer` / `GtkSourceBuffer` cast while `SourceView` is constructed was left out of this bug.
- 💩 The socket close about five seconds after the activity stops, and the following probe timeouts that hide Agent Pi, were left out of this bug.
