# 8.2.8.10 — URGENT — `bash` as a remote tool Android can use

**Status:** **URGENT** — Phase 1 has code proposals; Phases 2–3 design only

> **Do not update** `docs/plans/RPC-1.0-summary.md` **for this sub-plan.**

**Parent:** [`RPC-8.2.8-filesd-connections-ui.md`](RPC-8.2.8-filesd-connections-ui.md) Phase 12

**Depends on:**

- [`RPC-8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) — Agent Pi on `LIVE` / `SOCKET`. Registers `write` / `read` only. Does not register `Bash`.
- [`BWRAP-2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) — daemon `Bubble.can_wrap` / `Bubble.exec` wire. Not on the wire yet.

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`.

---

## Purpose

- **🔷** A separate ticket. Not stuffed into [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md).
- **🔷** Turn `bash` into a tool the phone can use **remotely**.
  - The command runs on the desktop `ollmfilesd`.
  - Not on the phone.
- **ℹ️** [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) already said that. It pointed at [`BWRAP-2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) and left no child ticket.
- **ℹ️** [`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) is the daemon sandbox RPC. This ticket is the Android `bash` **tool**.
- **🔷** `⏳` Phase 1 (daemon `Bubble.*`) has code fences here. Phase 2 and Phase 3 fences wait on the caller shape.

---

## Current behaviour

- **ℹ️** `liboctools/RunCommand/Bash.vala` is a Pi-facing name on `RunCommand.Tool`. Same `Request` as `run_command`.
- **ℹ️** `Request.execute_tool_async` calls in-process `OLLMbwrap.Bubble.exec` (or `GLib.Subprocess` when bwrap is missing / Flatpak / `run_as_root`).
- **ℹ️** Overlay apply after a local exec is File.* RPC ([`done/2.10.4.19-DONE-runcommand-overlay-index.md`](done/2.10.4.19-DONE-runcommand-overlay-index.md)). The command itself never left the app process.
- **ℹ️** `write` / `read` already go through `ProjectManager` RPC when the client is on HTTPS.
- **ℹ️** Android `initialize_client` registers `write` / `read` only ([`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md) Phase 2).
- **ℹ️** `AgentPi.Factory.register_config` `GLib.error`s without `write` / `read` / `bash`. Android therefore does not call `register_config` yet.
- **ℹ️** Daemon `Bubble.*` is still **DEFERRED** ([`FILES-2.10.4.1`](FILES-2.10.4.1-ollmfilesd-rpc-api.md) · [`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md)).

---

## Design decisions

- **🔷** Phone `bash` is an RPC tool. Exec is on the desktop daemon.
- **🔷** Do not register in-process `Bash` on Android.
- **ℹ️** Wire names and result shape stay [`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) Phase A (`Bubble.can_wrap`, `Bubble.exec`). Do not invent a second exec object.
- **🔷** `Bubble.exec` on `ollmfilesd` is the one exec path.
  - Linux desktop does not keep a separate in-process `OLLMbwrap.Bubble.exec` as the future path.
  - Callers go through that RPC.
  - That RPC is also how this is tested.
- **🔷** Keep the `Bash` class for now. The name is the Agent Pi tool (`bash`). It stays a wrapper on `RunCommand.Tool`.
- **🔷** After `Bubble.exec` is on the wire, Android registers `Bash`, then `AgentPi.Factory.register_config`.
  - Same order as `write` / `read` today.
- **ℹ️** `Bash` today only sets `name`, `title`, and `example_call`. `Request.execute_tool_async` is what spawns. Whether that method is the only edit is not decided.
- **🔷** Whether this needs another V2 cutover is open.
  - [`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) still says the daemon RPC caller lands at the V2 flip, and that in-app `OLLMbwrap` can ship sooner.
  - This ticket does not decide that.
  - Do not treat “Phase A ships, skip V2” as a requirement.

---

## Phase 1 — Daemon `Bubble.exec` (`⏳`)

- **ℹ️** Full design, params, and vetoes live in [`BWRAP-2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) Phase A. **Read that first.** The bullets below are only the parts needed to review the hunks in this phase.
- **ℹ️** Whether Phase A waits on another V2 flip is the open question in Design decisions. [`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) still lists the `RunCommand` caller as “at V2 flip only”.

### Key design (summary — `2.10.4.15` is the source)

- **🔷** `⏳` `ollmfilesd` answers `can_wrap` and `exec` on one wire object. No second exec object.
- **🔷** `exec` params: `project_path`, `command`, `working_dir`, `network`, `allow_write`.
  - `project_path` empty = no-project mode.
  - `command` is an `sh -c` shell string.
  - `allow_write` is `no` / `project` / absolute roots.
- **🔷** Sandbox work is `OLLMbwrap` on the daemon. `ollmfilesd` only resolves the project, builds write roots, and replies.
- **🔷** Overlay apply and index update are the daemon's job — `OLLMbwrap.Scan` plus a daemon `FileVerification`.
- **🚫** `run_as_root` / sudo on the wire. **🚫** Client Flatpak / Windows unsandboxed fallback. **🚫** `Exec.vala`. **🚫** MCP stdio session (`2.10.4.15` Phase B).

### Wire shape — tree does not match `2.10.4.15` Phase A

- **ℹ️** `2.10.4.15` Phase A writes the wire as JSON (`"method":"Bubble.exec"`, a `params` object, `BubbleParams` in `ollmfilesd/CallParam.vala`). The shipping daemon does not dispatch that way.
- **ℹ️** Shipping dispatch is `OLLMrpc.Request.add_class(prefix, type, suffix, signature)` plus `OLLMrpc.Request.register(prefix, instance)`, with **positional** `request.args`. See `ollmfilesd/Folder.vala` and `ollmfilesd/File.vala`.
- **ℹ️** There is no `ollmfilesd/CallParam.vala` and no `*Params` class in the tree. That part of `2.10.4.15` is stale.
- **💩** So the proposals below use the shipping style. Decisions you may want to overrule:
  - Prefix is `RPC-Bubble`, like `RPC-File` / `RPC-Folder`. Wire names become `RPC-Bubble.can_wrap` and `RPC-Bubble.rpc_exec` (the `rpc_` prefix is on the wire — compare `RPC-File.rpc_write`).
  - `exec` signature string is `sssbS`.
  - `can_wrap` replies `msg` = `1` / `0`. `OLLMbwrap.Bubble.can_wrap()` is a bool with no `reason`, so the `{available, reason}` result in `2.10.4.15` has nothing to fill `reason` with.
  - `exec` replies `msg` = the exec output string. `OLLMbwrap.Bubble.exec` already embeds exit code and seccomp evidence in that string, so the 4-field result object (`output`, `exit_code`, `seccomp_network`, `seccomp_fs`) in `2.10.4.15` would need a new return type on `OLLMbwrap.Bubble`.
  - Error codes `-32001` / `-32003` / `-32004` from `2.10.4.15` are **not** in `OLLMrpc.RpcErrorCode` (`PARSE_ERROR`, `INVALID_REQUEST`, `METHOD_NOT_FOUND`, `INVALID_PARAMS`, `INTERNAL_ERROR`, `NOT_IMPLEMENTED`). Proposals use `INTERNAL_ERROR`, and a plain `msg` for “project not found” the way `Folder.rpc_roots` does.

### Gaps this phase does not close

- **💩** `⏳` No live output. In-process `RunCommand.Request` streams `bubble.output` into `client.run_tool.output` notifications. A one-shot reply gives the phone nothing until the command ends.
- **💩** `⏳` No stop and no timeout. `Request.stop()` calls `bubble.stop()` in-process. Over RPC there is no handle to kill the daemon child.
- **ℹ️** Both are Phase 2 caller concerns. Naming them here so the one-shot reply is not mistaken for feature parity.

Edits are **Remove** / **Replace with** / **Add** against the tree. Verify surrounding context before applying. `ollmfilesd` is not in the `docs/meson.build` valadoc inputs, so these new files need no valadoc entry.

### 1. `ollmfilesd/meson.build` — link `ocbwrap`

**Why:** The daemon does not link `libocbwrap` today. `libocbwrap` is already `subdir()`-ed before `ollmfilesd` in the root `meson.build`, so `ocbwrap_vapi_dep` exists. Windows gets the `libocbwrap/windows/*` stubs from the same dependency, so no `is_windows` branch is needed here.

**Where:** `ollmfilesd_deps`, `ollmfilesd_src`, `build_rpath`, `include_directories`, and `vala_args`.

#### Remove

```meson
  ocvector2_vapi_dep,
]
```

#### Replace with

```meson
  ocvector2_vapi_dep,
  ocbwrap_vapi_dep,
]
```

#### Remove

```meson
  'SQT/VectorMetadata.vala',
  'Daemon.vala',
```

#### Replace with

```meson
  'SQT/VectorMetadata.vala',
  'FileVerification.vala',
  'Sandbox/Bubble.vala',
  'Daemon.vala',
```

#### Remove

```meson
  meson.current_build_dir() / '..' / 'libocvector2',
])
```

#### Replace with

```meson
  meson.current_build_dir() / '..' / 'libocvector2',
  meson.current_build_dir() / '..' / 'libocbwrap',
])
```

#### Remove

```meson
    include_directories('../libocvector2'),
  ],
```

#### Replace with

```meson
    include_directories('../libocvector2'),
    include_directories('../libocbwrap'),
  ],
```

#### Remove

```meson
    '--pkg=ocvector2',
    '--pkg=libsoup-3.0',
```

#### Replace with

```meson
    '--pkg=ocvector2',
    '--pkg=ocbwrap',
    '--pkg=libsoup-3.0',
```

#### Remove

```meson
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector2',
```

#### Replace with

```meson
    '--vapidir', meson.current_build_dir() / '..' / 'libocvector2',
    '--vapidir', meson.current_build_dir() / '..' / 'libocbwrap',
```

### 2. `ollmfilesd/FileVerification.vala` — apply overlay writes on the daemon

**Why:** `OLLMbwrap.Scan` decides created / modified / removed; the `FileVerification` implementation is what actually writes to the live filesystem and the index. `OLLMbwrap.NoOpFileVerification` **discards** overlay writes, so the daemon needs a real one or every sandboxed write is lost.

**Where:** New file. Daemon mirror of `liboctools/FileVerification.vala`, with the bodies from `File.write` in `ollmfilesd/File.vala` instead of `rpc_write` round-trips.

**Depends on:** §1 (`--pkg=ocbwrap`).

- **ℹ️** This is a **copy** of two approved blocks, not new code:
  - Class shape and all five method bodies — `liboctools/FileVerification.vala` **verbatim**.
  - The `switch (base_type)` that ends `created` / `modified` — `File.write` in `ollmfilesd/File.vala` **verbatim** (`path` reads `real_path`). That method is the current receiver of the in-app `rpc_write` call, so this is the same code the write already runs, minus the round trip.
- **ℹ️** Blanket `try` per method, `Banner.show` on failure, private fields assigned in the constructor, duplicated `created` / `modified`, nullable `project` — all **as approved**. Not restyled.
- **ℹ️** The `catch` is forced anyway: `created` / `modified` / `removed` / `finish` on `OLLMbwrap.FileVerification` have no `throws`, so an implementation cannot propagate. Only `has_file` has `throws`.
- **💩** Only three substitutions, each because the in-app call has no daemon counterpart:
  - `yield new OLLMfiles.File.new_fake(…).rpc_write(…)` → the `File.write` switch above. The daemon is the write target; it cannot RPC itself.
  - `yield this.project.fetch_file(real_path)` — **dropped** in `has_file`, replaced by `get_file_from_active_project` / `get_folder_at_path` in `removed`. `fetch_file` is the client warming its cache **from** this daemon; there is no such method in `ollmfilesd`, and the daemon already holds the index.
    - **💩** `has_file` therefore answers from `file_cache` only. A row that is in the database but not loaded in memory reads as `UNKNOWN`, which `Scan` treats as created rather than modified. If that matters, the fix is a DB lookup here — say so and I will add one.
  - `this.manager.review_files.refresh()` → `this.project.refresh_review()`, and `this.manager.rpc.notification` → `this.manager.notification`. Daemon names for the same two calls.

#### Add

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfilesd
{
	/**
	 * Applies overlay scan results to the daemon filesystem and index.
	 *
	 * {@link OLLMbwrap.Scan} walks the overlay upper layer after
	 * {@link OLLMbwrap.Bubble.exec} and calls one method per change.
	 * Each change is realized through {@link Folder}, {@link FileAlias},
	 * and {@link File}, and removals retire through
	 * {@link DeleteManager} — the same work ''RPC-File.rpc_write'' and
	 * ''RPC-File.rpc_delete'' do for a remote client. In-app callers use
	 * {@link OLLMtools.FileVerification}, which sends those two calls over
	 * RPC; nothing here leaves the daemon.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var bubble = new OLLMbwrap.Bubble(
	 *     new OLLMfilesd.FileVerification(project, manager));
	 * bubble.project_path = project.path;
	 * var output = yield bubble.exec("make test", "");
	 * }}}
	 */
	public class FileVerification : GLib.Object, OLLMbwrap.FileVerification
	{
		private ProjectManager manager;
		private Folder? project;

		/**
		 * @param project Active project, or null when no project is open
		 * @param manager Project manager for the index and file_cache
		 */
		public FileVerification(
			Folder? project,
			ProjectManager manager)
		{
			this.project = project;
			this.manager = manager;
		}

		public override async GLib.FileType has_file(string real_path) throws GLib.Error
		{
			if (this.project == null) {
				return GLib.FileType.UNKNOWN;
			}
			if (!this.manager.file_cache.has_key(real_path)) {
				return GLib.FileType.UNKNOWN;
			}
			var item = this.manager.file_cache.get(real_path);
			if (item.base_type == "d") {
				return GLib.FileType.DIRECTORY;
			}
			if (item.base_type == "fa") {
				return GLib.FileType.SYMBOLIC_LINK;
			}
			return GLib.FileType.REGULAR;
		}

		public async void created(
			GLib.FileType file_type,
			string real_path,
			string overlay_path)
		{
			if (this.project == null) {
				return;
			}
			try {
				var base_type = "f";
				var content = "";
				var target = "";
				switch (file_type) {
					case GLib.FileType.DIRECTORY:
						base_type = "d";
						break;

					case GLib.FileType.SYMBOLIC_LINK:
						base_type = "fa";
						var link = GLib.FileUtils.read_link(overlay_path);
						if (link == null) {
							throw new GLib.IOError.FAILED("Cannot read symlink target");
						}
						target = link;
						break;

					case GLib.FileType.REGULAR:
						var bytes = GLib.File.new_for_path(
							overlay_path
						).load_bytes(null);
						content = (string) bytes.get_data();
						break;

					default:
						break;
				}
				var unix_mode = 0U;
				try {
					var info = GLib.File.new_for_path(overlay_path).query_info(
						GLib.FileAttribute.UNIX_MODE,
						GLib.FileQueryInfoFlags.NONE,
						null
					);
					unix_mode = info.get_attribute_uint32(
						GLib.FileAttribute.UNIX_MODE
					) & 0777;
				} catch (GLib.Error e) {
					GLib.warning(
						"Cannot query overlay mode (%s): %s",
						overlay_path,
						e.message
					);
				}
				switch (base_type) {
					case "d": {
						var folder = this.manager.get_folder_at_path(real_path);
						if (folder == null) {
							folder = new Folder(this.manager) {
								path = real_path,
								id = -1
							};
						}
						if (folder.id < 0) {
							yield folder.to_real();
						}
						yield folder.realize(unix_mode);
						break;
					}
					case "fa": {
						var alias = this.manager.file_cache.get(
							real_path
						) as FileAlias;
						if (alias == null) {
							alias = new FileAlias(this.manager) {
								path = real_path,
								id = -1
							};
						}
						if (alias.id < 0) {
							yield alias.to_real(target);
						}
						yield alias.realize(target, unix_mode);
						break;
					}
					default: {
						var file = this.manager.get_file_from_active_project(
							real_path
						);
						if (file == null) {
							file = new File(this.manager) {
								path = real_path,
								id = -1
							};
						}
						var change_type = file.id < 0 ? "added" : "modified";
						if (file.id < 0) {
							yield file.to_real();
						}
						if (change_type == "modified" && this.manager.db != null) {
							file.is_need_approval = true;
							file.last_change_type = "modified";
							var file_history = new FileHistory(
								this.manager.db,
								file,
								"modified",
								new GLib.DateTime.now_local()
							);
							yield file_history.commit();
							file.saveToDB(this.manager.db, null, false);
						}
						yield file.realize(content, unix_mode);
						if (change_type == "modified") {
							this.manager.notification(new OLLMrpc.Notification() {
								method = "event.project.invalidate_cache",
								object_type = "Project",
								message = this.manager.active_project.path
							});
						}
						break;
					}
				}
			} catch (GLib.Error e) {
				GLib.critical("overlay created failed %s: %s", real_path, e.message);
				this.manager.notification(new OLLMrpc.Notification() {
					method = "Banner.show",
					message = "Could not save overlay file: " + real_path
				});
			}
		}

		public async void modified(
			GLib.FileType file_type,
			string real_path,
			string overlay_path)
		{
			if (this.project == null) {
				return;
			}
			try {
				var base_type = "f";
				var content = "";
				var target = "";
				switch (file_type) {
					case GLib.FileType.DIRECTORY:
						base_type = "d";
						break;

					case GLib.FileType.SYMBOLIC_LINK:
						base_type = "fa";
						var link = GLib.FileUtils.read_link(overlay_path);
						if (link == null) {
							throw new GLib.IOError.FAILED("Cannot read symlink target");
						}
						target = link;
						break;

					case GLib.FileType.REGULAR:
						var bytes = GLib.File.new_for_path(
							overlay_path
						).load_bytes(null);
						content = (string) bytes.get_data();
						break;

					default:
						break;
				}
				var unix_mode = 0U;
				try {
					var info = GLib.File.new_for_path(overlay_path).query_info(
						GLib.FileAttribute.UNIX_MODE,
						GLib.FileQueryInfoFlags.NONE,
						null
					);
					unix_mode = info.get_attribute_uint32(
						GLib.FileAttribute.UNIX_MODE
					) & 0777;
				} catch (GLib.Error e) {
					GLib.warning(
						"Cannot query overlay mode (%s): %s",
						overlay_path,
						e.message
					);
				}
				switch (base_type) {
					case "d": {
						var folder = this.manager.get_folder_at_path(real_path);
						if (folder == null) {
							folder = new Folder(this.manager) {
								path = real_path,
								id = -1
							};
						}
						if (folder.id < 0) {
							yield folder.to_real();
						}
						yield folder.realize(unix_mode);
						break;
					}
					case "fa": {
						var alias = this.manager.file_cache.get(
							real_path
						) as FileAlias;
						if (alias == null) {
							alias = new FileAlias(this.manager) {
								path = real_path,
								id = -1
							};
						}
						if (alias.id < 0) {
							yield alias.to_real(target);
						}
						yield alias.realize(target, unix_mode);
						break;
					}
					default: {
						var file = this.manager.get_file_from_active_project(
							real_path
						);
						if (file == null) {
							file = new File(this.manager) {
								path = real_path,
								id = -1
							};
						}
						var change_type = file.id < 0 ? "added" : "modified";
						if (file.id < 0) {
							yield file.to_real();
						}
						if (change_type == "modified" && this.manager.db != null) {
							file.is_need_approval = true;
							file.last_change_type = "modified";
							var file_history = new FileHistory(
								this.manager.db,
								file,
								"modified",
								new GLib.DateTime.now_local()
							);
							yield file_history.commit();
							file.saveToDB(this.manager.db, null, false);
						}
						yield file.realize(content, unix_mode);
						if (change_type == "modified") {
							this.manager.notification(new OLLMrpc.Notification() {
								method = "event.project.invalidate_cache",
								object_type = "Project",
								message = this.manager.active_project.path
							});
						}
						break;
					}
				}
			} catch (GLib.Error e) {
				GLib.critical("overlay modified failed %s: %s", real_path, e.message);
				this.manager.notification(new OLLMrpc.Notification() {
					method = "Banner.show",
					message = "Could not update overlay file: " + real_path
				});
			}
		}

		public async void removed(
			GLib.FileType file_type,
			string real_path,
			string overlay_path)
		{
			if (this.project == null) {
				return;
			}
			FileBase? filebase = null;
			if (this.manager.file_cache.has_key(real_path)) {
				filebase = this.manager.file_cache.get(real_path);
			}
			if (filebase == null) {
				filebase = this.manager.get_file_from_active_project(real_path);
			}
			if (filebase == null) {
				filebase = this.manager.get_folder_at_path(real_path);
			}
			if (filebase == null) {
				return;
			}
			try {
				yield this.manager.delete_manager.remove(
					filebase,
					new GLib.DateTime.now_local()
				);
			} catch (GLib.Error e) {
				GLib.critical("overlay removed failed %s: %s", real_path, e.message);
				this.manager.notification(new OLLMrpc.Notification() {
					method = "Banner.show",
					message = "Could not remove overlay path: " + real_path
				});
			}
		}

		public async void finish()
		{
			if (this.project == null) {
				return;
			}
			yield this.manager.delete_manager.cleanup();
			this.project.refresh_review();
		}
	}
}
```

### 3. `ollmfilesd/Sandbox/Bubble.vala` — `RPC-Bubble` handlers

**Why:** `2.10.4.15` wants RPC glue only — no `Exec.vala`, no `Sandbox/*` copy under `ollmfilesd/`. This class resolves the project, builds `write_roots`, and hands off to `OLLMbwrap.Bubble`.

**Where:** New file, new `ollmfilesd/Sandbox/` directory. Handler shape copies `ollmfilesd/File.vala`: typed FFI entry point, then a private `async` method that re-reads `request.args`.

**Depends on:** §1 and §2.

- **ℹ️** The private `async exec` is not an optional helper. The FFI entry point cannot `yield`, so every async daemon handler is split this way (`File.rpc_write` → `File.write`, `Codebase.rpc_search` → `Codebase.search`). This plan names it.
- **ℹ️** The project / `write_roots` / `Bubble` setup is copied from `execute_tool_async` in `liboctools/RunCommand/Request.vala`, including the nullable `project` and the `// avoid async vala ctor bug` property assignments.
- **💩** `write_roots` is one entry, `project.path` → `project.path`, matching in-process `RunCommand.Request` today. `Folder.roots()` would widen writes to every distinct project root; not changing that here.
- **💩** `project_path` empty means no-project mode, so `project` stays null and `FileVerification` early-returns — same as in-app with no project open. No `OLLMbwrap.NoOpFileVerification` needed.

#### Add

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMfilesd.Sandbox
{
	/**
	 * Server ''RPC-Bubble.*'' wire handlers — sandbox availability and
	 * one-shot command execution on the daemon.
	 *
	 * {@link OLLMbwrap.Bubble} owns the bubblewrap spawn, overlay, and
	 * seccomp stack. This class is RPC glue: it resolves the project,
	 * builds the writable roots, and replies with the command output.
	 * Overlay writes land through {@link OLLMfilesd.FileVerification}.
	 * Registered once in {@link OllmfilesdApplication}. Arguments arrive
	 * on {@link OLLMrpc.Request.args}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMfilesd.Sandbox.Bubble.rpc_register();
	 * OLLMrpc.Request.register(
	 *     "RPC-Bubble", new OLLMfilesd.Sandbox.Bubble(project_manager));
	 * var req = new OLLMrpc.Request() {
	 *     method = "RPC-Bubble.rpc_exec",
	 *     args = OLLMrpc.args("sssbS", path, "make test", "", false, roots)
	 * };
	 * }}}
	 */
	public class Bubble : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Bubble", typeof(Bubble),
				"can_wrap", "",
				"rpc_exec", "sssbS"
			);
		}

		public ProjectManager manager { get; construct; }

		public Bubble(ProjectManager manager)
		{
			GLib.Object(manager: manager);
		}

		/**
		 * ''RPC-Bubble.can_wrap'' — whether bubblewrap is usable on this
		 * daemon host.
		 *
		 * Reply ''msg'' is ''1'' or ''0''.
		 * {@link OLLMbwrap.Bubble.can_wrap} reports no reason string, so
		 * there is nothing to send alongside it.
		 *
		 * @param request inbound RPC
		 */
		public void can_wrap(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = OLLMbwrap.Bubble.can_wrap() ? "1" : "0"
			});
		}

		/**
		 * ''RPC-Bubble.rpc_exec'' — run one shell command in the daemon
		 * sandbox.
		 *
		 * The typed parameters are the FFI signature; {@link exec}
		 * re-reads them from {@link OLLMrpc.Request.args}.
		 *
		 * @param request inbound RPC
		 * @param project_path project root, or empty for no-project mode
		 * @param command ''sh -c'' shell string
		 * @param working_dir absolute path, or empty for the first root
		 * @param network true leaves the network namespace shared
		 * @param allow_write ''no'' / ''project'' / absolute roots
		 */
		public void rpc_exec(
			OLLMrpc.Request request,
			string project_path, string command, string working_dir,
			bool network, string[] allow_write
		) {
			this.exec.begin(request, (obj, res) => {
				this.exec.end(res);
			});
		}

		/**
		 * Reply to {@link rpc_exec} after the sandboxed command ends.
		 *
		 * Reply ''msg'' is the {@link OLLMbwrap.Bubble.exec} string, which
		 * already carries the exit code and any seccomp evidence.
		 *
		 * @param request the RPC request to reply to
		 */
		private async void exec(OLLMrpc.Request request)
		{
			if (!OLLMbwrap.Bubble.can_wrap()) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"sandbox unavailable"
					)
				});
				return;
			}
			var project_path = request.args.get(0).get_string();
			var command = request.args.get(1).get_string();
			var working_dir = request.args.get(2).get_string();
			var network = request.args.get(3).get_boolean();
			var allow_write = (string[]) request.args.get(4).get_boxed();
			var project = this.manager.project_root(project_path);
			if (project_path != "" && project == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "project not found"
				});
				return;
			}
			var write_roots = new Gee.HashMap<string, string>();
			if (project != null) {
				write_roots.set(project.path, project.path);
			}
			// avoid async vala ctor bug
			var bubble = new OLLMbwrap.Bubble(
				new FileVerification(project, this.manager));
			bubble.project_path = project_path;
			bubble.allow_network = network;
			bubble.write_tokens = allow_write;
			bubble.write_roots = write_roots;
			var output = "";
			try {
				output = yield bubble.exec(command, working_dir);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						e.message
					)
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = output
			});
		}
	}
}
```

### 4. `ollmfilesd/Application.vala` — register `RPC-Bubble`

**Why:** `add_class` fills the method table; `register` binds the handler instance. Both are needed before the first request arrives.

**Where:** The `rpc_register()` run and the `OLLMrpc.Request.register(...)` block in daemon startup.

**Depends on:** §3.

#### Remove

```vala
			SQT.VectorMetadata.rpc_register();
			Codebase.rpc_register();
