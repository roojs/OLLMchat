# 2.31.6 — Daemon `Sandbox-Bubble` RPC (parked draft)

**Status:** ⏳ **PARKED — do not apply.** Code proposals are complete and kept on purpose, to be mined by Phases A and B of the parent. The wire shape in here is superseded.

> **Do not update** `docs/plans/TOOLS-1.0-summary.md` **for this sub-plan.**

**Was:** `RPC-8.2.8.10.1-daemon-sandbox-bubble-rpc.md`. Moved with its parent into the `TOOLS` series.

**Parent:** [`TOOLS-2.31`](TOOLS-2.31-URGENT-bash-process-tool.md) — `bash` as a process tool

**Numbered `.6`** so `TOOLS-2.31.1` … `TOOLS-2.31.5` stay free for the parent's phases A–E.

**Depends on:**

- [`BWRAP-2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) — daemon sandbox RPC design. Phase A is the source for params and vetoes.

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

Proposed Vala follows `docs/coding-standards.md`.

---

## Purpose

- **🔷** Put the daemon side of remote `bash` on the wire: `ollmfilesd` runs the sandboxed command, the client drives it over RPC.
- **🔷** `⏳` Hold the implementation without applying it. The parent is reworking the **tool** contract first (timeout, detached processes, status / kill / stdin), and that may change what the daemon has to expose.
- **ℹ️** Everything below was written against the tree and reviewed. It is parked, not abandoned.
- **ℹ️** Read [`BWRAP-2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md) Phase A first for the full design, params, and vetoes.

---

## What the parent rework may change

- **⏳** **🔷** The parent is moving to a model where the **tool** owns a timeout (~30s), streams output, and then **returns while the process keeps running**, handing the agent a process id to manage.
- **⏳** **🔷** That needs status / kill / wait / stdin calls on a running process. This sub-plan has `rpc_run` and `stop` but **no status, no wait, and no stdin**.
- **⏳** **💩** A detached process also outlives the tool call, so the lease lifetime below (client unrefs on `finished`) is probably wrong for that model.
- **ℹ️** Re-read this section before applying anything here.

---

## Phase 1 — Daemon `Bubble.exec` (`⏳`)

### Key design (summary — `2.10.4.15` is the source)

- **🔷** `⏳` `ollmfilesd` answers `can_wrap` and the exec calls on one wire object. No second exec object.
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
- **🔷** Handler prefix is `Sandbox-Bubble`. `RPC-` stays on `RPC-Daemon` and `RPC-Live-*` only.
  - **ℹ️** Nested namespaces hyphenate (`RPC-Live-Remote` for `OLLMrpc.Live.Remote`), so this prefix carries `Sandbox-`.
  - **ℹ️** The `rpc_` suffix on `rpc_create` / `rpc_run` is unrelated and stays — it is on the wire for existing handlers too (`File.rpc_write`), and marks the sync FFI entry point that pairs with a private `async` method.
- **💩** So the proposals below use the shipping style. Decisions you may want to overrule:
  - Signatures: `rpc_create` is `sssbS`, `rpc_run` and `stop` are `t`, `can_wrap` is `""`.
  - `can_wrap` replies `msg` = `1` / `0`. `OLLMbwrap.Bubble.can_wrap()` is a bool with no `reason`, so the `{available, reason}` result in `2.10.4.15` has nothing to fill `reason` with.
  - The `finished` signal carries the exec output string. `OLLMbwrap.Bubble.exec` already embeds exit code and seccomp evidence in that string, so the 4-field result object (`output`, `exit_code`, `seccomp_network`, `seccomp_fs`) in `2.10.4.15` would need a new return type on `OLLMbwrap.Bubble`.
  - Error codes `-32001` / `-32003` / `-32004` from `2.10.4.15` are **not** in `OLLMrpc.RpcErrorCode` (`PARSE_ERROR`, `INVALID_REQUEST`, `METHOD_NOT_FOUND`, `INVALID_PARAMS`, `INTERNAL_ERROR`, `NOT_IMPLEMENTED`). Proposals use `INTERNAL_ERROR`, and a plain `msg` for “project not found” the way `Folder.rpc_roots` does.

### Exec is a live handle, not one call

