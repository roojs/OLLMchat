# Changelog

All notable changes to OLLMchat are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for git tags (`v1.4.0`, etc.).

Debian and RPM packaging notes are generated from this file at release time
(see [Creating releases](docs/creating-releases.md)).

**AI agents:** Read that document before editing this file.

## [Unreleased]

### Changed

#### Packaging

- Debian 13 packages link `libwebkitgtk-6.0-webdriver` from the Trixie WebDriver build

## [1.4.8] - Unreleased

Work since **1.4.7** (2026-11-07).

### Changed

#### Packaging

- Windows releases publish one MSYS2 pacman package per library (DLL, import library, header, and VAPI)

## [1.4.7] - 2026-11-07

Work since **1.4.6** (2026-11-06).

### Changed

#### Packaging

- Ubuntu packages are built per release: 25.04 (`+plucky`, girepository 1.0), 25.10 (`+questing`), and 26.04 (plain revision)

## [1.4.6] - 2026-11-06

Work since **1.4.5** (2026-11-05).

### Changed

#### Markdown

- A bash fence is the shell listing, and the command is the title
- Live tool output and a restored bash result both use that fence
- The restored result is collapsed and shows the command
- Stop on that frame stops the running tools

#### Packaging

- Ubuntu 26.04 packages are the plain revision again, for 25.10 and resolute
- Debian 13 is an added Trixie build, versioned `+trixie`
- That Trixie build links stock WebKit until WebDriver is built for Debian

## [1.4.5] - 2026-11-05

Work since **1.4.4** (2026-11-04).

### Changed

#### ollmfilesd

- Long bash output spills under `tools/bash/YYYY/MM/DD` in the cache
- Starting the file daemon keeps the current spill month and the previous month, and deletes the rest

#### Bash

- Tool output uses Droid Sans Mono at 10pt

### Fixed

#### libocrpc

- `Transport.TlsClient` delivers a server notification that arrives during `call`, and `watch` keeps reading notifications while the socket is idle
- That idle read uses the TLS stream, stays up when the read times out, and skips the read when the stream is not readable so the next `call` is not held for the socket timeout
- A blocking subscription returns the remote handler's value in the signal's declared type, and `Callback.reply` completes that wait

#### Security

- Packages no longer embed a CA private key. Each server generates its own CA, and pairing returns only the public certificate

## [1.4.4] - 2026-11-04

Work since **1.4.3** (2026-11-03).

### Changed

#### libocrpc

- Pair publish can lower the minimum advertised TCP port; the default stays 1024

#### ollmfilesd

- `ProjectManager.db_projects` replaces `rpc_load_projects_from_db`
- Creating a project broadcasts `event.project.list_dirty` so other clients refresh the list

### Fixed

#### libocrpc

- An empty object array encodes as count `0` with no element type, so a one-shot TLS call no longer aborts
- `StreamValue` reads the stream live-handles flag instead of a missing connection

#### File browser

- Folder counts update when a folder is already in the tree, so hide-empty keeps non-empty folders
- File nav reloads the project tree after the folder load finishes

#### Android

- Bash tool output stays white on black
- Select project reloads when the daemon marks the project list dirty

#### Bash

- Long command output is spilled on the server, where the next `bash` call can open it

## [1.4.3] - 2026-11-03

Work since **1.4.2** (2026-11-03).

### Changed

#### Packaging

- Debian release packages are built on Ubuntu 26.04 with GIRepository 2.0
- GIRepository 2.0 requires version 2.86 or newer; older distributions keep the GIRepository 1.0 implementation

### Fixed

#### Packaging

- Native builds map all four `libocsqlite` outputs to their correct install destinations
- Monolithic Debian and RPM packages include the installed `ocsqlite.h`

## [1.4.2] - 2026-11-03

Work since **1.4.1** (2026-11-02).

### Added

#### libocrpc

- Newer distributions can use GIRepository 2.0 while older distributions keep the GIRepository 1.0 implementation

### Changed

#### Chat

- User-message quotes use the normal UI font and wrap long text

### Fixed

#### Packaging

- The Debian `libocsqlite-dev` and RPM `libocsqlite-devel` packages include `ocsqlite.h`

#### libocrpc

- GIRepository 2.0 is initialized on first use, avoiding a null repository when static methods run before class initialization

#### Android

- The model dropdown stays open on tablets

## [1.4.1] - 2026-11-02

Work since **1.4.0** (2026-10-02). The phone pairs with a desktop and uses that machine's file daemon. Agent Π opens the desktop's projects, reads and writes files there, and runs `bash` on `ollmfilesd`.

That is the path this release makes work: pairing through to `LIVE`, the project and folder sheets, and opening a file. The other notes are the file browser, the editor, and `libocrpc` from the same span.

