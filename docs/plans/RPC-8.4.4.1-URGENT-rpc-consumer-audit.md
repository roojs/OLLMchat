# 8.4.4.1 — URGENT — RPC consumers: throw, then audit callers

> `docs/plans/RPC-1.0-summary.md` is **not** updated for this sub-plan until it is done and archived.

**Status:** **URGENT** **PROPOSED**

**Parent:** [`RPC-8.4.4-rpc-invoke-errors.md`](RPC-8.4.4-rpc-invoke-errors.md)

**Depends on:** [`8.4.4`](RPC-8.4.4-rpc-invoke-errors.md) Phase 1 — `Client.call` throws `GLib.Error`.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

---

## Purpose

- **🔷** `✔️` **Phase 1** — wrappers and `rpc.call` sites throw. Delete the old `response.error` / canned-`FAILED` handling. Unhandled-error warnings at callers are expected. No fences for `throws`. No new UI.
- **🔷** `⏳` **Phase 2** — numbered below. Tick one at a time. Catch vs throw per site.
- **🔷** `rpc_project_description`: blank description is OK. Catch in the wrapper. `GLib.critical`, return `""`. Parents do not throw.
- **🔷** Callers that **already throw** (tools, CLI that already `throws`) keep throwing.
- **🔷** Most other callers: `GLib.critical` and carry on (same fallback as today, but logged).
- **🔷** `File.read` `false` stays for empty path and buffer-load catch. Not RPC.
- **ℹ️** `tests/rpc` is [`RPC-8.4.4`](RPC-8.4.4-rpc-invoke-errors.md).
- **ℹ️** `libocmcp/Request.vala` `client.call` is MCP HTTP, not `OLLMrpc.Client`.

**Suggested order:** Phase 1 done → Phase 2 items **1** … in order.

---

## Phase 1 — Throw, drop dead handling

No **Remove** / **Replace with** fences. `throws GLib.Error` is the edit.

- **🔷** `✔️` Wrappers: `throws GLib.Error`. Delete `if (response.error != null)` swallows.
  - `Folder` — `rpc_project_description`, `rpc_roots`, `fetch_file`, `contains_folder`, `fetch_files`
  - `File` — `exists`, `read`, `rpc_write`, `check_changed`, `register`, `rpc_delete`, `apply_permissions`
  - `ReviewFiles` — `fetch_pending` (and `refresh` yields it)
  - `FileHistory` — `rpc_approve`, `rpc_revert`
  - `ProjectManager` — `rpc_load_projects_from_db`, `fetch_folder`, `rpc_create_project`
- **🔷** `✔️` Direct `rpc.call`: delete `throw new GLib.IOError.FAILED(response.error.message)`. Keep empty-result `FAILED` and any outer UI catch.
  - `CodebaseSearch/Request.vala`, `libochf/Model.vala` `fetch_siblings`, `HuggingFace/Request.vala`
  - `ReadFile/Summarize.vala` `load_vector_metadata` (delete `if (error) return`)
  - `examples/oc-hf.vala`, `oc-vector-index.vala`, `oc-vector-search.vala`
- **🔷** `✔️` `File.to_real` / `DeleteManager.remove`: drop canned `FAILED` on wrapper `false`. Yield and let it throw.
- **🔷** `⏳` Caller `throws` / fire-and-forget `.end`: Phase 2. Do not add `throws` up the tree in Phase 1.
- **ℹ️** Keep `if (!(yield file.read()))` for **buffer-load** `false`.

---

## Phase 2 — numbered callers

Edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

### 1. `✔️` `rpc_project_description` — critical, return `""`

- **🔷** Catch in `Folder.rpc_project_description`. Drop `throws`.
- **🔷** `GLib.critical`, return `""`. Prompt fill keeps going with a blank blurb.
- **🔷** Parents (`Skill/Runner`, `Task/Details`, `Task/Tool`) do not catch this.
- **ℹ️** `examples/oc-vector-index.vala` calls the daemon method on `Client.call` directly. Not this wrapper. Item 3.