- **🔷** A command can run for minutes. One request/reply would hold the call open for the whole run and return only the final string. `exec` is therefore **not** a single call: the daemon hands back a **live handle** and the client streams from it.
- **🔷** Four calls replace `exec`:
  - `Sandbox-Bubble.can_wrap` → `msg` `1` / `0`.
  - `Sandbox-Bubble.rpc_create(project_path, command, working_dir, network, allow_write)` → `retval` the **handle** (`t`, uint64). Builds the `OLLMbwrap.Bubble` and leases it. **Does not run it.**
  - `Sandbox-Bubble.rpc_run(handle)` → replies at once; output arrives on the subscribed signals.
  - `Sandbox-Bubble.stop(handle)` → `bubble.stop()`.
- **🔷** Between `rpc_create` and `rpc_run` the client subscribes on the lease with `RPC-Live-Subscribe.rpc_signal`:
  - `output` — one line per emission.
  - `finished` — final output string; the run is over.
- **🔷** Client releases with `RPC-Live-Remote.rpc_unref` once `finished` arrives.
- **🔷** **Create and run are separate on purpose.** If one call both leased and started, output emitted before the client's subscribe round-trip would be lost. Splitting them removes the race with no buffering.
- **ℹ️** This reuses shipped machinery only — leases, `Live.Subscribe`, `Live.Remote` — all covered by `tests/rpc/subscribe-test.vala`. No new streaming protocol.
- **🚫** One-shot `exec` returning the final output string.
- **🚫** A poll handle (`poll(job_id, from_line)`). Only needed if the transport had no push.

#### Transport

- **🔷** HTTPS is being retired. The phone reaches the daemon over the TLS TCP socket (`filesd.socket`, `SslListen`).
  - **ℹ️** Handover is [`RPC-1.11.3`](RPC-1.11.3-tcp-client-handover.md). `TcpListen` stays the plaintext Windows listener.
  - **ℹ️** HTTPS could not have carried this: `Transport.HttpServer` never overrides `Listen.broadcast`, and `X-rpc-sequence` forbids a second in-flight call on a session, so even `stop` could not be sent mid-run.
- **✔️** `TcpListen` overrides `broadcast` (`libocrpc/Transport/TcpListen.vala:77`) and passes `live_handles` to each accepted connection (`:66`). `SocketListen` does both too.
- **🔷** `live_handles` must be switched on for the daemon's listeners — §5. No `ollmfilesd` listener sets it today; `Live.Subscribe.rpc_signal` calls `GLib.error("Subscribe.signal requires live_handles")` when off.
- **⏳** **💩** `Live.BufferStream` is skipped for `tcp://` (`Client.vala:408`). That is the fd-passing buffer channel, Unix-socket only. Signal subscriptions travel as ordinary `Notification` writes on the same connection, so they should be unaffected — confirm on the first live run.

#### Still open

- **⏳** **💩** Timeout ownership. In-process the caller owns `timeout_src`. The handle makes this a client job: start a timer on `rpc_run`, call `stop` on expiry. Daemon-side timeout would need a second config path; not proposed.
- **⏳** **💩** Orphan cleanup. A handle outlives its request, so a client that drops mid-run leaves a live `Bubble` and a running child. `Transport.Connection` already unrefs leases on teardown, but nothing calls `bubble.stop()` — the child would survive. Needs a hook on connection close.

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

- **ℹ️** Copied from two approved sources, not written fresh:
  - Class shape, constructor, nullable `project`, `Banner.show` on failure, the `unix_mode` query block, the duplicated `created` / `modified` pair — `liboctools/FileVerification.vala`.
  - The per-path work (`get_folder_at_path` / `file_cache` / `get_file_from_active_project`, the `id < 0` fake rows, `to_real`, `change_type`, the `FileHistory` + `saveToDB` approval bookkeeping, `realize`, `invalidate_cache`) — `File.write` in `ollmfilesd/File.vala`, the current receiver of the in-app `rpc_write` call.
