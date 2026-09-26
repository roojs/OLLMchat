# 8.2.8.8 — Android `ChatDesktopInterface`: phone stack / tablet columns

**Status:** **PROPOSED** — Phase 1 hunks in tree (`✔️`)

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Split from:** [`RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) Phase 3.

**Depends on:**

- [`RPC-8.2.8.6`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) — Android `ProjectManager`, HTTPS takeover, full `liboccoder`, `notification` / `window_config()`
- [`RPC-8.2.8.2`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md) Phase 1 — Android browser `tool_toggle` on `chat_widget.view_stack`

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Android `OllmchatWindow` implements `OLLMchat.ChatDesktopInterface`.
- **🔷** Detect tablet once (device class). Phone keeps today's globe stack. Tablet always uses the landscape two-column shell.
- **🔷** Tablet: chatter | browser-or-editor. One right slot (`tab_view`). Fixed columns, not `Gtk.Paned`.
- **🔷** Tablet: lock landscape. No portrait / phone-stack fallback on that device.
- **🔷** Route the existing Android browser `tool_toggle` into that same secondary surface (stack on phone, right column on tablet).
- **🔷** Detect tablet the standard Android way (`smallestScreenWidthDp` / `sw600dp`). If that signal is not reachable from Vala/GTK, expose it (JNI / activity). Do not invent a Gdk width cutoff.
- **🔷** Tablet `tab_view()` is still an `Adw.ViewStack` so factory casts match desktop.
- **ℹ️** Agent Pi register is [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md). Startup hello, history, and bars are [`8.2.8.11`](RPC-8.2.8.11-URGENT-android-startup-history-bars.md). This plan only makes the host surface.

---

## Current behaviour

- **ℹ️** Android `OllmchatWindow` is `ChatUserInterface` only. Phase 2 on [`8.2.8.6`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) added `notification` as a class signal (not the interface).
- **ℹ️** Phone shell: `Gtk.Stack` (`startup` / `chat` / `history`). Browser globe toggles `chat_widget.view_stack` (`"chat"` vs tool name). No right pane.
- **ℹ️** Desktop split is `ollmapp/WindowPane.vala` (`Gtk.Paned` + `Adw.ViewStack tab_view`). Showing the pane **grows** the window. Not in `android_poc` sources.
- **ℹ️** `AgentPi.Factory.activate` casts the window to `ChatDesktopInterface` and `tab_view()` to `Adw.ViewStack`, then mounts `OLLMcoder.SourceView`.
- **ℹ️** GTK/Vala has no `smallestScreenWidthDp`. JNI already lives in `ollmapp/android/android-partial-wake-lock.c` (`JNI_OnLoad` + `gdk_android_toplevel_get_activity`). A second `.c` cannot add another `JNI_OnLoad`.

---

## Design decisions

- **🔷** `ChatDesktopInterface` is the host surface. No separate Android `activate` path.
- **🔷** Browser and editor share one secondary surface. Phone: full-stack swap. Tablet: chat stays visible, secondary is the other column.
- **🔷** Tablet vs phone is a **device class**, not a live wide/narrow cutoff. A tablet does not flip to the phone shell when rotated.
- **🔷** Tablet UI is landscape only. Do not show a vertical (portrait) phone layout on tablet.
- **🔷** Tablet split is a **fixed** two-column layout. Not a user-draggable sash (`Gtk.Paned` / desktop `WindowPane`).
- **🔷** Lock tablet orientation on the activity (`sensorLandscape`) so the phone stack never appears there.
- **🔷** Columns are a `Gtk.Box`, not `WindowPane`. No extra tablet tab API.
- **💩** Put the JNI on the existing wake-lock `.c` / `.h` (shared `JNI_OnLoad`). Do not add a second Android C file.
- **💩** One `Adw.ViewStack pane_stack` is `tab_view()` on both device classes. Phone: named `"pane"` child of `chat_widget.view_stack`. Tablet: the right column, hidden until `schedule_pane_update(true)`.
- **💩** `smallestScreenWidthDp >= 600` is tablet. Missing Android toplevel / JNI env → phone (do not guess from Gdk).
- **💩** `SCREEN_ORIENTATION_SENSOR_LANDSCAPE` (`6`) for the tablet lock.
- **ℹ️** `register_default_agents()` stays Chatter only. Coder factories stay off Android.

Named members this plan adds: `pane_stack`, `is_tablet`, `ChatDesktopInterface` methods (`session_agent`, `above_input_widget`, `chat_message_queue`, `tab_view`, `schedule_pane_update`, `scroll_to_message`), C `ollmapp_android_is_tablet` / `ollmapp_android_lock_landscape`.

---

## Phase 1 — `ChatDesktopInterface` + phone / tablet pane (`✔️`)

Edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

### 1. `ollmapp/android/android-partial-wake-lock.h` — tablet JNI

**Why:** Vala/GTK cannot read `smallestScreenWidthDp`. Same header already exposes the wake-lock JNI.

**Where:** after `ollmapp_android_set_streaming_foreground`.

**Depends on:** none.

#### Add — after `void ollmapp_android_set_streaming_foreground (GtkWindow *window, gboolean enable);`

```c
gboolean ollmapp_android_is_tablet (GtkWindow *window);
void ollmapp_android_lock_landscape (GtkWindow *window);
```

---

### 2. `ollmapp/android/android-partial-wake-lock.c` — `is_tablet` + lock landscape

**Why:** Device class from the activity `Configuration`. Tablet lock is `setRequestedOrientation(6)`. Reuse `ollmapp_android_jni_env` / `gdk_android_toplevel_get_activity` (a second `.c` cannot define `JNI_OnLoad`).

**Where:** after `ollmapp_android_set_streaming_foreground`. This `.c` is only in `android_poc_sources` — no `#ifdef __ANDROID__` / desktop stubs.

**Depends on:** §1.

Wake-lock checks `ExceptionCheck` after loading an **app** class that can be missing from the APK. These calls are framework `Activity` / `Resources` / `Configuration` — same straight walk as `ollmapp_android_load_class`. Keep the GDK surface / activity / env entry (native may not be an Android toplevel). No per-hop null trees, no `window == NULL`.

#### Add — after `ollmapp_android_set_streaming_foreground`

```c
gboolean
ollmapp_android_is_tablet (GtkWindow *window)
{
	GdkSurface *surface;
	jobject activity;
	JNIEnv *env;
	jclass activity_cls;
	jmethodID get_resources;
	jobject resources;
	jclass resources_cls;
	jmethodID get_configuration;
	jobject configuration;
	jclass configuration_cls;
	jfieldID sw_field;
	jint sw;

	surface = gtk_native_get_surface (GTK_NATIVE (window));
	if (surface == NULL || !GDK_IS_ANDROID_TOPLEVEL (surface)) {
		return FALSE;
	}
	activity = gdk_android_toplevel_get_activity (GDK_ANDROID_TOPLEVEL (surface));
	if (activity == NULL) {
		return FALSE;
	}
	env = ollmapp_android_jni_env ();
	if (env == NULL) {
		return FALSE;
	}
	activity_cls = (*env)->GetObjectClass (env, activity);
	get_resources = (*env)->GetMethodID (env, activity_cls, "getResources",
		"()Landroid/content/res/Resources;");
	resources = (*env)->CallObjectMethod (env, activity, get_resources);
	resources_cls = (*env)->GetObjectClass (env, resources);
	get_configuration = (*env)->GetMethodID (env, resources_cls,
		"getConfiguration", "()Landroid/content/res/Configuration;");
	configuration = (*env)->CallObjectMethod (env, resources, get_configuration);
	configuration_cls = (*env)->GetObjectClass (env, configuration);
	sw_field = (*env)->GetFieldID (env, configuration_cls,
		"smallestScreenWidthDp", "I");
	sw = (*env)->GetIntField (env, configuration, sw_field);
	(*env)->DeleteLocalRef (env, configuration_cls);
	(*env)->DeleteLocalRef (env, configuration);
	(*env)->DeleteLocalRef (env, resources_cls);
	(*env)->DeleteLocalRef (env, resources);
	(*env)->DeleteLocalRef (env, activity_cls);
	(*env)->DeleteLocalRef (env, activity);
	return sw >= 600;
}

void
ollmapp_android_lock_landscape (GtkWindow *window)
{
	GdkSurface *surface;
	jobject activity;
	JNIEnv *env;
	jclass activity_cls;
	jmethodID set_mid;

	surface = gtk_native_get_surface (GTK_NATIVE (window));
	if (surface == NULL || !GDK_IS_ANDROID_TOPLEVEL (surface)) {
		return;
	}
	activity = gdk_android_toplevel_get_activity (GDK_ANDROID_TOPLEVEL (surface));
	if (activity == NULL) {
		return;
	}
	env = ollmapp_android_jni_env ();
	if (env == NULL) {
		return;
	}
	activity_cls = (*env)->GetObjectClass (env, activity);
	set_mid = (*env)->GetMethodID (env, activity_cls,
		"setRequestedOrientation", "(I)V");
	/* ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE */
	(*env)->CallVoidMethod (env, activity, set_mid, 6);
	(*env)->DeleteLocalRef (env, activity_cls);
	(*env)->DeleteLocalRef (env, activity);
}
```

---

### 3. `ollmapp/android/OllmchatWindow.vala` — implement `ChatDesktopInterface`

**Why:** Factories cast the window to this interface. Drop the Phase 2 class `notification` signal; the interface already declares it.

**Where:** class declaration; fields after `startup_status_label`; remove the class-level `notification` signal (keep `window_config()`).

**Depends on:** none.

#### Remove — class declaration

```vala
	public class OllmchatWindow : Adw.ApplicationWindow, ChatUserInterface
```

#### Replace with

```vala
	public class OllmchatWindow : Adw.ApplicationWindow, ChatUserInterface, OLLMchat.ChatDesktopInterface
```

#### Add — after `public Gtk.Label startup_status_label;`

```vala
		private Adw.ViewStack pane_stack;
		private bool is_tablet = false;
```

#### Remove — class-level signal (`ChatDesktopInterface` provides it)

```vala
		public signal void notification(OLLMrpc.Notification notif);
```

---

### 4. `ollmapp/android/OllmchatWindow.vala` — `ChatDesktopInterface` methods

**Why:** Same names and return types as desktop `Window.vala`. `tab_view()` is `pane_stack` (not `WindowPane`). `schedule_pane_update` shows the globe page on phone and the right column on tablet.

**Where:** class body, after `window_config()`, before `public OllmchatWindow(AndroidApplication app)`.

**Depends on:** §3 (`pane_stack`, `is_tablet`).

#### Add — after `window_config()`, before the constructor

```vala
		public OLLMchat.Agent.Base? session_agent()
		{
			return this.history_manager.session.agent;
		}

		public GLib.Object above_input_widget()
		{
			return this.chat_widget.above_input;
		}

		public OLLMchat.MessageQueue chat_message_queue()
		{
			return this.chat_widget.queue_view.queue;
		}

		public GLib.Object tab_view()
		{
			return this.pane_stack;
		}

		public void schedule_pane_update(bool visible)
		{
			if (this.is_tablet) {
				this.pane_stack.visible = visible;
				return;
			}
			if (visible) {
				this.chat_widget.view_stack.visible_child_name = "pane";
				return;
			}
			this.chat_widget.view_stack.visible_child_name = "chat";
		}

		public void scroll_to_message(int idx)
		{
			if (idx < 0) {
				return;
			}
			this.chat_widget.chat_view.scroll_to_idx(idx);
		}
```

---

### 5. `ollmapp/android/OllmchatWindow.vala` — constructor: create `pane_stack`

**Why:** `tab_view()` must return a live `Adw.ViewStack` after construct. Device class is still unknown here (needs a realized activity).

**Where:** constructor, after `this.chat_container = new Gtk.Box (…);`.

**Depends on:** §3.

#### Add — after the `chat_container` initializer, before `this.startup_status_label =`

```vala
			this.pane_stack = new Adw.ViewStack() {
				hexpand = true,
				vexpand = true,
			};
```

---

### 6. `ollmapp/android/OllmchatWindow.vala` — `initialize_client()`: detect, lock, route tools

**Why:** JNI needs a realized window (`realize` already ran `load_config_and_initialize`). Browser and later editor share `pane_stack`.

**Where:** `initialize_client()`. Detect after `refresh()`. Tool lambda and `chat_container.append` after `setup_chat_widget`.

**Depends on:** §2, §4, §5.

#### Add — after `yield this.history_manager.connection_models.refresh();`, before `this.project_manager = new OLLMfiles.ProjectManager();`

```vala
			this.is_tablet = android_is_tablet(this);
			if (this.is_tablet) {
				android_lock_landscape(this);
			}
```

#### Remove — `tool_toggle` lambda

```vala
			this.chat_widget.chat_bar.tool_toggle.connect((tool_name, active) => {
				if (!active) {
					this.chat_widget.view_stack.visible_child_name = "chat";
					return;
				}
				if (!this.history_manager.tools.has_key(tool_name)) {
					return;
				}
				var ui = this.history_manager.tools.get(tool_name) as OLLMchat.Tool.UiWidgets;
				if (ui == null) {
					return;
				}
				var view = (Gtk.Widget) ui.view_widget;
				if (this.chat_widget.view_stack.get_child_by_name(tool_name) == null) {
					this.chat_widget.view_stack.add_named(view, tool_name);
				}
				this.chat_widget.view_stack.visible_child_name = tool_name;
			});
```

#### Replace with

```vala
			this.chat_widget.chat_bar.tool_toggle.connect((tool_name, active) => {
				if (!active) {
					this.schedule_pane_update(false);
					return;
				}
				if (!this.history_manager.tools.has_key(tool_name)) {
					return;
				}
				var ui = this.history_manager.tools.get(tool_name) as OLLMchat.Tool.UiWidgets;
				if (ui == null) {
					return;
				}
				var view = (Gtk.Widget) ui.view_widget;
				if (this.pane_stack.get_child_by_name(tool_name) == null) {
					this.pane_stack.add_named(view, tool_name);
				}
				this.pane_stack.set_visible_child_name(tool_name);
				this.schedule_pane_update(true);
			});
```

#### Remove — append chat widget only

```vala
			this.chat_container.append (this.chat_widget);
```

#### Replace with

```vala
			if (this.is_tablet) {
				var columns = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
					hexpand = true,
					vexpand = true,
				};
				this.chat_widget.hexpand = true;
				this.chat_widget.vexpand = true;
				columns.append(this.chat_widget);
				this.pane_stack.visible = false;
				columns.append(this.pane_stack);
				this.chat_container.append(columns);
			} else {
				this.chat_widget.view_stack.add_named(this.pane_stack, "pane");
				this.chat_container.append(this.chat_widget);
			}
```

---

### 7. `ollmapp/android/OllmchatWindow.vala` — Vala externs

**Why:** Same `[CCode]` pattern as the wake-lock / foreground calls.

**Where:** after `android_set_streaming_foreground`, before `int main`.

**Depends on:** §2.

#### Add — after the `android_set_streaming_foreground` extern

```vala
	[CCode (cname = "ollmapp_android_is_tablet", cheader_filename = "android-partial-wake-lock.h")]
	private extern bool android_is_tablet(Gtk.Window window);

	[CCode (cname = "ollmapp_android_lock_landscape", cheader_filename = "android-partial-wake-lock.h")]
	private extern void android_lock_landscape(Gtk.Window window);
```

---

### 8. `ollmapp/ChatUserInterface.vala` — doc (`💩`)

**Why:** The comment still says coder pane API is desktop-only.

**Where:** class docblock, the sentence about `ChatDesktopInterface`.

**Depends on:** §3.

#### Remove

```vala
		 * Coder pane API for liboccoder is {@link OLLMchat.ChatDesktopInterface}
		 * (desktop window only).
```

#### Replace with

```vala
		 * Coder pane API for liboccoder is {@link OLLMchat.ChatDesktopInterface}
		 * (desktop and Android windows).
```

---

## Verify before starting

- **ℹ️** `ChatDesktopInterface` already lives in `libollmchat` (linked on `android_poc`).
- **ℹ️** `initialize_client` runs from `realize` → JNI has an activity.
- **🔷** `⏳` Fix `android_poc` compile errors in this plan. No `#if ANDROID` stubs on the desktop row. No `WindowPane` / `Gtk.Paned` / `Adw.Breakpoint`.

---

## Suggested order

1. **✔️** [`8.2.8.6`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md) Phase 1–2
2. **✔️** This plan — JNI device class, `ChatDesktopInterface`, phone `"pane"` stack / tablet columns

---

## LLM notes

- **ℹ️** HTTPS takeover / `ProjectManager` stay in [`8.2.8.6`](done/RPC-8.2.8.6-DONE-filesd-android-remote-takeover.md).
- **🚫** Registering `AgentPi.Factory` / `AgentFactory` / Skill Runner on Android in this plan — [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md).
- **🚫** `WindowPane` / `Gtk.Paned` on Android (resizable sash, grow-the-window).
- **🚫** Width breakpoint that swaps phone ↔ tablet as the window rotates or resizes.
- **🚫** Portrait phone shell on a tablet.
- **🚫** A second Android-only `activate` that avoids `ChatDesktopInterface`.
- **🚫** Gdk width cutoff instead of `smallestScreenWidthDp`.
- **🚫** A second Android C file with its own `JNI_OnLoad`.
- **🚫** `#ifdef __ANDROID__` / desktop no-op stubs in `android-partial-wake-lock.c` — meson only compiles that file on `android_poc`.
- **🚫** New Vala helpers around detect / layout / tool routing — inline in `initialize_client` and `schedule_pane_update`.
- **🚫** Plan numbers / slugs in Valadoc (keep API comments about the types, not the ticket).
- **🚫** Per-hop JNI `NULL` / `ExceptionCheck` on framework `Activity` APIs (`getResources`, `getConfiguration`, `smallestScreenWidthDp`, `setRequestedOrientation`). Wake-lock does that for a **missing app class**; `load_class` does not.