```

#### Replace with

```vala
			SQT.VectorMetadata.rpc_register();
			Codebase.rpc_register();
			Sandbox.Bubble.rpc_register();
```

#### Remove

```vala
			OLLMrpc.Request.register("RPC-Codebase", 
				new Codebase(this.project_manager, this.config));
```

#### Replace with

```vala
			OLLMrpc.Request.register("RPC-Codebase", 
				new Codebase(this.project_manager, this.config));
			OLLMrpc.Request.register("RPC-Bubble",
				new Sandbox.Bubble(this.project_manager));
```

### Testing Phase 1

- **🔷** `⏳` `RPC-Bubble.*` is the primary way to test this. Exercise it before any caller change.
- **💩** `⏳` `oc-rpc-script` / `--interactive` on the daemon drives `RPC-Bubble.can_wrap` and `RPC-Bubble.rpc_exec` without touching `RunCommand`. `2.10.4.15` calls this the T3 harness.
- **💩** `⏳` Smoke the overlay path too, not just exit codes: a command that creates, edits, and deletes a project file should leave the index and the live tree correct through §2.

---

## Phase 2 — `RunCommand.Request` calls `Bubble.exec` over RPC (`⏳`)

- **🔷** `⏳` When the file client is `LIVE`, `Request` runs the command through `Bubble.exec` RPC. Not `OLLMbwrap` in the Android process.
- **ℹ️** `SOCKET` is the desktop local Unix hello ([`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md)). `ollmfilesd` is already up on this machine. Empty `url`. Not a remote row.
- **🔷** What `SOCKET` does for exec is not decided. Not enough here to choose in-process bwrap versus the same `Bubble.exec` RPC.
  - It hangs on the open V2 question above.
  - It also hangs on RPC being the one exec path.
