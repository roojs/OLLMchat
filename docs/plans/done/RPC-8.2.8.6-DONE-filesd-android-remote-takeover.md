# 8.2.8.6 — DONE — Remote file connection: Android takeover

**Status:** **DONE** ✔️ — Phase 1–2 in tree. Phase 3 is [`RPC-8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md).

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](../RPC-8.2.8-filesd-connections-ui.md)

**Split from:** [`RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md`](RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) Phase E.

**Depends on:**

- [`RPC-8.2.8.5`](RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) — desktop Check / `reconnect` / Linux takeover (Phases C–D)
- [`RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md`](RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md) — `OLLMrpc.Client.http`, `ProjectManager.replace_rpc` + `notification`
- [`RPC-8.2.8.2-DONE-filesd-android-file-connection.md`](RPC-8.2.8.2-DONE-filesd-android-file-connection.md) Phase 1 — Android Connections UI + `FileConnectionAdd.request()`
- [`FILES-2.10.4.33-client-tree-sitter-daemon.md`](../FILES-2.10.4.33-client-tree-sitter-daemon.md) — **✔️** client `Tree` dropped; `libocfiles` has no tree-sitter dep

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Landed (tree)

- `meson.build` / `libocfiles/meson.build` / `liboccoder/meson.build` / `ollmapp/meson.build` — Android `libocfiles` + full `liboccoder`; stub `AndroidToolTypes.vala` deleted
- `ollmapp/android/OllmchatWindow.vala` — `project_manager`, `uuid`, `notification`, `window_config()`; HTTPS `replace_rpc` + `RPC-Daemon.hello` (no `ClientBoot`)

---

## Purpose

- **🔷** Replace the `OLLMfiles.ProjectManager` stub so an approved + enabled file connection talks to remote `ollmfilesd` over HTTPS.
- **🔷** Android startup: when `url != "" && enabled && approved`, HTTPS `replace_rpc` as [`8.2.8.5`](RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) §1, then `yield rpc.connect(hello)` with **no** `ClientBoot`.
- **🔷** Compile **full** `liboccoder` on Android (same sources as desktop). Implication is meson + deps, not a second agent API.
- **🔷** Tree-sitter stays off Android on purpose. AST parse is the file daemon's job — [`FILES-2.10.4.33`](../FILES-2.10.4.33-client-tree-sitter-daemon.md).
- **🔷** Do **not** register occoder agent factories on Android in this plan (Agent Pi / Code Assistant / Skill Runner). Android Agent Pi register is [`8.2.8`](../RPC-8.2.8-filesd-connections-ui.md) Phase 10.
- **ℹ️** Phone/tablet `ChatDesktopInterface` shell is [`RPC-8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md).
- **ℹ️** Operator nginx doc: [`docs/filesd-behind-nginx-proxy.md`](../../filesd-behind-nginx-proxy.md).

---

## Current behaviour

- **ℹ️** `android_poc` links reduced `occoder` (`AgentPi/Skill.vala` + `SkillSet.vala` only) via `liboccoder/meson.build` `is_android_cross` + `subdir_done()`.
- **ℹ️** `OLLMfiles.ProjectManager` is a stub in `ollmapp/android/AndroidToolTypes.vala`. `libocfiles` is not in the Android `subdir()` list.
- **ℹ️** Pixiewood has no tree-sitter wrap (deliberate). Client `Tree` / `TreeBase` are gone ([`FILES-2.10.4.33`](../FILES-2.10.4.33-client-tree-sitter-daemon.md)).
- **ℹ️** Phone/tablet shell was this plan's Phase 3 — now [`8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md).
- **ℹ️** [`8.2.8.5`](RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) `FileConnectionRow` / `ConnectionsPage.render_approved` already call `win.project_manager`, `win.notification`, `win.window_config()`.

---

## Design decisions

