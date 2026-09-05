# Changelog

All notable changes to OLLMchat are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for git tags (`v1.3.0`, etc.).

Debian and RPM packaging notes are generated from this file at release time
(see [Creating releases](docs/creating-releases.md)).

## [Unreleased]

### RPC

- GI / FFI: boxed structs, `float` / `double`, numeric arrays, enums / flags,
  INOUT, GList IN, explicit GType aliases
- Live GI callbacks (register / invoke / reply) and `SCM_RIGHTS` on
  `Response`
- Live leases: stamp lease id on proxy decode; write path uses the lease key;
  `Live.Handle` interface
- Namespace (top-level) GI functions — bare `Clutter.` / `Meta.` wire prefixes
  with no lease
- Drop `CallParam`. Positional **`Request.args`** / **`Response.args`**.
  Typed **`Response.retval`** for the GIR C return. `Request.add_class` FFI
  handlers
- Bin protocol **v3.1** method-name tokens (`NAME_REF`)
- `OLLMrpc.rpc_register()`; client throws server errors to callers
- **GiMock** / `register_mock`: test-only GI dispatch that mints leased fakes for
  registered OBJECT / INTERFACE returns (including GIR pointer types); ctors no
  longer pack `val("o", null)`
- Nullable OBJECT returns and null `"o"` args pack safely (no `get_type()` on
  null)

### FILES

- `ollmfilesd` / `libocfiles`: File, Folder, FileHistory, ProjectManager,
  Codebase, and Daemon methods on positional `args`; `CallParam` bags
  deleted
- Client wrappers throw. UI surfaces failures with Banner / Alert (file
  dropdown, save / reload, approve / revert, project load / create /
  remove, overlay scan)
- Daemon boot uses `OLLMrpc.rpc_register()`; file payloads can ride the
  `Response` SCM buffer

### TOOLS

- **run_command**: Stop; last-slice tail (do not kill for length); live
  tool frame; wall-clock timeout; live output stream; spill file
- Sudo: first-draft **libsecret** store and two-second hold Allow; Exec
  approval shows the command as the bold label

### BROWSER

- WebDriver automation path for the browser tool (Linux RemoteInspector;
  Windows / Android CDP) — controlled views, session hand-off; fill/press
  smoke still open
- Hide `navigator.webdriver` when the linked WebKit `.so` exports the
  navigator-policy API (`HAVE_WEBKIT_NAVIGATOR_WEBDRIVER_POLICY`)
- Meson probes the WebKit `.so` for interactions (required) and navigator-policy
  (optional) — prefer `webkitgtk-6.0-webdriver`, else stock with interactions
  (Fedora / RPM)

### ANDROID

- About dialog no longer hangs; Add Model search TLS; settings tab order

## [1.3.0] - 2026-08-22

### Added

- **File daemon (`ollmfilesd`)**: project scan, file I/O, SQLite, and semantic
  indexing run out of the UI process. The app talks to the daemon over
  **`libocrpc`** (binary RPC). **`libocvector2`** is the daemon FAISS stack.
- **Sandbox (`libocbwrap`)**: shared bubblewrap / seccomp helpers for
  `run_command` and MCP stdio servers
- **Browser tool**: WebKitGTK `browser` on Linux, plus Windows WebView2 and
  Android WebView hosts — toggle/view chrome, downloads, fill-by-name
- **Agent Π**: compact coding agent (`liboccoder/AgentPi`) with Pi-style tools
  (`read` / `write` / `bash`), base skills, follow-up / urgent message queue,
  skills settings tab, and project-summary skill
- **Coding Assistant**: Chatter-style summarized conversation history —
  background summarizer after each turn, `summary` transcript role, and
  follow-up rounds that send only messages since the latest summary plus a
  `coder_followup.md` system tail (with `session_fetch` hash links)
- **Agents**: shared `OLLMchat.Agent.Summarizer` and `Agent.Base.create_summary()`
  used by Chatter, the Coding Assistant, and Agent Π
- **OpenAI-compatible APIs**: Chat, Embed, and Generate use the v1 Chat
  Completions path (`tool_calls` / `tool_call_id`)