- **ℹ️** The `catch` itself is forced: `created` / `modified` / `removed` / `finish` on `OLLMbwrap.FileVerification` have no `throws`, so an implementation cannot propagate. Only `has_file` has `throws`.
- **🔷** **Try scope is narrow — one `try` per case, around only the throwing calls.** This is a deliberate deviation. Both source files wrap the whole switch in one blanket `try`; that shape is not copied forward.
  - Outside the `try`: the lookups, the `new Folder` / `new FileAlias` / `new File` construction, `change_type`, `saveToDB`, and the `invalidate_cache` notification. None of those throw.
  - Inside: `to_real`, `realize`, `read_link`, `load_bytes`, `FileHistory.commit`.
  - **💩** Cost of narrowing: the `Banner.show` block repeats in each `catch`, three times per method. The alternative is a flag to defer one emit, which is worse. Say the word if you would rather have the flag.
- **💩** Four substitutions, each because the in-app call has no daemon counterpart:
  - `yield new OLLMfiles.File.new_fake(…).rpc_write(…)` → the `File.write` work inline. The daemon is the write target; it cannot RPC itself.
  - The `base_type` string (`d` / `fa` / `f`) is **dropped**. It only existed to carry the file kind over the wire to `File.write`. In-process the `switch` runs straight off `GLib.FileType`, so `created` / `modified` now switch once instead of mapping to a string and switching again.
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
	 * {@link DeleteManager} — the same work ''File.rpc_write'' and
	 * ''File.rpc_delete'' do for a remote client. In-app callers use
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
		public FileVerification(Folder? project, ProjectManager manager)
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
			var unix_mode = 0U;
			try {
				var info = GLib.File.new_for_path(overlay_path).query_info(
					GLib.FileAttribute.UNIX_MODE, GLib.FileQueryInfoFlags.NONE, null);
				unix_mode = info.get_attribute_uint32(GLib.FileAttribute.UNIX_MODE) & 0777;
			} catch (GLib.Error e) {
				GLib.warning("Cannot query overlay mode (%s): %s", overlay_path, e.message);
			}
			switch (file_type) {
				case GLib.FileType.DIRECTORY:
					var folder = this.manager.get_folder_at_path(real_path);
					if (folder == null) {
						folder = new Folder(this.manager) {
							path = real_path,
							id = -1
						};
					}
					try {
						if (folder.id < 0) {
							yield folder.to_real();
						}
						yield folder.realize(unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay created folder %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not save overlay file: " + real_path
						});
					}
					break;

				case GLib.FileType.SYMBOLIC_LINK:
					var alias = this.manager.file_cache.get(real_path) as FileAlias;
					if (alias == null) {
						alias = new FileAlias(this.manager) {
							path = real_path,
							id = -1
						};
					}
					try {
						var target = GLib.FileUtils.read_link(overlay_path);
						if (alias.id < 0) {
							yield alias.to_real(target);
						}
						yield alias.realize(target, unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay created symlink %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not save overlay file: " + real_path
						});
					}
					break;

				default:
					var file = this.manager.get_file_from_active_project(real_path);
					if (file == null) {
						file = new File(this.manager) {
							path = real_path,
							id = -1
						};
					}
					var change_type = file.id < 0 ? "added" : "modified";
					try {
						if (file.id < 0) {
							yield file.to_real();
						}
						if (change_type == "modified" && this.manager.db != null) {
							file.is_need_approval = true;
							file.last_change_type = "modified";
							var file_history = new FileHistory(this.manager.db,
								file, "modified", new GLib.DateTime.now_local());
							yield file_history.commit();
							file.saveToDB(this.manager.db, null, false);
						}
						var bytes = GLib.File.new_for_path(overlay_path).load_bytes(null);
						yield file.realize((string) bytes.get_data(), unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay created file %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not save overlay file: " + real_path
						});
						return;
					}
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

		public async void modified(
			GLib.FileType file_type,
			string real_path,
			string overlay_path)
		{
			if (this.project == null) {
				return;
			}
			var unix_mode = 0U;
			try {
				var info = GLib.File.new_for_path(overlay_path).query_info(
					GLib.FileAttribute.UNIX_MODE, GLib.FileQueryInfoFlags.NONE, null);
				unix_mode = info.get_attribute_uint32(GLib.FileAttribute.UNIX_MODE) & 0777;
			} catch (GLib.Error e) {
				GLib.warning("Cannot query overlay mode (%s): %s", overlay_path, e.message);
			}
			switch (file_type) {
				case GLib.FileType.DIRECTORY:
					var folder = this.manager.get_folder_at_path(real_path);
					if (folder == null) {
						folder = new Folder(this.manager) {
							path = real_path,
							id = -1
						};
					}
					try {
						if (folder.id < 0) {
							yield folder.to_real();
						}
						yield folder.realize(unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay modified folder %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not update overlay file: " + real_path
						});
					}
					break;

				case GLib.FileType.SYMBOLIC_LINK:
					var alias = this.manager.file_cache.get(real_path) as FileAlias;
					if (alias == null) {
						alias = new FileAlias(this.manager) {
							path = real_path,
							id = -1
						};
					}
					try {
						var target = GLib.FileUtils.read_link(overlay_path);
						if (alias.id < 0) {
							yield alias.to_real(target);
						}
						yield alias.realize(target, unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay modified symlink %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not update overlay file: " + real_path
						});
					}
					break;

				default:
					var file = this.manager.get_file_from_active_project(real_path);
					if (file == null) {
						file = new File(this.manager) {
							path = real_path,
							id = -1
						};
					}
					var change_type = file.id < 0 ? "added" : "modified";
					try {
						if (file.id < 0) {
							yield file.to_real();
						}
						if (change_type == "modified" && this.manager.db != null) {
							file.is_need_approval = true;
							file.last_change_type = "modified";
							var file_history = new FileHistory(this.manager.db,
								file, "modified", new GLib.DateTime.now_local());
							yield file_history.commit();
							file.saveToDB(this.manager.db, null, false);
						}
						var bytes = GLib.File.new_for_path(overlay_path).load_bytes(null);
						yield file.realize((string) bytes.get_data(), unix_mode);
					} catch (GLib.Error e) {
						GLib.critical("overlay modified file %s: %s", real_path, e.message);
						this.manager.notification(new OLLMrpc.Notification() {
							method = "Banner.show",
							message = "Could not update overlay file: " + real_path
						});
						return;
					}
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
				yield this.manager.delete_manager.remove(filebase,
					new GLib.DateTime.now_local());
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

