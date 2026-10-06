# Add Remote Desktop — PIN before mDNS, browse never starts

**Status:** ⏳ JNI env comes from the app, not the GTK patch. Patch edit reverted. APK not rebuilt yet.

**Package:** `org.roojs.ollmchat.androidpoc`  
**Device:** emulator-5554, `sdk_gphone16k_x86_64`, API 37. APK is arm64-v8a under translation.  
**Related:** ℹ️ `ollmapp/android/FileConnectionAdd.vala`, `ollmapp/android/android-pair-browse.c`, `android/PairBrowse.java`, `android/OllmApplication.java`

---

## Problem

- **🔷** Add Remote Desktop shows the PIN row before any mDNS result. It should say Listening until a desktop is found, then show the PIN entry.
- **🔷** The phone never hears the desktop broadcast.

Reproduction: emulator, Settings, Connections, Remote Desktop Connection. Desktop Allow New Device can be open or not — the phone never reaches `NsdManager`.

---

## Evidence

- **✔️** The dialog group description and the label are both `Listening for connection`. The PIN `Adw.ActionRow` is added in the constructor and never hidden. Only the entry widget starts `visible = false`. The row title PIN is on screen immediately.
- **✔️** Logcat pid 13741, thread 13757 `GTK Thread`, every 200ms while the dialog is open:

```
android jni: no JavaVM helper=0x0 get_vms=0x0 count=0
```

- **✔️** No `NsdManager` / `NsdService` / `mdnsd` lines for that pid. `PairBrowse.start` is never reached, so the Java 30s timeout never runs. The Vala poll treats `""` as keep waiting, so the label stays on Listening forever.
- **✔️** `adb shell` on the emulator: the only `libnativehelper.so` is `/apex/com.android.art/lib64/libnativehelper.so`. There is no arm copy. `dlopen` from the translated arm64 process returns NULL (`helper=0x0`).
- **✔️** `ps -T -p 13741` names tid 13757 `GTK Thread`. `gdk_android_runtime_gtk_thread` creates that thread and attaches it. Browse runs on that thread (`Idle` / `Timeout`), not on the Java main thread `chat.androidpoc`.
- **✔️** The log is printed only after `gdk_android_toplevel_get_activity` returns an activity. That call uses `gdk_android_get_env` inside libgtk and `NewLocalRef`. GTK already has a `JNIEnv` on this thread. The browse code ignores it and looks up `JNI_GetCreatedJavaVMs` instead.
- **✔️** `gdk_android_get_env` is `LOCAL HIDDEN` in `libgtk-4.so`. `dlsym` cannot see it. `gdk_android_initialize` is `GLOBAL DEFAULT`.
- **ℹ️** This session did not check whether the desktop Avahi service was published. Discovery never called `discoverServices`, so a missing broadcast is not what this log shows.

---

## Root cause

- **✔️** UI: the PIN row is in the group from construction. Hiding the entry leaves the row.
- **✔️** Broadcast: `ollmapp_android_jni_env` cannot load `libnativehelper.so` in this process, so `android_pair_browse_start` returns before `PairBrowse.browse`. Nothing subscribes to `_rpc._tcp`.
- **✔️** `poll` then calls `FindClass("org/roojs/ollmchat/androidpoc/PairBrowse")`. GTK Thread was attached with `AttachCurrentThread`, so `FindClass` uses the boot loader and will not see that app class. A hit could not be reported even after the env lookup is fixed. `start` already loads the class through the activity class loader.

---

## Proposed fix

- **🔷** While waiting, the label is `Listening` and the PIN row is hidden. A `host:port` hit shows the row. `none` stays `No desktop found` with the row hidden.
- **🚫** Do not edit `android/pixiewood-wraps/gtk/android-bugs.patch`. `gdk_android_get_env` stays hidden.
- **🔷** `OllmApplication` replaces `RuntimeApplication` in the manifest. After `super.onCreate()` returns, `PairBrowse.bind` loads `ollmchat-android-poc` and calls `nativeBind`. That call receives a `JNIEnv` and keeps the `JavaVM`, the class, and the application context. Browse on the GTK thread uses `GetEnv` on that VM.
- **🚫** Do not add a multicast lock in this change. Retest discovery after the env works.
- **🚫** Do not change `android-partial-wake-lock.c` or `libocrpc/Client.vala`.

### 1. `ollmapp/android/FileConnectionAdd.vala` — constructor: Listening, PIN row hidden

**Why:** The row title is what shows before mDNS.  
**Where:** `FileConnectionAdd` constructor, the group, label, and PIN row.  
**Depends on:** none

#### Remove