#### `libocfiles/Folder.vala` — `rpc_project_description()`

**Why:** A missing project blurb is fine. Parents must not abort prompt fill.

**Where:** `Folder.rpc_project_description` — whole method (signature + body).

**Depends on:** none.

##### Part 1 — Drop `throws`

#### Remove
```vala
		 * @return description text, or empty string
		 * @throws GLib.Error if the RPC fails
		 */
		public async string rpc_project_description() throws GLib.Error
```

#### Replace with
```vala
		 * @return description text, or empty string
		 */
		public async string rpc_project_description()
```

##### Part 2 — Catch `rpc.call`

#### Remove
```vala
			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "RPC-Folder.rpc_project_description",
				args = OLLMrpc.args("s", this.path)
			});
			return response.msg;
```

#### Replace with
```vala
			try {
				var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
					method = "RPC-Folder.rpc_project_description",
					args = OLLMrpc.args("s", this.path)
				});
				return response.msg;
			} catch (GLib.Error e) {
				GLib.critical("project description failed %s: %s", this.path, e.message);
				return "";
			}
```

### 2. `✔️` `rpc_roots` — critical, return empty list

When starting a sandboxed MCP server, we ask the daemon for the project’s write-root folders (`rpc_roots`) so bubblewrap can bind them.

- **🔷** Catch in `Folder.rpc_roots`. Drop `throws`.
- **🔷** `GLib.critical`, return an empty `Gee.ArrayList<Folder>`. Same as the not-a-project early return.
- **🔷** `libocmcp/Client/Stdio.vala` `build_spawn_argv` does not catch this. Spawn still runs.
- **ℹ️** Empty roots means no project bind mounts. The MCP process still starts.

#### `libocfiles/Folder.vala` — `rpc_roots()`

**Why:** A missing root list must not abort MCP spawn. Parents keep going with no write binds.

**Where:** `Folder.rpc_roots` — signature and `rpc.call` body.

**Depends on:** none.

##### Part 1 — Drop `throws`

#### Remove
```vala
		 * @return Write-root folder rows (paths are realpaths)
		 * @throws GLib.Error if the RPC fails
		 */
		public async Gee.ArrayList<Folder> rpc_roots() throws GLib.Error
```

#### Replace with
```vala
		 * @return Write-root folder rows (paths are realpaths)
		 */
		public async Gee.ArrayList<Folder> rpc_roots()
```

##### Part 2 — Catch `rpc.call`

#### Remove
```vala
			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "RPC-Folder.rpc_roots",
				args = OLLMrpc.args("s", this.path)
			});

			var folders = (Gee.ArrayList<Folder>) response.result;
			foreach (var folder in folders) {
				folder.manager = this.manager;
			}
			return folders;
```

#### Replace with
```vala
			try {
				var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
					method = "RPC-Folder.rpc_roots",
					args = OLLMrpc.args("s", this.path)
				});
				var folders = (Gee.ArrayList<Folder>) response.result;
				foreach (var folder in folders) {
					folder.manager = this.manager;
				}
				return folders;
			} catch (GLib.Error e) {
				GLib.critical("project write roots failed %s: %s", this.path, e.message);
				return new Gee.ArrayList<Folder>();
			}
```

### 3. `✔️` Tools / CLI that already throw (`execute_request`)

No code. These already `throws`. RPC failure fails the tool or CLI.

- **🔷** `ReadFile/Request.vala`, `WriteFile/Request.vala` `execute_request`, `EditMode/Request.vala`
- **🔷** `CodebaseSearch/Request.vala`, `HuggingFace/Request.vala`, `libochf/Model.vala` `fetch_siblings`
- **🔷** `DeleteManager.remove`, `Folder.insert_file`, `File.to_real`
- **🔷** `TreeBase.load_file_content` (parse tools)
- **🔷** `examples/oc-hf.vala`, `oc-vector-index.vala`, `oc-vector-search.vala`
  - Hugging Face’s outer catch that shows the red error frame stays.