### 3. `libocbwrap/Bubble.vala` — `finished` signal, `command`, `working_dir`

**Why:** Two gaps for a leased bubble. First, the client learns a run ended by subscribing to a signal, and there is no completion signal — `stopped` is set **only** by `stop()` (`Bubble.vala:146-148`), so it never fires on a normal exit. Second, `rpc_create` accepts the command but `rpc_run` is a separate call, so the command and working dir have to live on the object between them.

**Where:** beside the existing `output` signal.

- **🔷** Declarations only. **`exec` is not touched** — it has six return points at its tail and none of them are edited. The daemon emits `bubble.finished(output)` after `yield bubble.exec(...)` returns (§4).
- **🔷** `command` / `working_dir` are plain properties the owner fills before calling `exec`. `exec` keeps its two parameters and its current behaviour; the properties are **not** read inside it. §4 passes them straight back in (`bubble.exec(bubble.command, bubble.working_dir)`).
  - **💩** The alternative was keeping two `Gee.HashMap`s on the handler keyed by bubble. Carrying the state on the object it belongs to is the better of the two, but it does put caller state on a library class — say if you would rather have the maps.
- **ℹ️** `finished` carries the same string `exec` returns, which already embeds the exit code and any seccomp evidence.
- **ℹ️** All three are additive for in-process callers: `RunCommand.Request` keeps passing `exec` its arguments and using the return value, and never connects `finished`.

#### Remove

```vala
		public bool stopped { get; private set; default = false; }
		public signal void output(string line);
```

#### Replace with

```vala
		public bool stopped { get; private set; default = false; }
		public signal void output(string line);

		/**
		 * Shell string for a deferred run, when the owner leases this
		 * object and starts it on a later call. Not read by
		 * {@link exec} — pass it in.
		 */
		public string command { get; set; default = ""; }

		/**
		 * Working directory for a deferred run. Same contract as
		 * {@link command}.
		 */
		public string working_dir { get; set; default = ""; }

		/**
		 * Emitted once the command has ended, with the string
		 * {@link exec} returns (exit code and seccomp evidence
		 * already embedded).
		 *
		 * For remote callers that hold this object as a live handle
		 * and cannot see the {@link exec} return value. Emitted by
		 * the owner after ''exec'' resolves, not from inside it.
		 *
		 * @param output final command output
		 */
		public signal void finished(string output);
```

### 4. `ollmfilesd/Sandbox/Bubble.vala` — `Sandbox-Bubble` handlers