### Added

#### libocrpc

- `Live.Buffer.from_bytes` writes a byte array into a new memfd
- `Live.Buffer.read_exact` drains that memfd
- `Transport.TlsClient` sends one or more requests on one TLS handshake

#### ollmfilesd

- Allow New Device publishes `_rpc._tcp` while the PIN dialog is open
- Those A records use `hostname-rpc.local`

#### Android

- Agent Π registers `bash` next to `read` and `write`
- `bash` runs on the desktop file daemon
- One agent manager owns which of editor, browser, and chat are visible
- An unreachable desktop asks Retry or Close
- Close leaves Agent Π and starts a Chatter session
- Retry shows **Checking desktop environment…** until the probe finishes

#### liboccoder

- Pending edits paint through `ChangeView` instead of replacing the whole buffer
- Edits on green and unchanged lines save back to the file server
- Red lines stay read-only
- The waiting row can show the assembled outbound message
- A list longer than the system prompt plus one user message shows only the last message

#### libollmchat

- A missing codebase-search model names the Settings row, the model, and the connection

### Changed

#### libocrpc

- Handler names outside the RPC daemon drop the `RPC-` prefix
- `RPC-Daemon` and `RPC-Live-*` keep it
- Phone registration and the address probe send those requests through `Transport.TlsClient`

#### Phone and tablet chrome

- The file-name button has no icon
- The project button and the file button sit closer together
- Save and the markdown toggle use icons that exist on Android
- The project list hides the subtitle under the selected project
- Recent / All and Tree / Recent show which one is selected
- A file row shows the modified time and the size
- A folder row keeps the relative path
- On the phone, the file sheet and the project sheet cover the composer and the model bar
- An approved phone is titled with the handset name, not `ollmchat`

#### Android editor

- The source view uses Droid Sans Mono, then monospace
- Pinch and Ctrl+wheel change that font, from 8 px to 64 px
- Android leaves the search bar hidden
- A file stays read-only until a long-press
- The editing hint shows once when the text view is mapped, and once when a document opens
- The editor button is only there for a coding agent, between browser and chat
- Vala highlighting runs because the language schema is packed in the APK
- Choosing a file leaves the caret out of the file field

### Fixed

#### libocrpc

- `Live.Hook.emit` returns when the connection has already stopped
- Opening Settings no longer crashes on the SSL host dropdown
- A signal emit exports an object argument the connection had not leased
- A private runtime type is sent as its declared public type
- An unregistered runtime type walks up to a registered parent
- A handler that returns bool finishes before that signal emission ends
- A blocking void signal waits for the remote reply
- `File.read` keeps strings longer than 32767 bytes

#### Android pairing

- The PIN dialog browses before it registers
- A pair request stores the signed certificate and the CA
- Hello gets past “certificate not registered”
- The live client reads the socket with the shared `IOChannel` watch
- A finished pair reaches `LIVE`, shows Agent Π, and loads project files

#### Phone

- A project tap opens the project list after Agent Π is live
- Choosing a project or a folder does not focus the chat entry or raise the keyboard
- Opening a file no longer aborts when the hunk list is empty
- Opening a project leaves **Loading folders** and shows the first level
- The chat scroll idle stops, so an idle handset is not held on one core

#### Files

- Opening the folder tree sends `Folder.fetch_children`
- **All** lists every project
- Selector search takes focus, and the file-search bar keeps its height
- Clicking a folder loads that directory
- An empty folder says **No files**
- Switching back to a project reloads that project's tree
- Opening a project no longer hangs on the folder-count query
- Building the folder tree no longer takes about two seconds
- The file grid shows the size from the last directory scan
- The file sheet opens on the open file's folder and highlights that row
- A folder linked into the project shows in the tree
- Loading projects stays connected when a file row includes `size`
- The tablet location row shows each folder name as a button
- Scrolling the folder list leaves the file list where it is
- Picking the open project from Recent keeps it in the list
- Opening a project folder fills the file pane instead of leaving it on Loading

## [1.4.0] - 2026-10-02

Work since **1.3.0** (2026-08-22). `libocrpc` drops `CallParam` and uses bin protocol **v3.1**.

Not in this release: PIN pairing and mDNS (the dialog only), the LAN client, the Windows desktop server, Android remote `bash`, source-view diff approval, and WebDriver fill/press. Still open on device: phone chrome, editor scroll, pinch-zoom, the Add Model popover, and codebase-search markdown.

### Added

#### libocrpc