```vala
			this.group = new Adw.PreferencesGroup() {
				description = "Listening for connection"
			};
			this.listen_label = new Gtk.Label("Listening for connection") {
				wrap = true,
				xalign = 0
			};
			this.group.add(this.listen_label);
			this.pin_entry = new Gtk.Entry() {
				placeholder_text = "Six digits",
				visible = false,
				max_length = 6
			};
			var pin_row = new Adw.ActionRow() {
				title = "PIN"
			};
			pin_row.add_suffix(this.pin_entry);
			this.group.add(pin_row);
```

#### Replace with

Label is Listening. The PIN row stays out of the dialog until a hit.

```vala
			this.group = new Adw.PreferencesGroup();
			this.listen_label = new Gtk.Label("Listening") {
				wrap = true,
				xalign = 0
			};
			this.group.add(this.listen_label);
			this.pin_entry = new Gtk.Entry() {
				placeholder_text = "Six digits",
				max_length = 6
			};
			this.pin_row = new Adw.ActionRow() {
				title = "PIN",
				visible = false
			};
			this.pin_row.add_suffix(this.pin_entry);
			this.group.add(this.pin_row);
```

#### Add — field after `private Gtk.Entry pin_entry;`

The constructor assigns this row. `show_add` and the poll hit show or hide it.

```vala
		private Adw.ActionRow pin_row;
```

### 2. `ollmapp/android/FileConnectionAdd.vala` — `show_add` and the poll hit

**Why:** Opening the dialog must hide the row again and reset the label.  
**Where:** `show_add`, the two lines that clear the entry and set the label; the poll callback lines that reveal the entry.  
**Depends on:** §1

#### Remove

```vala
			this.pin_entry.text = "";
			this.pin_entry.visible = false;
			this.listen_label.label = "Listening for connection";
```

#### Replace with

```vala
			this.pin_entry.text = "";
			this.pin_row.visible = false;
			this.listen_label.label = "Listening";
```

#### Remove

```vala
					this.found = hit;
					this.listen_label.label = hit;
					this.pin_entry.visible = true;
```

#### Replace with

```vala
					this.found = hit;
					this.listen_label.label = hit;
					this.pin_row.visible = true;
```

### 3. App binds the VM — no GTK patch

**🚫** Do not add `gdk_android_ollmchat_jni_env` to the GTK patch.

**✔️** `android/OllmApplication.java` subclasses `RuntimeApplication`. The manifest application name is rewritten in `patch_android_manifest`. `PairBrowse.bind` calls `nativeBind`. `android-pair-browse.c` stores that `JavaVM` and uses `GetEnv` on the GTK thread. The class and application context are global refs taken on the main thread, so `FindClass` on GTK Thread is not used.

---

## Attempts / changelog

- **✔️** Opened Add Remote Desktop on emulator-5554. PIN row visible. Logcat as above. No NsdManager lines.
- **ℹ️** GTK patch edit was reverted. `gdk_android_get_env` stays hidden.
- **✔️** `OllmApplication` binds the JavaVM after the GTK runtime is up. Browse no longer dlopens `libnativehelper.so`.
- **🔷** That product change was tested and did not hear the broadcast. Stop editing the chat app and the GTK patch for this.
- **💩** `android/pair-listen-probe/` is a separate app. It browses `_rpc._tcp` with `NsdManager`, stays on Listening until a foreign host resolves, then shows the PIN field.

## PIN submit 2026-10-06

- **✔️** Rebuilt APK, installed on emulator-5554. Log: `android pair: bound`. PIN submit was not tried in that step.
- **✔️** User entered the PIN. Logcat pid 17516, `FileConnectionAdd.vala:88`, five times: `Could not connect to 10.0.2.16: Connection refused`.
- **✔️** `10.0.2.16/24` is the emulator `wlan0` address. `eth0` is `10.0.2.15`.
- **✔️** `serviceDiscovery` for `_rpc._tcp` on that emulator lists `pair-probe-local` with `ip4: [10.0.2.16]` port 9753. That registration is the probe app on the emulator. Nothing listens on 9753.
- **✔️** Host `avahi-browse -rtk _rpc._tcp` shows only `pair-probe-host` port 9754 (`avahi-publish-service`, pid 443072). Addresses include `192.168.0.16`. `ollmfilesd` is listening on `192.168.0.16:8422` and `:8443` and is not in that browse.

## Phone test 2026-10-06 09:01