- **ℹ️** Overlay / index update after daemon exec is the daemon's job in `2.10.4.15` (`Scan` + `FileVerification` on `ollmfilesd`).
- **⏳** Code proposals — after Phase 1 is on the wire.

---

## Phase 3 — Android registers `bash` (`⏳`)

- **🔷** `⏳` `ollmapp/android/OllmchatWindow.vala` `initialize_client` registers `OLLMtools.RunCommand.Bash` next to `write` / `read`, then `AgentPi.Factory.register_config`.
- **🔷** `⏳` Still no in-process exec on the phone. Registration is only valid once Phase 2 uses RPC.
- **⏳** Code proposals — after Phase 2 compiles.

---

## Suggested order

1. **⏳** Phase 1 — daemon `Bubble.*` ([`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) Phase A)
2. **⏳** Phase 2 — `RunCommand.Request` RPC caller when `LIVE`
3. **⏳** Phase 3 — Android `Bash` + `AgentPi.Factory.register_config`

---

## LLM notes

- **🚫** Registering in-process `Bash` on Android so Agent Pi can start. That runs on the phone.
- **🚫** A long-term in-process `OLLMbwrap.Bubble.exec` on Linux desktop beside `Bubble.exec` RPC. RPC is the exec path.
- **🚫** A new RPC object (`Exec.*`, `Bash.*`, `RunCommand.*`). The wire is `Bubble.*`.
- **🚫** Putting these hunks into [`8.2.8.9`](done/RPC-8.2.8.9-DONE-android-agent-pi.md).
- **🚫** `run_as_root` / sudo over RPC ([`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md)).
- **🚫** MCP stdio session RPC (`2.10.4.15` Phase B).
- **🚫** Helper methods unless a later fence names one.