**Why:** `2.10.4.15` wants RPC glue only — no `Exec.vala`, no `Sandbox/*` copy under `ollmfilesd/`. This class resolves the project, builds `write_roots`, and hands off to `OLLMbwrap.Bubble`.

**Where:** New file, new `ollmfilesd/Sandbox/` directory. Handler shape copies `ollmfilesd/File.vala`: typed FFI entry point, then a private `async` method that re-reads `request.args`.

**Depends on:** §1, §2 and §3.

- **🔷** `rpc_create` leases and replies; `rpc_run` starts the child. Two calls, so the client can subscribe on the lease before any `output` is emitted.
- **ℹ️** The private `async run` is not an optional helper. The FFI entry point cannot `yield`, so every async daemon handler is split this way (`File.rpc_write` → `File.write`, `Codebase.rpc_search` → `Codebase.search`). This plan names it.
- **ℹ️** `rpc_create` is **not** split — it does no `yield`, so it stays a plain handler like `Folder.rpc_roots`.
- **🔷** Handlers test `request.args` directly and return first — no block of arg locals at the top. `File.write` and `Codebase.search` both open with one `var` per argument; that shape is **not** copied forward, because those locals are single-use aliases of `request.args.get(N).get_*()` and `temporary-variables` forbids them. Only `project`, `bubble` and `output` remain, and each is used more than once or holds built-up state.
- **🔷** The handle is `request.connection.export(bubble)` — the same lease table `Live.Subscribe` and `Live.Remote` read. `rpc_run` and `stop` resolve it back with `request.connection.leases.get((int) handle)`.
- **💩** `rpc_run` replies `msg = "ok"` immediately and does **not** wait for the command. The result arrives on `finished`. Replying after the run would reintroduce the blocking call this design removes.
- **ℹ️** The guards are copied from `execute_tool_async` in `liboctools/RunCommand/Request.vala` — empty-command rejection first, then `can_wrap`, then the project, with `project` nullable.
- **🔷** `Bubble` is built with object-initializer syntax, not the post-construction assignments `execute_tool_async` uses. `project_path`, `allow_network`, `write_tokens` and `write_roots` are all plain `get; set;` auto-properties on `OLLMbwrap.Bubble` — none is derived or `construct`-only — so the `// due to vala async ctor quirk` comment does not apply here and is dropped along with the separate assignment lines.
  - **💩** `write_roots` cannot go in the initializer because it is populated conditionally. It defaults to `new Gee.HashMap<string, string>()` per instance, so the one entry is set on `bubble.write_roots` after construction. This also removes the `write_roots` local and the `verification` local.
