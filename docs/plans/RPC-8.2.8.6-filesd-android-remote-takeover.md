# 8.2.8.6 — Remote file connection: Android takeover + tablet shell

**Status:** **PROPOSED** — Phase 1 code proposals; Phase 2–3 still design-only

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md)

**Split from:** [`RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) Phase E.

**Depends on:**

- [`RPC-8.2.8.5`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) — desktop Check / `reconnect` / Linux takeover (Phases C–D)
- [`RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md`](done/RPC-8.2.8.4-DONE-filesd-remote-rpc-client.md) — `OLLMrpc.Client.http`, `ProjectManager.replace_rpc` + `notification`
- [`RPC-8.2.8.2-DONE-filesd-android-file-connection.md`](done/RPC-8.2.8.2-DONE-filesd-android-file-connection.md) Phase 1 — Android Connections UI + `FileConnectionAdd.request()`
- [`FILES-2.10.4.33-client-tree-sitter-daemon.md`](FILES-2.10.4.33-client-tree-sitter-daemon.md) — **✔️** client `Tree` dropped; `libocfiles` has no tree-sitter dep

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Replace the `OLLMfiles.ProjectManager` stub so an approved + enabled file connection talks to remote `ollmfilesd` over HTTPS.
- **🔷** Android startup: when `url != "" && enabled && approved`, HTTPS `replace_rpc` as [`8.2.8.5`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) §1, then `yield rpc.connect(hello)` with **no** `ClientBoot`.
- **🔷** Compile **full** `liboccoder` on Android (same sources as desktop). Implication is meson + deps, not a second agent API.
- **🔷** Tree-sitter stays off Android on purpose. AST parse is the file daemon's job — [`FILES-2.10.4.33`](FILES-2.10.4.33-client-tree-sitter-daemon.md).
- **🔷** Do **not** register occoder agent factories on Android in this plan (Agent Pi / Code Assistant / Skill Runner). Later.
- **🔷** Android `OllmchatWindow` implements `OLLMchat.ChatDesktopInterface`.
  - Phone: browser and code editor use today's globe pattern (`chat_widget.view_stack` swap).
  - Tablet: double pane — chatter | browser-or-editor (one right slot). Device class, not a width breakpoint. Landscape only. No portrait phone shell on tablet. Split is **not** a resizable paned.
- **ℹ️** Operator nginx doc: [`docs/filesd-behind-nginx-proxy.md`](../filesd-behind-nginx-proxy.md).

---

## Current behaviour

- **ℹ️** `android_poc` links reduced `occoder` (`AgentPi/Skill.vala` + `SkillSet.vala` only) via `liboccoder/meson.build` `is_android_cross` + `subdir_done()`.
- **ℹ️** `OLLMfiles.ProjectManager` is a stub in `ollmapp/android/AndroidToolTypes.vala`. `libocfiles` is not in the Android `subdir()` list.
- **ℹ️** Pixiewood has no tree-sitter wrap (deliberate). Client `Tree` / `TreeBase` are gone ([`FILES-2.10.4.33`](FILES-2.10.4.33-client-tree-sitter-daemon.md)).
- **ℹ️** Phone shell: `Gtk.Stack` (`startup` / `chat` / `history`). Browser globe toggles `chat_widget.view_stack` (`"chat"` vs tool name). No right pane.
- **ℹ️** Desktop split is `ollmapp/WindowPane.vala` (`Gtk.Paned` + `Adw.ViewStack tab_view`). Showing the pane **grows** the window. Not in `android_poc` sources.
- **ℹ️** `AgentPi.Factory.activate` casts the window to `ChatDesktopInterface` and `tab_view()` to `Adw.ViewStack`, then mounts `OLLMcoder.SourceView`. Android window is `ChatUserInterface` only.
- **ℹ️** [`8.2.8.5`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md) `FileConnectionRow` / `ConnectionsPage.render_approved` already call `win.project_manager`, `win.notification`, `win.window_config()`.

---

## Design decisions

- **🔷** Same HTTPS client construction as desktop: `Transport.Cert.ensure()` then `tls.certificate` / `tls.trust` on `HttpClient`.
- **🔷** Full liboccoder compiles on Android. Registration of those factories stays off.
- **🔷** `ChatDesktopInterface` is the host surface. No separate Android `activate` path.
- **🔷** Browser and editor share one secondary surface. Phone: full-stack swap. Tablet: chat stays visible, secondary is the other column.
- **🔷** Tablet vs phone is a **device class**, not a live wide/narrow cutoff. A tablet does not flip to the phone shell when rotated.
- **🔷** Tablet UI is landscape only. Do not show a vertical (portrait) phone layout on tablet.
- **🔷** Tablet split is a **fixed** two-column layout. Not a user-draggable sash (`Gtk.Paned` / desktop `WindowPane`).
- **🔷** Detect tablet the standard Android way (`smallestScreenWidthDp` / `sw600dp`). If that signal is not reachable from Vala/GTK, expose it (JNI / activity). Do not invent a Gdk width cutoff.
- **🔷** Lock tablet orientation in the Android manifest / activity (`landscape` / `sensorLandscape`) so the phone stack never appears there.
- **🔷** Tablet `tab_view()` is still an `Adw.ViewStack` so factory casts match desktop. Columns are a `Gtk.Box`, not `WindowPane`. No extra tablet tab API.
- **🔷** Tree-sitter is daemon-side ([`FILES-2.10.4.33`](FILES-2.10.4.33-client-tree-sitter-daemon.md)). Do not add a Pixiewood wrap or ship language `.so` files in the APK.
- **ℹ️** `register_default_agents()` is Chatter only (`ChatUserInterface`). Coder factories are a separate desktop `Window.initialize_client` block. Leave that block off Android.

---

## Phase 1 — Real `ProjectManager` + full `liboccoder` (`⏳`)

- **🔷** `⏳` `libocfiles` in the Android `subdir()` list. `ocfiles_vapi_dep` + `--pkg=ocfiles` on `android_poc`.
- **🔷** `⏳` Drop the `is_android_cross` Skill-only `subdir_done()` in `liboccoder/meson.build`. Build the same `occoder_src` as desktop (GtkSourceView, `SourceView`, factories). No tree-sitter on this cross-build.
- **🔷** `⏳` Drop / replace the stub in `ollmapp/android/AndroidToolTypes.vala`.
- **ℹ️** Cross-build already has `sqlite3`, `gmodule-2.0`, `gtksourceview-5`. Tree-sitter is [`FILES-2.10.4.33`](FILES-2.10.4.33-client-tree-sitter-daemon.md), not a wrap here.
- **ℹ️** `FileConnectionRow` / `ConnectionsPage.render_approved` still need `win.project_manager`, `win.notification`, `win.window_config()` — those are Phase 2. Do not `#if ANDROID` the row.
- **💩** Skip `vala_gir` on the Android `occoder` `library()` (same as `libollmchat` / `libollmchatgtk`).
- **💩** `gee_vapi_dir` on Android `ocfiles` / `occoder` VAPI `custom_target`s (same as `libocrpc`).
- **💩** `--define=ANDROID` on the `occoder` VAPI `custom_target` (`ReviewBar` is `#if !ANDROID`; that valac does not inherit project args).
- **💩** `--pkg=ocrpc` + its vapidir on `android_poc` (desktop `ollmchat` already does; `ocfiles.vapi` names `OLLMrpc`).

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

**Why:** SkillsPage already needs `AgentPi.Skill`; Phase 3 needs `SourceView` / factories compiled. Keep `is_android_cross` for GIR skip and VAPI `--define`.

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

## Phase 2 — HTTPS takeover at Android startup (`⏳`)

- **🔷** `⏳` `OllmchatWindow.initialize_client` (Android): when `filesd_client.url != "" && enabled && approved`, mint the device `Cert`, `HttpClient`, `OLLMrpc.Client` with `http` set, `replace_rpc`, `yield rpc.connect(hello)` (no `ClientBoot`).
- **🔷** `⏳` Copy the Cert / HttpClient literals from `FileConnectionAdd.request()` (no fourth helper).
- **🔷** `⏳` Expose `project_manager`, `notification`, `window_config()` on the Android window so `FileConnectionRow.reconnect` compiles (same names as desktop).
- **⏳** Code proposals — after Phase 1 compiles.

---

## Phase 3 — `ChatDesktopInterface` + phone / tablet pane (`⏳`)

- **🔷** `⏳` `OllmchatWindow` implements `OLLMchat.ChatDesktopInterface`.
- **🔷** `⏳` Detect tablet once (device class). Phone keeps today's globe stack. Tablet always uses the landscape two-column shell.
- **🔷** `⏳` Tablet: chatter | browser-or-editor. One right slot (`tab_view`). Fixed columns, not `Gtk.Paned`.
- **🔷** `⏳` Tablet: lock landscape. No portrait / phone-stack fallback on that device.
- **🔷** `⏳` Route the existing Android browser `tool_toggle` into that same secondary surface (stack on phone, right column on tablet).
- **🚫** Register `AgentPi.Factory` / `AgentFactory` / Skill Runner on Android in this plan.
- **🚫** `WindowPane` on Android (resizable sash + grow-the-window).
- **🚫** `Adw.Breakpoint` / window-width switching between phone and tablet layouts.
- **⏳** Code proposals — after Phase 2 can connect.

---

## Verify before starting

- **ℹ️** `ConnectionsPage.render_approved` already references `win.project_manager.rpc`.
- **ℹ️** `FileConnectionRow.reconnect` already references `win.project_manager`, `win.notification`, `win.window_config()`.
- **🔷** `✔️` [`FILES-2.10.4.33`](FILES-2.10.4.33-client-tree-sitter-daemon.md) landed before any Android `subdir('libocfiles')`.
- **🔷** `⏳` Fix `android_poc` compile errors in this plan. No `#if ANDROID` stubs on the desktop row.

---

## Follow-ups (`⏳`, not in this plan)

- **🔷** `⏳` Register `OLLMcoder.AgentPi.Factory` when the remote file connection is live (Android gate). Linux stays as today.

---

## Suggested order

1. **✔️** [`FILES-2.10.4.33`](FILES-2.10.4.33-client-tree-sitter-daemon.md) — client `Tree` off `libocfiles`
2. **⏳** Phase 1 — `libocfiles` (no tree-sitter) + full `liboccoder` + real `ProjectManager`
3. **⏳** Phase 2 — HTTPS `replace_rpc` + window APIs `FileConnectionRow` already calls
4. **⏳** Phase 3 — `ChatDesktopInterface` + phone stack / tablet landscape columns (browser now, editor host ready)

---

## LLM notes

- **ℹ️** Desktop Check / live toggle / Linux takeover stay in [`8.2.8.5`](done/RPC-8.2.8.5-DONE-filesd-remote-takeover-connections-tab.md).
- **🚫** `ClientBoot` on Android (no local Unix `ollmfilesd`).
- **🚫** Gating Linux Agent Pi on the remote connection.
- **🚫** Registering occoder agents on Android in this plan.
- **🚫** A second Android-only `activate` that avoids `ChatDesktopInterface`.
- **🚫** `WindowPane` / `Gtk.Paned` on Android (resizable sash, grow-the-window).
- **🚫** Width breakpoint that swaps phone ↔ tablet as the window rotates or resizes.
- **🚫** Portrait phone shell on a tablet.
- **🚫** Multiple file-server URLs.
- **🚫** `ensure_trust()` / `try/catch` around `Cert.ensure()`.
- **🚫** A Pixiewood tree-sitter wrap, or language parser `.so` files in the APK, to make `libocfiles` compile.
- **🚫** `#if ANDROID` stub `OLLMfiles.Tree` so Phase 1 can ignore the leftover.