- **🔷** Same HTTPS client construction as desktop: `Transport.Cert.ensure()` then `tls.certificate` / `tls.trust` on `HttpClient`.
- **🔷** Full liboccoder compiles on Android. Registration of those factories stays off.
- **🔷** Tree-sitter is daemon-side ([`FILES-2.10.4.33`](../FILES-2.10.4.33-client-tree-sitter-daemon.md)). Do not add a Pixiewood wrap or ship language `.so` files in the APK.
- **ℹ️** `register_default_agents()` is Chatter only (`ChatUserInterface`). Coder factories are a separate desktop `Window.initialize_client` block. Leave that block off Android.
- **ℹ️** `ChatDesktopInterface` / phone vs tablet layout is [`8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md).

---

## Phase 1 — Real `ProjectManager` + full `liboccoder` (`✔️` tree, Android compile `⏳`)

- **🔷** `✔️` `libocfiles` in the Android `subdir()` list. `ocfiles_vapi_dep` + `--pkg=ocfiles` on `android_poc`.
- **🔷** `✔️` Drop the `is_android_cross` Skill-only `subdir_done()` in `liboccoder/meson.build`. Build the same `occoder_src` as desktop (GtkSourceView, `SourceView`, factories). No tree-sitter on this cross-build.
- **🔷** `✔️` Drop / replace the stub in `ollmapp/android/AndroidToolTypes.vala`.
- **ℹ️** Cross-build already has `sqlite3`, `gmodule-2.0`, `gtksourceview-5`. Tree-sitter is [`FILES-2.10.4.33`](../FILES-2.10.4.33-client-tree-sitter-daemon.md), not a wrap here.
- **ℹ️** `FileConnectionRow` / `ConnectionsPage.render_approved` still need `win.project_manager`, `win.notification`, `win.window_config()` — those are Phase 2. Do not `#if ANDROID` the row.
- **💩** `✔️` Skip `vala_gir` on the Android `occoder` `library()` (same as `libollmchat` / `libollmchatgtk`).
- **💩** `✔️` `gee_vapi_dir` on Android `ocfiles` / `occoder` VAPI `custom_target`s (same as `libocrpc`).
- **💩** `✔️` `--define=ANDROID` on the `occoder` VAPI `custom_target` (`ReviewBar` is `#if !ANDROID`; that valac does not inherit project args).
- **💩** `✔️` `--pkg=ocrpc` + its vapidir on `android_poc` (desktop `ollmchat` already does; `ocfiles.vapi` names `OLLMrpc`).
- **⏳** Android `android_poc` compile not reached: Pixiewood meson reconfigure failed on wrap-pin skew (stale `subprojects/glib` 2.84 vs wrap 2.90, then pango `harfbuzz` 8.4 vs `>= 11`). Desktop `ninja -C build` succeeded.

Edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

### 1. `meson.build` — `libocfiles` on the `android_poc` `subdir()` list

**Why:** `liboccoder` and `android_poc` need `ocfiles_vapi_dep`. Client tree-sitter is gone, so this cross-build does not need a Pixiewood wrap.

**Where:** `elif android_poc_opt and host_machine.system() == 'android'` library order, after `subdir('libocrpc')`. Also the `liboccoder` comment on that branch.

**Depends on:** none.

#### Remove

```python
  subdir('libocsqlite')
  subdir('libocrpc')
  subdir('libollamaweb')
```

#### Replace with

```python
  subdir('libocsqlite')
  subdir('libocrpc')
  subdir('libocfiles')       # Depends on libocsqlite + libocrpc; no tree-sitter
  subdir('libollamaweb')
```

#### Remove — `liboccoder` comment on the same branch

```python
  subdir('liboccoder')       # AgentPi catalog only on Android (see liboccoder/meson.build)
```

#### Replace with

```python
  subdir('liboccoder')       # Same sources as desktop (see liboccoder/meson.build)
```

---

### 2. `libocfiles/meson.build` — Android `gee_vapi_dir` on the VAPI custom_target

**Why:** `ocrpc` / `ocsqlite` already pass `gee_vapi_dir` on Android `custom_target` valac. `libocfiles` did not, because it was not in the Android `subdir()` list.

**Where:** next to `is_windows`; then `ocfiles_vapi_cmd` after the `if not is_windows` vapidir.

**Depends on:** §1.

#### Add — after `is_windows = host_machine.system() == 'windows'`

```python
is_android = host_machine.system() == 'android'
```

#### Add — after `ocfiles_vapi_cmd`'s `if not is_windows` vapidir block, before `ocfiles_vapi = custom_target(`

```python
if is_android
  ocfiles_vapi_cmd += ['--vapidir', gee_vapi_dir]
endif
```

---

### 3. `liboccoder/meson.build` — full `occoder_src` on Android

**Why:** SkillsPage already needs `AgentPi.Skill`; [`8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md) needs `SourceView` / factories compiled. Keep `is_android_cross` for GIR skip and VAPI `--define`.

**Where:** top of file through `subdir_done()`; then `occoder_base_lib = library(`; then after `occoder_vapi_vapidirs`.

**Depends on:** §1, §2.

##### Part 1 — drop Skill-only `subdir_done()`

#### Remove

```python
if is_android_cross
  # Full occoder needs libocfiles / GtkSourceView / tree-sitter. Android
  # SkillsPage only needs AgentPi.Skill + SkillSet. Same soname / --pkg=occoder.
  occoder_src = files([
    'AgentPi/Skill.vala',
    'AgentPi/SkillSet.vala',
  ])
  occoder_deps = [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    valac.find_library('posix'),
  ]
  occoder_base_lib = library(occoder_lib,
    dependencies: occoder_deps,
    sources: occoder_src,
    vala_header: 'occoder.h',
    vala_vapi: 'occoder-meson.vapi',
    install: true,
  )
  occoder_vapi_cmd = [
    valac_exe,
    '-C', '--debug',
    '--target-glib=auto',
    '--vapidir', meson.current_build_dir(),
    '--vapidir', gee_vapi_dir,
    '--pkg', 'posix',
    '--pkg', 'gobject-2.0',
    '--pkg', 'glib-2.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gee-0.8',
    '--library', occoder_lib,
    '--header', meson.current_build_dir() / 'occoder.h',
    '--vapi', '@OUTPUT@',
    '@INPUT@',
  ]
  occoder_vapi = custom_target('occoder-vapi',
    output: 'occoder.vapi',
    input: occoder_src,
    command: occoder_vapi_cmd,
    depends: [occoder_base_lib],
    build_by_default: true,
    install: true,
    install_dir: get_option('datadir') / 'vala' / 'vapi',
  )
  occoder_vapi_dep = declare_dependency(
    link_args: ['-L' + meson.current_build_dir(), '-l' + occoder_lib],
    sources: [occoder_vapi[0]],
  )
  subdir_done()
endif
```

Keep `valac = meson.get_compiler('vala')` and `is_android_cross = host_machine.system() == 'android'` above this block. The desktop `occoder_src` / `occoder_deps` that follow become the Android compile too.

##### Part 2 — omit `vala_gir` on Android (`library()`)

**Why:** `libollmchat` / `libollmchatgtk` already skip `vala_gir` on Android. `g_ir_compiler` is a `disabler()` there; Meson still rejects or fails `vala_gir` on the `library()` itself.

#### Remove

```python
occoder_base_lib = library(occoder_lib,
  dependencies: occoder_lib_deps,
  sources: occoder_src,
  vala_header: 'occoder.h',
  vala_vapi: 'occoder-meson.vapi',  # Use different name so our custom_target can use 'occoder.vapi'
  vala_gir: 'OLLMcoder-1.0.gir',
  build_rpath: lib_build_rpath,
  include_directories: [
    include_directories('..' / 'libollmchat'),
    include_directories('..' / 'libollamaweb'),
    include_directories('..' / 'libocfiles')     # For C headers (build directory)
  ],
  vala_args: occoder_vala_args,
  install: true
)
```

#### Replace with

```python
if is_android_cross
  occoder_base_lib = library(occoder_lib,
    dependencies: occoder_lib_deps,
    sources: occoder_src,
    vala_header: 'occoder.h',
    vala_vapi: 'occoder-meson.vapi',  # Use different name so our custom_target can use 'occoder.vapi'
    build_rpath: lib_build_rpath,
    include_directories: [
      include_directories('..' / 'libollmchat'),
      include_directories('..' / 'libollamaweb'),
      include_directories('..' / 'libocfiles')     # For C headers (build directory)
    ],
    vala_args: occoder_vala_args,
    install: true
  )
else
  occoder_base_lib = library(occoder_lib,
    dependencies: occoder_lib_deps,
    sources: occoder_src,
    vala_header: 'occoder.h',
    vala_vapi: 'occoder-meson.vapi',  # Use different name so our custom_target can use 'occoder.vapi'
    vala_gir: 'OLLMcoder-1.0.gir',
    build_rpath: lib_build_rpath,
    include_directories: [
      include_directories('..' / 'libollmchat'),
      include_directories('..' / 'libollamaweb'),
      include_directories('..' / 'libocfiles')     # For C headers (build directory)
    ],
    vala_args: occoder_vala_args,
    install: true
  )
endif
```

##### Part 3 — Android VAPI `custom_target`: `gee_vapi_dir` + `--define=ANDROID`

**Why:** that `custom_target` does not inherit `add_project_arguments`. `ReviewBar` is `#if !ANDROID`. `gee_vapi_dir` matches the old Skill-only Android vapi command and `libocrpc`.

#### Add — after the `occoder_vapi_vapidirs = [ ... ]` list, before `occoder_vapi_depends =`

```python
if is_android_cross
  occoder_vapi_vapidirs += ['--vapidir', gee_vapi_dir]
  occoder_vapi_gen_pkgs += ['--define', 'ANDROID']
endif
```

---

### 4. `ollmapp/meson.build` — `ocfiles` on `android_poc` + drop stub source

**Why:** link the real `OLLMfiles.ProjectManager`. `ocfiles.vapi` references `OLLMrpc`, so `--pkg=ocrpc` / its vapidir go on the same target (desktop `ollmchat` already does).

**Where:** `android_poc` `dependencies`, `include_directories`, `vala_args`, and `android_poc_sources`.

**Depends on:** §1–§3.

#### Remove — `android_poc_sources`

```python
    'android/AndroidBootstrapConnectionAdd.vala',
    'android/AndroidToolTypes.vala',
    'android/AndroidToolsRegistration.vala',
```

#### Replace with

```python
    'android/AndroidBootstrapConnectionAdd.vala',
    'android/AndroidToolsRegistration.vala',
```

#### Add — `android_poc` `dependencies:` list, after `occoder_vapi_dep,`

```python
      ocfiles_vapi_dep,
```

#### Add — `android_poc` `include_directories:`, after `include_directories('../liboccoder'),`

```python
      include_directories('../libocfiles'),
```

#### Add — `android_poc` `vala_args:`, after `'--pkg=occoder',`

```python
      '--pkg=ocfiles',
      '--pkg=ocrpc',
```

#### Add — `android_poc` `vala_args:` vapidirs, after `'--vapidir', meson.current_build_dir() / '..' / 'liboccoder',`

```python
      '--vapidir', meson.current_build_dir() / '..' / 'libocfiles',
      '--vapidir', meson.current_build_dir() / '..' / 'libocrpc',
```

---

### 5. Delete `ollmapp/android/AndroidToolTypes.vala`

**Why:** the file is only the empty `OLLMfiles.ProjectManager` stub. The real class is `libocfiles/ProjectManager.vala`.

**Where:** delete the file. Meson source drop is §4.

**Depends on:** §4.

#### Remove

```vala
namespace OLLMfiles
{
	/**
	 * Android POC stub for {@link OLLMtools.WebFetch.Tool} constructor typing.
	 *
	 * Full project workspace support is desktop-only; mobile passes null.
	 *
	 * @since 1.0
	 */
	public class ProjectManager : GLib.Object
	{
	}
}
```

Delete the leftover license header with the file.

---

## Phase 2 — HTTPS takeover at Android startup (`✔️`)

- **🔷** `✔️` `OllmchatWindow.initialize_client` (Android): when `filesd_client.url != "" && enabled && approved`, mint the device `Cert`, `HttpClient`, `OLLMrpc.Client` with `http` set, `replace_rpc`, `yield rpc.connect(hello)` (no `ClientBoot`).
- **🔷** `✔️` Copy the Cert / HttpClient literals from `FileConnectionAdd.request()` (no fourth helper).
- **🔷** `✔️` Expose `project_manager`, `notification`, `window_config()` on the Android window so `FileConnectionRow.reconnect` compiles (same names as desktop).
- **ℹ️** `notification` on desktop is the `ChatDesktopInterface` signal. Phase 2 adds that signal on the Android window without implementing the interface ([`8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md)).
- **ℹ️** `FileConnectionRow.reconnect(false)` still uses `ClientBoot` (local Unix). Do not `#if ANDROID` the row. Startup never passes `ClientBoot`.
- **💩** `✔️` On HTTPS `connect` failure, `GLib.warning` + `Alert.show` and **continue** chat (desktop `return`s out of `initialize_client` because the local daemon is required there).
- **💩** `✔️` Constructor `notification` handler: `Alert.show` → `Adw.AlertDialog` only (desktop also has `ActivityBanner` / `Banner.show` / file-change). `FileConnectionRow` emits `Alert.show`.
- **💩** `✔️` GtkSource `BufferProvider` on the Android `ProjectManager` (desktop always sets it; editor host is [`8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md)).
- **💩** `✔️` Forward `ProjectManager.notification` → window `notification` via `GLib.Idle.add` (desktop does this after connect).

Edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

Named members this phase adds: `project_manager`, `uuid`, `notification` (signal), `window_config()`.

### 1. `ollmapp/android/OllmchatWindow.vala` — `project_manager`, `uuid`, `notification`

**Why:** `FileConnectionRow` / `ConnectionsPage.render_approved` already call these names on `OllmchatWindow`. Same types as desktop `Window.vala`.

**Where:** class body, after `public Gtk.Label startup_status_label;`, before the constructor.

**Depends on:** Phase 1 (real `OLLMfiles.ProjectManager`).

#### Add — after `public Gtk.Label startup_status_label;`

```vala
		public OLLMfiles.ProjectManager? project_manager { get; private set; default = null; }
		/**
		 * UUID key into {@link OLLMchat.Settings.Config2.windows}.
		 */
		public string uuid { get; private set; default = ""; }
		public signal void notification(OLLMrpc.Notification notif);
```

---

### 2. `ollmapp/android/OllmchatWindow.vala` — `window_config()`

**Why:** `FileConnectionRow.reconnect` calls `this.win.window_config()` then `restore_active_state`. Same body as desktop `Window.vala` `window_config()`. Plan-named method.

**Where:** class body, after the §1 fields, before `public OllmchatWindow(AndroidApplication app)`.

**Depends on:** §1 (`uuid`).

#### Add — after the `notification` signal, before the constructor

```vala
		public OLLMchat.Settings.Window window_config()
		{
			if (this.uuid != "") {
				return this.app.config.windows.get(this.uuid);
			}
			if (this.app.config.windows.size == 0) {
				this.uuid = GLib.Uuid.string_random();
				this.app.config.windows.set(
					this.uuid,
					new OLLMchat.Settings.Window()
				);
				this.app.config.save();
				return this.app.config.windows.get(this.uuid);
			}
			foreach (var entry in this.app.config.windows.entries) {
				this.uuid = entry.key;
				return entry.value;
			}
			GLib.error("windows map non-empty but no entries");
		}
```

---

### 3. `ollmapp/android/OllmchatWindow.vala` — constructor: `Alert.show`

**Why:** `FileConnectionRow.reconnect` emits `this.win.notification(… method = "Alert.show")`. Without a handler the signal compiles and the user sees nothing.

**Where:** constructor, after `this.settings_dialog.closed.connect(…);`, before `var toolbar_view = new Adw.ToolbarView();`.

**Depends on:** §1.

#### Add — after the `settings_dialog.closed.connect` lambda, before `var toolbar_view`

```vala
			this.notification.connect((notif) => {
				if (notif.method != "Alert.show") {
					return;
				}
				var alert = new Adw.AlertDialog("Alert", notif.message);
				alert.add_response("ok", "OK");
				alert.choose.begin(this, null);
			});
```

---

### 4. `ollmapp/android/OllmchatWindow.vala` — `initialize_client()`: `ProjectManager` + HTTPS hello

**Why:** Approved + enabled file connection talks to remote `ollmfilesd` at startup. `ProjectManager()` still builds a Unix client; `replace_rpc` swaps it before `connect`. HTTPS `connect(hello)` must not pass `ClientBoot`.

**Where:** `initialize_client()`, after `yield this.history_manager.connection_models.refresh();`, before `this.register_default_agents();`.

**Depends on:** §1, §3. Cert / `HttpClient` literals from `FileConnectionAdd.request()`.

**Keep**

```vala
			this.startup_status_label.label = "Loading models…";
			yield this.history_manager.connection_models.refresh();
```

**Add** — After `refresh()`. Create `ProjectManager`. When url + enabled + approved: Cert / `HttpClient` / `replace_rpc` / `connect(hello)` with no `ClientBoot`. Failed hello does not skip chat. Always forward manager notifications.

```vala
			this.project_manager = new OLLMfiles.ProjectManager();
			this.project_manager.buffer_provider = new OLLMcoder.BufferProvider();
			if (config.filesd_client.url != "" && config.filesd_client.enabled
				&& config.filesd_client.approved) {
				var tls = new OLLMrpc.Transport.Cert() {
					dir = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "ollmchat"),
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "ollmchat-device",
					product_ca_resource = true,
				};
				tls.ensure();
				var http = new OLLMrpc.Transport.HttpClient(config.filesd_client.url) {
					bin_body = true,
					tls_certificate = tls.certificate,
					tls_database = tls.trust
				};
				this.project_manager.replace_rpc(
					new OLLMrpc.Client("", "", config.filesd_client.url) { http = http }
				);
				var hello = new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("is", 1, "ollmchat")
				};
				if (!yield this.project_manager.rpc.connect(hello)) {
					var msg = this.project_manager.rpc.connect_error;
					if (msg == "") {
						msg = "could not reach the file server";
					}
					GLib.warning("%s", msg);
					this.notification(new OLLMrpc.Notification() {
						method = "Alert.show",
						message = "File server: " + msg
					});
				}
			}
			this.project_manager.notification.connect((notif) => {
				GLib.Idle.add(() => {
					this.notification(notif);
					return false;
				});
			});
```

**Keep**

```vala
			this.register_default_agents();
```

---

## Phase 3 — `ChatDesktopInterface` + phone / tablet pane

**➡️** [`RPC-8.2.8.8-DONE-android-phone-tablet-pane.md`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md)

---

## Verify before starting

- **ℹ️** `ConnectionsPage.render_approved` already references `win.project_manager.rpc`.
- **ℹ️** `FileConnectionRow.reconnect` already references `win.project_manager`, `win.notification`, `win.window_config()`.
- **🔷** `✔️` [`FILES-2.10.4.33`](../FILES-2.10.4.33-client-tree-sitter-daemon.md) landed before any Android `subdir('libocfiles')`.
- **🔷** `⏳` Fix `android_poc` compile errors in this plan. No `#if ANDROID` stubs on the desktop row.

---

## Suggested order

1. **✔️** [`FILES-2.10.4.33`](../FILES-2.10.4.33-client-tree-sitter-daemon.md) — client `Tree` off `libocfiles`
2. **✔️** Phase 1 — `libocfiles` (no tree-sitter) + full `liboccoder` + real `ProjectManager` (Android meson reconfigure still `⏳`)
3. **✔️** Phase 2 — HTTPS `replace_rpc` + window APIs `FileConnectionRow` already calls
4. **✔️** Phase 3 — [`8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md) — `ChatDesktopInterface` + phone stack / tablet landscape columns

---

## LLM notes

- **ℹ️** Desktop Check / live toggle / Linux takeover stay in [`8.2.8.5`](RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md).
- **ℹ️** Phone/tablet shell is [`8.2.8.8`](RPC-8.2.8.8-DONE-android-phone-tablet-pane.md).
- **🚫** `ClientBoot` on Android (no local Unix `ollmfilesd`).
- **🚫** Gating Linux Agent Pi on the remote connection.
- **🚫** Registering occoder agents on Android in this plan — [`8.2.8`](../RPC-8.2.8-filesd-connections-ui.md) Phase 10.
- **🚫** Multiple file-server URLs.
- **🚫** `ensure_trust()` / `try/catch` around `Cert.ensure()`.
- **🚫** A Pixiewood tree-sitter wrap, or language parser `.so` files in the APK, to make `libocfiles` compile.
- **🚫** `#if ANDROID` stub `OLLMfiles.Tree` so Phase 1 can ignore the leftover.