- **ℹ️** Empty command replies `INVALID_PARAMS`, not `INTERNAL_ERROR`. In-process that path is `throw new GLib.IOError.INVALID_ARGUMENT("Command cannot be empty")`; a bad argument is the closest wire code.
- **💩** Everything `execute_tool_async` does **after** `bubble.exec` stays with the caller: the `"No output received from command"` substitution, the timeout note, the `// LLM received last 50 of N lines` footer, the spill path, and the `Exit code:` footer. All of it reads `this.timed_out` / `this.stopped` / `this.output_lines` / `this.spill_path`, which only the caller has. The daemon replies with the raw `exec` string.
- **💩** `working_dir` arrives already normalized — `normalize_working_dir()` runs caller-side in the parent's Phase 2 and is not repeated here.
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
	 * Server ''Sandbox-Bubble.*'' wire handlers — sandbox
	 * availability and sandboxed command execution on the daemon.
	 *
	 * {@link OLLMbwrap.Bubble} owns the bubblewrap spawn, overlay, and
	 * seccomp stack. This class is RPC glue: it resolves the project,
	 * builds the writable roots, and leases the bubble to the caller.
	 * Overlay writes land through {@link OLLMfilesd.FileVerification}.
	 * Registered once in {@link OllmfilesdApplication}. Arguments arrive
	 * on {@link OLLMrpc.Request.args}.
	 *
	 * A run is three calls, because a command may take minutes and a
	 * single reply would block the caller for all of it. ''rpc_create''
	 * leases a bubble, the caller subscribes to ''output'' and
	 * ''finished'' on that lease, then ''rpc_run'' starts the child.
	 * Subscribing between the two is what stops early output being
	 * emitted before anyone is listening.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMfilesd.Sandbox.Bubble.rpc_register();
	 * OLLMrpc.Request.register("Sandbox-Bubble",
	 *     new OLLMfilesd.Sandbox.Bubble(project_manager));
	 * // client side, in order:
	 * //   Sandbox-Bubble.rpc_create -> handle
	 * //   RPC-Live-Subscribe.rpc_signal lease_id=handle "output"
	 * //   RPC-Live-Subscribe.rpc_signal lease_id=handle "finished"
	 * //   Sandbox-Bubble.rpc_run handle
	 * //   RPC-Live-Remote.rpc_unref lease_id=handle
	 * }}}
	 */
	public class Bubble : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"Sandbox-Bubble", typeof(Bubble),
				"can_wrap", "",
				"rpc_create", "sssbS",
				"rpc_run", "t",
				"stop", "t"
			);
		}

		public ProjectManager manager { get; construct; }

		public Bubble(ProjectManager manager)
		{
			GLib.Object(manager: manager);
		}

		/**
		 * ''Sandbox-Bubble.can_wrap'' — whether bubblewrap is
		 * usable on this daemon host.
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
		 * ''Sandbox-Bubble.rpc_create'' — lease a sandbox for one
		 * command. Does not start it.
		 *
		 * Reply ''retval'' is the connection-local handle. Subscribe to
		 * ''output'' and ''finished'' on that lease
		 * ({@link OLLMrpc.Live.Subscribe}), then call {@link rpc_run}.
		 *
		 * @param request inbound RPC
		 * @param project_path project root, or empty for no-project mode
		 * @param command ''sh -c'' shell string
		 * @param working_dir absolute path, or empty for the first root
		 * @param network true leaves the network namespace shared
		 * @param allow_write ''no'' / ''project'' / absolute roots
		 */
		public void rpc_create(
			OLLMrpc.Request request,
			string project_path, string command, string working_dir,
			bool network, string[] allow_write
		) {
			if (command == "") {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INVALID_PARAMS,
						"Command cannot be empty"
					)
				});
				return;
			}

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

			var project = this.manager.project_root(project_path);
			if (project_path != "" && project == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					msg = "project not found"
				});
				return;
			}

			var bubble = new OLLMbwrap.Bubble(
				new FileVerification(project, this.manager)) {
				project_path = project_path,
				allow_network = network,
				write_tokens = allow_write,
				command = command,
				working_dir = working_dir
			};
			if (project != null) {
				bubble.write_roots.set(project.path, project.path);
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("t", request.connection.export(bubble))
			});
		}

		/**
		 * ''Sandbox-Bubble.rpc_run'' — start the leased command.
		 *
		 * Replies ''ok'' at once. Output arrives on the ''output''
		 * signal and the result on ''finished''; nothing waits for the
		 * child here.
		 *
		 * @param request inbound RPC
		 * @param handle lease from {@link rpc_create}
		 */
		public void rpc_run(OLLMrpc.Request request, uint64 handle)
		{
			this.run.begin(request, (obj, res) => {
				this.run.end(res);
			});
		}

		/**
		 * Run the leased bubble and emit ''finished'' when it ends.
		 *
		 * The ''finished'' string is what {@link OLLMbwrap.Bubble.exec}
		 * returns, so it already carries the exit code and any seccomp
		 * evidence. The empty-output text, timeout note and truncation
		 * footer stay with the caller in
		 * {@link OLLMtools.RunCommand.Request}.
		 *
		 * @param request inbound RPC
		 */
		private async void run(OLLMrpc.Request request)
		{
			var bubble = request.connection.leases.get(
				(int) request.args.get(0).get_uint64()) as OLLMbwrap.Bubble;
			if (bubble == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INVALID_PARAMS,
						"unknown sandbox handle"
					)
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = "ok"
			});

			var output = "";
			try {
				output = yield bubble.exec(bubble.command, bubble.working_dir);
			} catch (GLib.Error e) {
				output = "ERROR: " + e.message;
			}
			bubble.finished(output);
		}

		/**
		 * ''Sandbox-Bubble.stop'' — kill the leased command.
		 *
		 * ''finished'' still fires from {@link run} once
		 * {@link OLLMbwrap.Bubble.exec} unwinds.
		 *
		 * @param request inbound RPC
		 * @param handle lease from {@link rpc_create}
		 */
		public void stop(OLLMrpc.Request request, uint64 handle)
		{
			var bubble = request.connection.leases.get(
				(int) handle) as OLLMbwrap.Bubble;
			if (bubble == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INVALID_PARAMS,
						"unknown sandbox handle"
					)
				});
				return;
			}
			bubble.stop();
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				msg = "ok"
			});
		}
	}
}
```

### 5. `ollmfilesd/Application.vala` — register `Sandbox-Bubble`, enable `live_handles`

**Why:** `add_class` fills the method table; `register` binds the handler instance. Both are needed before the first request arrives. `live_handles` is what makes the lease usable — `Live.Subscribe.rpc_signal` calls `GLib.error("Subscribe.signal requires live_handles")` when it is off, and no `ollmfilesd` listener sets it today.

**Where:** The `rpc_register()` run, the `OLLMrpc.Request.register(...)` block, and both listener constructions in daemon startup.

**Depends on:** §4.

- **🔷** `live_handles = true` on both the TCP and the Unix listener. The TCP one is what the phone uses; the Unix one is what the T3 harness and the desktop use, and the same subscribe path has to work there to be testable.
- **💩** This is daemon-wide, not scoped to this feature — it turns on leases and signal subscription for every client of the daemon. It is the documented prerequisite (`docs/rpc-registration.md`, *Live prefixes*), not a workaround, but flagging it because the blast radius is larger than this plan.
- **🚫** Enabling it on the `Stdio` / `--interactive` listener. That path has no `Transport.Connection` fan-out.

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
			OLLMrpc.Request.register("Codebase",  new Codebase(this.project_manager, this.config));
```