- The HTTP server maps a path to a type, with JSON, NDJSON streaming, and bin POST
- `HttpClient` calls that server in JSON or bin and can reset the session
- `Client.call_poll` waits on the socket without a nested `MainLoop`
- `call_poll` keeps SCM file descriptors attached to the reply
- A live GI callback can be registered, invoked, and answered
- `Response` can carry `SCM_RIGHTS` file descriptors
- Top-level GI functions such as `Clutter.` and `Meta.` need no object lease
- A live object can subscribe to `notify::` property signals
- `rpc_signal_alias` maps a notify name onto another signal
- Several signals can be registered in one call
- GiMock mints a leased fake when a test return is an object or interface

#### ollmfilesd

- The daemon can listen on HTTPS with the product CA
- An unknown client certificate can request registration
- File Server settings can accept, reject, or ban that request
- Desktop can check a remote file daemon and reconnect to it
- Android opens a file connection over HTTPS and takes over the project
- `SslListen` serves bin RPC on the LAN with the same client certificates
- Desktop server rows show Unix, systemd, HTTPS, and the LAN SSL listener
- Allow New Device opens a one-minute PIN dialog. Pairing is not wired yet

#### Android

- The phone uses one stack. The tablet uses a side-by-side pane
- Agent Π runs only while the desktop environment is reachable, with `read` and `write`
- The phone shows a startup bar, a history bar, and editor chrome

#### liboccoder

- SourceView draws backup-versus-disk hunks on files waiting for approval
- The diff test app includes a ReviewBar for those hunks

#### liboctools

- `run_command` can be stopped from the tool frame
- Long command output keeps the last slice
- Command output streams into the live tool frame
- `run_command` stops when its wall-clock timeout is hit
- Output past the cap spills to a file
- The sudo password can be stored in libsecret
- Allow on a sudo prompt stays down for two seconds
- The exec approval label is the command

#### libocwebkit

- The browser tool can drive a page through WebDriver
- Linux uses RemoteInspector. Windows and Android use CDP
- Automation attaches only to views opened as controlled
- The tool session is handed to that controlled view

### Changed

#### libocrpc

- `CallParam` bags are removed
- Arguments are positional `Request.args` and `Response.args`
- The GIR C return is `Response.retval`
- FFI classes register with `Request.add_class`
- Bin protocol v3.1 sends method names as `NAME_REF` tokens
- FFI resolves each symbol once and reuses that slot
- Daemons boot through `OLLMrpc.rpc_register()`
- A server error is thrown to the caller
- A file payload can travel in the `Response` SCM buffer
- The same lease id returns the existing live proxy
- `Live.Interface` replaces the `Live.Handle` class
- Live `Object.new` waits for `TOKEN_END` before a nested call can run
- GI and FFI cover boxed structs, floats, numeric arrays, enums, and flags
- GI and FFI cover INOUT arguments and GList IN
- A GType can be sent with an explicit alias
- `GValue` arguments use the `V` wire type
- A bin type override can replace the GIR type on the wire
- An `ANY[]` value reads its type token before the value

#### ollmfilesd / libocfiles

- File, Folder, FileHistory, ProjectManager, Codebase, and Daemon take positional `args`
- Those client wrappers throw
- The UI shows those failures as a Banner or an Alert
- The HTTPS switch is `https_enabled`
- `ssl_enabled` turns on the LAN TLS listener
- The Linux daemon still listens on its Unix socket
- Tree-sitter stays in the daemon
- A pending file stores `reviewed`, `file_diff_part`, and `backup_path`

#### libocwebkit

- `navigator.webdriver` is hidden when the linked WebKit exports that API
- The build uses `webkitgtk-6.0-webdriver` when it is installed

### Fixed

#### libocrpc

- A null object return no longer calls `get_type()`
- A null `"o"` argument is packed safely
- UTF-8 strings stay valid across a GI call
- FLAGS values travel as uint
- An inout float no longer crashes
- Lease id `0` is rejected
- An FFI string array keeps its length
- Out `GValue`s are initialized before `get_property`
- A signal emit still includes its arguments when there is no reply frame
- A null object argument is written with a real type on the wire
- `libocrpc-dev` and `libocrpc-devel` install `ocrpc.h`

#### ollmfilesd

- Saving Config2 keeps the `filesd` block
- The file-server port can be edited
- File-server edits apply when they change
- The filesd systemd unit starts the daemon
- Windows uses the configured loopback port

#### libollamaweb

- A non-200 Ollama response throws the JSON `error` text
- A missing model reports that Ollama error

#### ollmapp

- Startup finishes when the selected model has been deleted

#### libollmchatgtk

- SortedList finalize disconnects each handler once

#### liboccoder

- A ReviewBar hover menu closes when the pointer leaves
- A ReviewBar menu closes on click-away
- The first prev or next click moves the review

#### Android

- The About dialog opens
- Add Model search reaches the catalog over TLS
- Settings tabs follow the desktop order
- The browser loads the page
- Checking a connection no longer crashes
- Checking a connection keeps the URL that was typed

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