### 4. `⏳` `fetch_file` — restore last file, revert reload

`fetch_file` is `RPC-File.fetch` (`ollmfilesd/File.vala` `fetch()`).

**Server replies (success, no `response.error`):**

- **🔷** Hit: `result` has one `File`. Client returns that file.
- **🔷** Miss: empty `result`, `msg` is `file not found` or `project not found`. Client returns `null`.
- **🔷** `mtime_on_disk` does not throw. It logs critical and returns `0`.

**Server / transport that `Client.call` throws:**

- **🔷** Transport / timeout (`IOError`, `TIMED_OUT`).
- **🔷** Protocol (`METHOD_NOT_FOUND`, `INVALID_PARAMS`, wrong args).
- **🔷** Not “file missing”. Missing is the success miss above.

**Client `Folder.fetch_file`:** keep `throws`. Do **not** catch in the wrapper (that would turn a throw into `null`).

**Read / write / edit tools** (item 3): `null` → fake file / probe disk. Throw fails the tool. OK.

**Restore the last open file** — `ProjectManager.restore_active_state`:

- **🔷** `null`: skip opening (no saved file / not in index). No critical.
- **🔷** Throw: `GLib.critical`, skip opening. Do not treat as “no saved file”.

**Revert buffer reload** — `FileHistory.rpc_revert` after the revert RPC:

- **🔷** `null`: skip reload (not in index).
- **🔷** Throw: `GLib.critical`, skip reload. Revert RPC itself still throws (item 9).

#### `libocfiles/ProjectManager.vala` — `restore_active_state()`

**Why:** A throw is not “file missing”. Log it. Leave the editor with no restored file.

**Where:** `restore_active_state` — the `fetch_file` yield.

**Depends on:** none.

#### Remove
```vala
			var file = yield project.fetch_file(file_path);
			if (file != null) {
				this.activate_file(file);
			}
```

#### Replace with
```vala
			try {
				var file = yield project.fetch_file(file_path);
				if (file != null) {
					this.activate_file(file);
				}
			} catch (GLib.Error e) {
				GLib.critical("restore open file failed %s: %s", file_path, e.message);
			}
```

#### `libocfiles/FileHistory.vala` — `rpc_revert()` lookup

**Why:** Revert already succeeded. A lookup throw must not skip the log. Skip only the buffer reload.

**Where:** `rpc_revert` — the `fetch_file` yield when cache miss.

**Depends on:** none.

#### Remove
```vala
			if (cached == null && this.manager.active_project != null) {
				cached = yield this.manager.active_project.fetch_file(
					this.path
				);
			}
```

#### Replace with
```vala
			if (cached == null && this.manager.active_project != null) {
				try {
					cached = yield this.manager.active_project.fetch_file(
						this.path
					);
				} catch (GLib.Error e) {
					GLib.critical("revert reload lookup failed %s: %s", this.path, e.message);
					return;
				}
			}
```

### 5. `⏳` Overlay scan (`has_file` / `created` / `modified`)

When a sandboxed command finishes, `OLLMbwrap.Scan` walks the overlay (files the command created or changed). For each path it asks `FileVerification.has_file`: “is this path already in the project index?”

- **Yes** (a real file type) → treat as an update.
- **No** (`GLib.FileType.UNKNOWN`) → treat as a **new** file and call `created` (RPC write into the project).

Today, if the `fetch_file` RPC **fails**, `has_file` returns `UNKNOWN`. The scanner then thinks the file is new and may try to create it a second time.

- **🔷** That is not “file is new”. Catch, `GLib.critical`, skip that path, keep walking the overlay.
- Same for `created` / `modified` when `rpc_write` throws: log critical, next file, do not abort the whole scan.