#### Replace with

```vala
			OLLMrpc.Request.register("Codebase",  new Codebase(this.project_manager, this.config));
			OLLMrpc.Request.register("Sandbox-Bubble",
				new Sandbox.Bubble(this.project_manager));
```

#### Remove

```vala
				this.listen = new OLLMrpc.Transport.TcpListen(
					opt_tcp_host,
					(uint16) opt_tcp_port
				);
```

#### Replace with

```vala
				this.listen = new OLLMrpc.Transport.TcpListen(
					opt_tcp_host,
					(uint16) opt_tcp_port
				) {
					live_handles = true
				};
```

#### Remove

```vala
				this.listen = new OLLMrpc.Transport.SocketListen(
					this.socket_path
				);
```

#### Replace with

```vala
				this.listen = new OLLMrpc.Transport.SocketListen(
					this.socket_path
				) {
					live_handles = true
				};
```

### Testing Phase 1

- **🔷** `⏳` `Sandbox-Bubble.*` is the primary way to test this. Exercise it before any caller change.
- **⏳** **🔷** The T3 harness cannot be an `oc-rpc-script` `.script.in` fixture. Those are one-way JSON lines; this needs a lease returned by one call and fed into the next, plus inbound signal notifications. It has to be a Vala test over a real socket — model it on `tests/rpc/subscribe-test.vala`, which already does export → `rpc_signal` → assert notifications → `rpc_unref`.
- **💩** `⏳` Sequence to assert: `can_wrap` → `rpc_create` returns a non-zero handle → `rpc_signal` on `output` and `finished` → `rpc_run` replies `ok` **before** the command ends → `output` notifications arrive while it runs → `finished` carries the exit code → `rpc_unref`.
- **💩** `⏳` Cover `stop` separately with a long-running command: `stop` replies `ok`, and `finished` still fires with `Command stopped by user.` in the string.
- **💩** `⏳` Smoke the overlay path too, not just exit codes: a command that creates, edits, and deletes a project file should leave the index and the live tree correct through §2.

---

## LLM notes

- **🚫** Applying any of this before the parent's tool design is settled.
- **🚫** A new RPC object (`Exec.*`, `Bash.*`, `RunCommand.*`). The wire is `Sandbox-Bubble.*`.
- **🚫** `run_as_root` / sudo over RPC ([`2.10.4.15`](BWRAP-2.10.4.15-DEFERRED-execution-rpc-sandbox.md)).
- **🚫** MCP stdio session RPC (`2.10.4.15` Phase B).
- **🚫** Helper methods unless a fence above names one.