- **run_command**: `run_as_root` runs via `sudo` after an in-app password prompt
  and explicit high-risk ChatPermission approval (Linux GTK app; no Allow Always)
- **Hugging Face**: `oc-hf` model catalog download with progress UI (local GGUF)
- **Local GGUF**: optional `CallLocal` / libllama backend (`-Dlocal_gguf`; still
  a proof of concept)
- **`libocrpc` live / GI**: object leases and notify proxy; optional positional
  `Request.values`; typelib register + `new` / invoke on a handle (`Gi`)
- **Android**: remote-only chat shell / POC APK — Config2, connections, default
  model, TLS, settings, browser host (`ollmapp/android/`), Agent Π skills
  catalog; WebView from webkitgtk-android **v0.1.3**
- **Packaging**: install from the [roojs repositories](https://roojs.github.io/repos/)
  (`apt` / `dnf` / `zypper`). Debian and RPM ship split libraries plus `-dev` /
  `-devel` packages (`libocrpc`, `libocrpc-dev`, …) alongside `ollmchat`;
  `ollmchat-remote-only` remains an all-in-one package without libllama.
  AppImage stays remote-only. Windows ships **`OLLMchat-<version>-Setup.exe`**
  from native MSYS2 (not Ubuntu cross / sqgipkg)
- **CI / release**: changelog-driven GitHub Release notes; per-family
  **Release - Debian / Fedora / openSUSE / AppImage / Windows / Android**
  jobs; tag builds attach the Android debug APK and Windows Setup.exe; RPM
  jobs on Fedora 44 and Tumbleweed

### Changed

- Applications load Config2 (`config.2.json`) only
- Open file / window / project state lives in config rather than the files DB
- Git operations go through the file daemon
- HTTP proxy is used only when the host is a real DNS name
- Coding Assistant system prompt is outbound-only — no longer persisted as
  `system` rows in the session transcript each turn
- Chatter summarizer moved from `Chatter.Summarizer` to the shared agent class
- Debian / docs / remote-only CI runs on Ubuntu 25.04 and installs `libllama-dev`
  from the roojs APT repo (no Debian-pool `.deb` hunting)
- Debian and RPM default layouts split each library into a runtime package and
  a `-dev` / `-devel` package (`libocrpc`, `libocrpc-dev`, …) so other apps can
  reuse the RPC library from the roojs repositories
- Windows release build is native MSYS2 UCRT64 on `windows-latest` (WebView2);
  sqgipkg is Linux AppImage only
- `ollmfilesd` no longer vendors RPC types; it consumes `libocrpc`
- Gee `HashMap` keys that are integer types use a stable hash so RPC handle
  maps work on 64-bit

### Removed

- Config1 and legacy `config.json` migration
- In-process v1 file / vector path (replaced by `ollmfilesd` + `libocvector2`)
- Tree-sitter Debian packaging script and FAISS / llama.cpp pool download helpers
  (packages come from the distro or the roojs repos)

### Fixed

- **Tool calling** on OpenAI-compatible backends (`tool_calls` / `tool_call_id`)
- **run_command** after the tool-calling fix; kill the process when output hits
  the existing line caps (100 sandboxed / 50 unsandboxed)
- **Add Model** / ollama.com search when switching connections; connection labels
  no longer duplicate the URL when name and URL match
- **Approvals / changed files**: approve and reject from the UI; notification
  updates when the changed-file list changes
- **RPC / daemon**: client write queue; stdio dispatch; second `ollmfilesd`
  startup no longer blocks the RPC stream
- **Composer / chat input** chrome and expand/collapse
- **Markdown**: ATX heading + bold stream hang; table top gap
- **SourceView**: opening a file no longer shows only the last line
- **Android**: TLS, IME freeze, browser globe toggle, icon theme

## [1.2.5-alpha] - 2026-07-24

Interim git tag. Changelog notes were still under Unreleased; they are now
listed under **1.3.0**.

## [1.2.4-alpha] - 2026-06-13

### Fixed

- Packaging: add missing release files