### 6. `⏳` Task markdown links (`ValidateLink`)

When a task’s References section is checked, `ValidateLink.file` asks: is this path in the project (`fetch_file`)? If not, is it a folder (`contains_folder`)? If neither, it appends “file does not exist” for the LLM to fix.

Today a **failed RPC** takes the same path as “not in the project”, so the model is told the file is missing when we simply could not ask the daemon.

- **🔷** Catch, `GLib.critical`, do **not** add a “file does not exist” issue. Continue validating the other links.

### 7. `⏳` File dropdown / review list (`fetch_files` / `fetch_pending`)

`.begin` from the UI. Callback cannot throw.

- **🔷** RPC throw (`project not found`, transport): catch in the ready callback, `GLib.critical`, leave the list (empty or last good page).
- **🔷** Empty page (`msg == "0"`, empty `result`): not an error. Empty dropdown. Do not retry, do not treat as scan-failed.
- **🔷** Path-filter miss (path absent from `all_files`): omit that path. Not an error.
- **🚫** Empty `fetch_files` is not “scan failed”. Do not change daemon `wait_scan_idle` / `read_dir` for this.
- **ℹ️** Same catch for `fetch_pending` / `ReviewFiles.refresh`.

### 8. `⏳` Save / reload / disk-changed banner (Window)

Save buffer, reload from disk, and “file changed on disk” all `.begin` from the window. Today a failed RPC looks like success (`false` ignored, or `NO_CHANGE` so no banner).

- **🔷** Catch, `GLib.critical`, do not show a fake “no change”. Save/reload: stay on the current buffer.

### 9. `⏳` Approve / revert buttons

- **🔷** Catch, `GLib.critical`. Do **not** refresh the review list after a failed approve/revert. Re-enable the buttons so the user can retry.

### 10. `⏳` Load project list / create project

- **🔷** `AgentFactory` / `Skill/Factory` already `catch` + `GLib.warning` on load. Keep (warning → `GLib.critical` if we touch them).
- **🔷** `ollmchat-cli` and examples that already throw: keep throwing (process may exit).
- **💩** `⏳` `SettingsDialog/ProjectsPage` — `GLib.critical` and leave the list as-is unless it already throws.

### 11. `⏳` Hugging Face / vector examples / `Summarize` vectors

- **🔷** Tools and CLI examples that already throw: keep throwing.
- **🔷** `Summarize.load_vector_metadata`: `GLib.critical`, still return the AST summary without vector rows (do not fail the whole summarize).

### 12. `⏳` Activate / remove project, notification `rpc.*` (fire-and-forget `call.begin`)

These send a daemon command and ignore the reply. The ready callback cannot throw.

- **🔷** Catch, `GLib.critical`. No extra dialog. `Client.failed` may also fire.

### 13. `⏳` `WriteFile.validate` / `EditMode/Stream`

Not item 3. These do **not** already throw.

- **🔷** `WriteFile.validate()` — yields `exists` / `fetch_file` / `read`, returns an error string. No `throws`. A failed RPC is an unhandled warning, not a failed tool call.
- **🔷** `EditMode/Stream` — `process_next_change` / `finalize_and_handle_response` run from `.begin`. The callback cannot throw.

---

## LLM notes

- **🚫** Fence Phase 1 `throws` / swallow deletes.
- **🚫** `GLib.critical` then return success from `Client.call`.
- **🚫** Catch in files wrappers except Phase 2 **item 1** (`rpc_project_description`) and **item 2** (`rpc_roots`).
- **🚫** Fence 8.4.4 wire / `Client.call`.
- **🚫** Edit ollmfilesd `*Params` handlers.
- **🚫** Abort prompt fill when project description RPC fails.
- **🚫** Catch-all back to `false` / `""` / `null` with no log.
- **🚫** Add `throws` up the caller tree.
- **ℹ️** Phase 2 fences only for the numbered item being ticked.
