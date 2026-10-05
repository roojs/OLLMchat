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

## Next

- **⏳** **🔷** Rebuild the chat POC APK, install on emulator-5554.
- **⏳** **💩** With Allow New Device open on the desktop, the dialog should stay on Listening with no PIN row, then show the PIN row with `host:port` once `poll` returns a hit. Log should show `android pair: bound` and no `no JavaVM` line.