- **✔️** `/usr/bin/ollmfilesd` pid 173034 SIGTRAP at 09:01:15. Kernel: `int3` in `libglib-2.0.so`, file offset `0x73e0f` is `g_logv`. No coredump. The debug log was replaced by the restart at 09:01:16, so the fatal message is gone.
- **✔️** `~/.cache/ollmchat/ollmchat.debug.log` just before that: `09:00:58` `ClientCert.pair` id 9 replied, then `09:01:15` notification `event.pair`, then `ClientCert.pair` id 10, then `socket closed` / `disconnect abort ClientCert.pair id=10`.
- **✔️** `/usr/bin/ollmchat` pid 368450 SIGTRAP at 09:01:22, same `g_logv` int3. The debug log line is `Client.vala:775: ClientCert.pair id=11: not connected`. That line is `GLib.error`, which aborts.
- **ℹ️** `event.pair` with action `done` is what {@link OLLMapp.SettingsDialog.ConnectionsPage.load_config} sends into {@link OLLMapp.SettingsDialog.PairingDialog.result}, and `done` calls `ClientCert.pair` with an empty PIN.
- **ℹ️** Phone logcat for this attempt has no `org.roojs.ollmchat.androidpoc` lines of its own. The phone UI string that contains “try again” is the startup alert in `ollmapp/android/AndroidStartup.vala`.

## Fix

- **✔️** `libocrpc/Transport/Connection.vala` `on_input_ready`: a parse error stops that connection. It no longer `GLib.error`s, which aborted `ollmfilesd`.
- **✔️** `libocrpc/Client.vala` `call`, `call_sync`, `call_poll`: not connected throws. It no longer `GLib.error`s, which aborted `ollmchat` on `ClientCert.pair` id 11. `poll_drain_readable` disconnects on a parse error instead of aborting.
- **✔️** Rebuilt `build/libocrpc/libocrpc.so`. Restarted `ollmfilesd` (pid 610653) with `LD_LIBRARY_PATH` on that library. A dropped handshake logged `ssl handshake failed` and the same pid stayed up.
- **ℹ️** `/usr/bin/ollmchat` still loads `/lib/x86_64-linux-gnu/libocrpc.so` from Oct 5. Copying the new library there needs a password. That abort only runs when the daemon socket is already dead.

## Phone registration 2026-10-06 09:42

- **✔️** Daemon `~/.cache/ollmchat/ollmfilesd.debug.log`: `09:42:50.301` `ClientCert.request_registration`, then `ClientCert.pair` id 4 (PIN cleared, dialog closes), then `Connection.vala:343` `Unexpected early end-of-stream`.
- **✔️** Phone logcat pid 27707 thread 27730 `09:42:50.152`: `FileConnectionAdd.vala:88: Try again`. Cert files under `files/share/ollmchat/` stayed at `09:01`. The signed cert and CA were never stored.
- **✔️** `09:44:06` the user tapped Request again. Phone: `Server required TLS certificate`. Daemon: `ssl handshake failed: TLS connection peer did not send a certificate`. The PIN was already cleared, and that handshake does not send a client certificate.
- **✔️** GLib reports `EAGAIN` as the message `Try again` (`socket_set_error_lazy` uses `socket_strerror` for `G_IO_ERROR_WOULD_BLOCK`). The phone treated that as a failed registration and closed the socket. The daemon had already accepted the PIN.

## Fix

- **✔️** `ollmapp/android/FileConnectionAdd.vala`: the registration reply read and the hello read wait through `GLib.IOError.WOULD_BLOCK` instead of closing the socket. Both sockets are set blocking. The status line sits under the PIN, centered, with space above. Request stays off until that attempt finishes.

## Phone registration 2026-10-06 10:29

- **✔️** Phone logcat `FileConnectionAdd.vala:91`: `Error receiving data: Connection reset by peer` at 10:29:02 and 10:29:19. Cert files were written at 10:29 (`client.pem` signed by `OLLMrpc Product CA`, key modulus matches, CA bytes match the desktop CA).
- **✔️** Daemon log: `ClientCert.request_registration`, then `ClientCert.pair` (dialog closes), then `SslListen.vala:192: ssl handshake failed: Unacceptable TLS certificate`, then `Unexpected early end-of-stream` on the registration connection.
- **✔️** The process still running was pid 623731, started 09:40, `/usr/bin/ollmfilesd (deleted)`. Its string table is `SslListen.vala:192`. The build from 09:42 is `SslListen.vala:193`, which is the extra line `tls.database = cert.trust`. Without that database, GLib sets `UNKNOWN_CA` and `accept_certificate` returns false. The phone sees the reset on the hello handshake.
- **✔️** `Gio.TlsFileDatabase.verify_chain` on the pulled leaf is flags 0. A local `GTlsServerConnection` with the CA database accepts it. The same leaf against the 09:40 process was rejected. After `systemctl --user restart ollmfilesd` (pid 779770, line 193), that leaf completes the handshake and the daemon starts the RPC reader (`Unexpected early end-of-stream` only because the probe sent no request).

## Next

- **⏳** **🔷** Allow New Device, then Request on the phone again. The hello handshake should stay up, hello should finish, and the add dialog should close.
