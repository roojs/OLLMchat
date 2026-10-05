# Add Remote Desktop — PIN before mDNS, browse never starts

**Status:** ⏳ root cause confirmed on emulator-5554; fix proposed — await apply approval

**Package:** `org.roojs.ollmchat.androidpoc`  
**Device:** emulator-5554, `sdk_gphone16k_x86_64`, API 37. APK is arm64-v8a under translation.  
**Related:** ℹ️ `ollmapp/android/FileConnectionAdd.vala`, `ollmapp/android/android-pair-browse.c`, `android/PairBrowse.java`, `subprojects/gtk/gdk/android/gdkandroidollmchatpatch.c`

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
- **💩** Export GTK's existing env from the ollmchat GTK patch and call that. Cache the `PairBrowse` class from the activity loader in `start`. `poll` uses the cache.
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

### 3. `subprojects/gtk/gdk/android/gdkandroidollmchatpatch.c` — export the env GTK already has

**Why:** `gdk_android_get_env` works on GTK Thread and is hidden. The browse `.so` cannot `dlsym` it.  
**Where:** includes, then a new function after the bugs tag.  
**Depends on:** none

#### Add — include after `#include "config.h"`

The patch is compiled into libgtk, so this is the header that declares `gdk_android_get_env`.

```c
#include "gdkandroidinit-private.h"
```

#### Add — `gdk_android_ollmchat_jni_env`, after the `gdk_android_ollmchat_bugs_tag` line

Default visibility so the browse module can link it. Returns the env `gdk_android_toplevel_get_activity` already uses on this thread.

```c
__attribute__ ((visibility ("default")))
JNIEnv *
gdk_android_ollmchat_jni_env (void)
{
  return gdk_android_get_env ();
}
```

### 4. `ollmapp/android/android-pair-browse.c` — use that env, cache the class

**Why:** `dlopen("libnativehelper.so")` cannot succeed in this process. `FindClass` on GTK Thread cannot see the app class.  
**Where:** the includes and the env lookup; `start` after the class load; `poll` class lookup and its `DeleteLocalRef` of that class.  
**Depends on:** §3

#### Remove

```c
#include <dlfcn.h>
#include <jni.h>
#include <gdk/android/gdkandroid.h>

static JavaVM *ollmapp_android_vm = NULL;
```

#### Replace with

```c
#include <jni.h>
#include <gdk/android/gdkandroid.h>

extern JNIEnv *gdk_android_ollmchat_jni_env (void);

static jclass ollmapp_android_pair_cls = NULL;
```

#### Remove

```c
static JNIEnv *
ollmapp_android_jni_env (void)
{
	JNIEnv *env = NULL;
	jsize vm_count = 0;

	/* GTK loads this .so with g_module_open, which does not run JNI_OnLoad. */
	if (ollmapp_android_vm == NULL) {
		void *helper = dlopen ("libnativehelper.so", RTLD_NOW | RTLD_NOLOAD);
		jint (*get_vms) (JavaVM **, jsize, jsize *) = NULL;

		if (helper != NULL) {
			get_vms = dlsym (helper, "JNI_GetCreatedJavaVMs");
		}
		/* Arm translation loads the x86_64 helper in another
		 * linker namespace, so NOLOAD misses it. Load the
		 * arm64 helper, which forwards to that VM. */
		if (helper == NULL) {
			helper = dlopen ("libnativehelper.so", RTLD_NOW);
		}
		if (get_vms == NULL && helper != NULL) {
			get_vms = dlsym (helper, "JNI_GetCreatedJavaVMs");
		}
		if (get_vms == NULL) {
			get_vms = dlsym (RTLD_DEFAULT, "JNI_GetCreatedJavaVMs");
		}
		if (get_vms == NULL
			|| get_vms (&ollmapp_android_vm, 1, &vm_count) != JNI_OK
			|| vm_count < 1) {
			g_message ("android jni: no JavaVM helper=%p get_vms=%p count=%d",
				helper, (void *) get_vms, (int) vm_count);
			ollmapp_android_vm = NULL;
			return NULL;
		}
	}
	if ((*ollmapp_android_vm)->GetEnv (ollmapp_android_vm, (void **) &env,
		JNI_VERSION_1_6) == JNI_OK) {
		return env;
	}
	if ((*ollmapp_android_vm)->AttachCurrentThread (ollmapp_android_vm, &env,
		NULL) != JNI_OK) {
		return NULL;
	}
	return env;
}
```

#### Replace with

GTK Thread is already attached. A NULL env is a real failure.

```c
static JNIEnv *
ollmapp_android_jni_env (void)
{
	JNIEnv *env = gdk_android_ollmchat_jni_env ();
	if (env == NULL) {
		g_message ("android jni: GTK has no JNIEnv");
	}
	return env;
}
```

#### Remove

```c
	cls = ollmapp_android_load_class (env, activity,
		"org.roojs.ollmchat.androidpoc.PairBrowse");
	if (cls == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
```

#### Replace with

`start` keeps the class for `poll`. GTK Thread cannot `FindClass` an app class.

```c
	cls = ollmapp_android_load_class (env, activity,
		"org.roojs.ollmchat.androidpoc.PairBrowse");
	if (cls == NULL || (*env)->ExceptionCheck (env)) {
		g_message ("android pair: PairBrowse class missing");
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
	if (ollmapp_android_pair_cls != NULL) {
		(*env)->DeleteGlobalRef (env, ollmapp_android_pair_cls);
	}
	ollmapp_android_pair_cls = (*env)->NewGlobalRef (env, cls);
```

#### Remove

```c
	env = ollmapp_android_jni_env ();
	if (env == NULL) {
		return g_strdup ("");
	}
	cls = (*env)->FindClass (env, "org/roojs/ollmchat/androidpoc/PairBrowse");
	if (cls == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		if (cls != NULL) {
			(*env)->DeleteLocalRef (env, cls);
		}
		return g_strdup ("");
	}
```

#### Replace with

```c
	env = ollmapp_android_jni_env ();
	if (env == NULL || ollmapp_android_pair_cls == NULL) {
		return g_strdup ("");
	}
	cls = ollmapp_android_pair_cls;
```

#### Remove

```c
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, cls);
		return g_strdup ("");
	}
```

#### Replace with

`cls` is a global ref. Do not delete it here.

```c
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return g_strdup ("");
	}
```

#### Remove

```c
	if (value == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, cls);
		return g_strdup ("");
	}
```

#### Replace with

```c
	if (value == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return g_strdup ("");
	}
```

#### Remove

```c
	(*env)->DeleteLocalRef (env, value);
	(*env)->DeleteLocalRef (env, cls);
	return copy;
```

#### Replace with

```c
	(*env)->DeleteLocalRef (env, value);
	return copy;
```

---

## Attempts / changelog

- **✔️** Opened Add Remote Desktop on emulator-5554. PIN row visible. Logcat as above. No NsdManager lines.
- **ℹ️** No code change yet.

## Next

- **⏳** **🔷** Apply after approval, rebuild the chat POC APK, install on emulator-5554.
- **⏳** **💩** With Allow New Device open on the desktop, the dialog should stay on Listening with no PIN row, then show the PIN row with `host:port` once `poll` returns a hit. Log should show browse started and no `no JavaVM` line.
