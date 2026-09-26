# 4.2.3.5.3 — ReviewBar part rows and Approvals cleanup

**Status:** **⏳** proposed

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md)

**Depends on:**

- [`CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md`](CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md) — **✔️** editor hosts **`ReviewBar`**; live **`ReviewFiles`** queue. Bulk accept / reject are in-memory stubs.
- [`CODER-4.2.3-URGENT-source-view-diff.md`](CODER-4.2.3-URGENT-source-view-diff.md) — **`file_diff_part`**, Flow A–F

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 Phase 1 saves the decision and changes the file. Phase 2 paints the bar and the editor.
- 🔷 A pending hunk has no saved row. Accept leaves the file alone. Reject undoes that hunk. Reset of a reject puts the hunk back. Reset of an accept does not change the file.

---

## Phase 1 — Daemon and saved rows

A part row is the saved Accept or Reject for one hunk (`file_diff_part`). The model saving the file does not create rows.

### No row until you decide

- 🔷 ⏳ A hunk stays pending until you Accept or Reject it.
- 🔷 ⏳ The first Accept or Reject of that hunk creates its row.
- 🔷 ⏳ When every hunk in this batch has a row, the batch is marked reviewed (`file_history.reviewed`).

### What the call does to the file

- 🔷 ⏳ Accept: the project file stays as it is.
- 🔷 ⏳ Reject: that hunk is undone in the project file.
- 🔷 ⏳ Reset of an accept: the row is deleted. The project file does not change.
- 🔷 ⏳ Reset of a reject: the hunk is written back into the project file, then the row is deleted.
- ℹ️ An older note said unapprove never writes the file. That is only true for an accept.

### Hunk text file

- 🔷 The hunk text is a file, not a column. Same cache area as the version backups.
- 🔷 Version backup: `~/.cache/ollmchat/edited/{date}-{history id}-{filename}`.
- 🔷 Hunk file, already named by `FileDiffPart.path`: `~/.cache/ollmchat/edited/parts/{history id}-{part id}-{part index}-{filename}.patch`.
- 🔷 ⏳ The first Accept or Reject writes that file. Reset deletes it.
- 🔷 The file is the project text for this batch, the same string `Differ` takes beside the backup. `Differ` returns the `Patch` list. `PatchApplier` applies that list.
- 🚫 Parsing that file into line arrays, or copying a `Patch` onto another object. `FileDiffPart` is the saved row.

### The call

- 🔷 Accept, reject, and reset are one call. The argument is `action_state`, a number.
- 🔷 `RPC-` is only for internal calls, such as `RPC-Daemon.hello`. `FileDiffPart` is the row, not a call target.
- 🔷 Hyphens join the namespace and class. The dot is only the method separator.
- 🔷 No path argument. `history_id` is the batch, and that row already has the path.
- ℹ️ Not the filebase id. One file can have several history rows. The call picks the batch.
- 💩 Wire name used by the fences at the end of this phase:

```
OLLMfilesd-FileHistory.decide(history_id, part_index, action_state)

action_state:
  1     accept — save the row, write the hunk file, leave the project file alone
 -1     reject — save the row, write the hunk file, undo that hunk in the project file
  0     reset  — delete the row and the hunk file
                 if the row was a reject, put the hunk back in the project file first
```

### A later edit

- 🔷 A second model edit, or you editing the file, becomes the active file and is versioned like any other write.
- 🔷 ⏳ The next review runs `Differ` on the active file and the saved project text.
- 🔷 A hunk matches on its text, not its line number. If it only moves, the accept or reject still stands.
- 🔷 That decision stays until the whole file is approved.
- 🔷 Anything that does not match is pending.

### Accept all files

- 🔷 No separate undo call. Looking back at approved batches is file history's job.
- 🔷 Fine for now. Git already covers uncommitted work in the tree.
- 🔷 ⏳ Accept-all uses this same `decide` call once per pending hunk. It does not get its own method.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

### 1. `ollmfilesd/Diff/*.vala` — symlink `OLLMfiles.Diff` into the daemon

**Why:** `part_index` is an index into `Differ.patches`. The daemon cannot link `libocfiles` (`ollmfilesd/meson.build` bans `--pkg=ocfiles`). `Copyable.vala` is already a symlink of an `OLLMfiles` source into this binary.

**Where:** new symlinks under `ollmfilesd/Diff/`, then the `ollmfilesd_src` list in `ollmfilesd/meson.build` after `'FileDiffPart.vala',`.

**Depends on:** none.

- 💩 These three symlinks. Same algorithm as the editor. Not a second diff.

#### Add — create the symlinks from the repo root

`mkdir` and `ln -s`. Targets match `ollmfilesd/Copyable.vala` (a symlink, not a copy).

```sh
mkdir -p ollmfilesd/Diff
ln -s ../../libocfiles/Diff/Patch.vala ollmfilesd/Diff/Patch.vala
ln -s ../../libocfiles/Diff/PatchApplier.vala ollmfilesd/Diff/PatchApplier.vala
ln -s ../../libocfiles/Diff/Differ.vala ollmfilesd/Diff/Differ.vala
```

#### Add — `ollmfilesd/meson.build` `ollmfilesd_src`, after `'FileDiffPart.vala',`

List the symlinked sources so `decide` can construct `OLLMfiles.Diff.Differ`.

```meson
  'Diff/Patch.vala',
  'Diff/PatchApplier.vala',
  'Diff/Differ.vala',
```

### 2. `ollmfilesd/FileHistory.vala` — `rpc_register`: second wire prefix

**Why:** The call is `OLLMfilesd-FileHistory.decide`. `RPC-FileHistory` stays the prefix for `rpc_approve` and `rpc_revert`.

**Where:** `rpc_register()`, after the existing `add_class` for `RPC-FileHistory`.

**Depends on:** none.

#### Add — second `add_class` inside `rpc_register()`, after the `RPC-FileHistory` call

Register `decide` on `OLLMfilesd-FileHistory`. Signature `xii` is `history_id`, `part_index`, `action_state`.

```vala
			OLLMrpc.Request.add_class(
				"OLLMfilesd-FileHistory", typeof(FileHistory),
				"decide", "xii"
			);
```

### 3. `ollmfilesd/Application.vala` — one handler, two prefixes

**Why:** Dispatch looks up the prefix on the registered instance. Approve and `decide` share the `for_rpc` object.

**Where:** `Application` startup, the `OLLMrpc.Request.register("RPC-FileHistory", …)` call.

**Depends on:** §2 (the `add_class` must run from `FileHistory.for_rpc` before `register`).

#### Remove

```vala
			OLLMrpc.Request.register("RPC-FileHistory", 
				new FileHistory.for_rpc(this.project_manager));
```

#### Replace with

```vala
			var history_rpc = new FileHistory.for_rpc(this.project_manager);
			OLLMrpc.Request.register("RPC-FileHistory", history_rpc);
			OLLMrpc.Request.register("OLLMfilesd-FileHistory", history_rpc);
```

### 5. `ollmfilesd/FileHistory.vala` — `decide`

**Why:** One call saves or deletes the `file_diff_part` row and the hunk file. Accept does not write the project file. Reject undoes that hunk. Reset of a reject writes it back, then drops the row.

**Where:** `FileHistory`, immediately above `approve()`.

**Depends on:** §1 (`Differ`, `PatchApplier`), §2 (the method is dispatched).

- 🔷 `decide(history_id, part_index, action_state)`. The history row has the path.
- 🔷 `decide` checks the arguments, the history row, the file, and any saved part, then creates the buffer. That work does not yield.
- 🔷 `load_texts` reads the buffer, the backup, and any saved project text. `decide` starts it.
- 🔷 `save_part` runs `Differ`, writes the row and the hunk file, and does not yield. `load_texts` calls it.
- 🔷 `write_kept` applies the kept patches and writes the buffer. `save_part` starts it. The reply is sent from there.
- ℹ️ None of those three is a second wire call.
- 🔷 The project file is `ProjectManager.get_file_from_active_project(history.path)`. Read it with `buffer.read_async`. Write it with `buffer.write`.
- ℹ️ The backup and the hunk file are cache files, not project files.
- ℹ️ The batch diff is `Differ` on the backup and the saved project text. `part_index` is an index into `differ.patches`.
- ℹ️ Closing the batch:
  - Part count equals that patch count → `reviewed = 1`
  - `since_id` is poked the same way as `approve`
  - `is_need_approval` clears only when no other open row remains for the path
  - `last_change_type` clears in that same case, matching `approve`
- ℹ️ Reset sets `reviewed = 0`. `is_need_approval` stays on while any open row remains.

#### Add — `decide`, `load_texts`, `save_part`, and `write_kept` above `public void approve`

`decide` stops before any yield. `load_texts` does the reads. `save_part` writes the row. `write_kept` writes the project file and replies.

```vala
		/**
		 * ''OLLMfilesd-FileHistory.decide'' — save or clear one hunk row.
		 *
		 * Checks the call, then starts ''load_texts''. The history row
		 * has the path.
		 *
		 * @param request inbound RPC
		 * @param history_id file_history id
		 * @param part_index hunk index in that batch
		 * @param action_state 1 accept, -1 reject, 0 reset
		 */
		public void decide(OLLMrpc.Request request, int64 history_id, int part_index, int action_state)
		{
			if (action_state > 1 || action_state < -1) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"action_state must be 1, -1, or 0"
					)
				});
				return;
			}
			if (part_index < 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"part_index out of range"
					)
				});
				return;
			}
			var rows = new Gee.ArrayList<FileHistory>();
			FileHistory.query(this.rpc_manager.db).select(
				"WHERE id = %lld".printf(history_id),
				rows
			);
			if (rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"history row not found"
					)
				});
				return;
			}
			var history = rows.get(0);
			var file = this.rpc_manager.get_file_from_active_project(history.path);
			if (file == null) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"file not found"
					)
				});
				return;
			}
			var parts = new Gee.ArrayList<FileDiffPart>();
			FileDiffPart.query(this.rpc_manager.db).select(
				"WHERE file_history_id = %lld ORDER BY part_index".printf(history.id),
				parts
			);
			var existing_at = -1;
			for (var i = 0; i < parts.size; i++) {
				if (parts.get(i).part_index != part_index) {
					continue;
				}
				existing_at = i;
				break;
			}
			if ((action_state == 1 || action_state == -1) && existing_at >= 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"hunk already decided"
					)
				});
				return;
			}
			if (action_state == 0 && existing_at < 0) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"hunk has no row"
					)
				});
				return;
			}
			file.manager.buffer_provider.create_buffer(file);
			this.load_texts.begin(
				request, history, file, parts, existing_at, part_index, action_state,
				(obj, res) => {
					this.load_texts.end(res);
				});
		}

		/**
		 * Read the project buffer, the backup, and any saved project text.
		 *
		 * Then calls ''save_part''. Not a wire call.
		 *
		 * @param request inbound RPC
		 * @param history batch row
		 * @param file project file, buffer already created
		 * @param parts saved rows for this batch
		 * @param existing_at index of this hunk in ''parts'', or -1
		 * @param part_index hunk index in that batch
		 * @param action_state 1 accept, -1 reject, 0 reset
		 */
		private async void load_texts(
			OLLMrpc.Request request,
			FileHistory history,
			File file,
			Gee.ArrayList<FileDiffPart> parts,
			int existing_at,
			int part_index,
			int action_state
		) {
			var agent_text = "";
			try {
				agent_text = yield file.buffer.read_async();
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
			var backup_text = "";
			if (history.backup_path != "") {
				var backup_bytes = new uint8[0];
				var backup_etag = "";
				try {
					yield GLib.File.new_for_path(history.backup_path).load_contents_async(
						null, out backup_bytes, out backup_etag);
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
				backup_text = (string) backup_bytes;
			}
			foreach (var part in parts) {
				if (!GLib.FileUtils.test(part.path(history), GLib.FileTest.EXISTS)) {
					continue;
				}
				var agent_bytes = new uint8[0];
				var agent_etag = "";
				try {
					yield GLib.File.new_for_path(part.path(history)).load_contents_async(
						null, out agent_bytes, out agent_etag);
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
				agent_text = (string) agent_bytes;
				break;
			}
			this.save_part(request, history, file, parts, existing_at, part_index, action_state,
				backup_text, agent_text);
		}

		/**
		 * Diff the batch, then write the part row and the hunk file.
		 *
		 * Starts ''write_kept'' when the row write succeeds. Not a wire call.
		 *
		 * @param request inbound RPC
		 * @param history batch row
		 * @param file project file
		 * @param parts saved rows for this batch
		 * @param existing_at index of this hunk in ''parts'', or -1
		 * @param part_index hunk index in that batch
		 * @param action_state 1 accept, -1 reject, 0 reset
		 * @param backup_text backup text
		 * @param agent_text project text for this batch
		 */
		private void save_part(
			OLLMrpc.Request request,
			FileHistory history,
			File file,
			Gee.ArrayList<FileDiffPart> parts,
			int existing_at,
			int part_index,
			int action_state,
			string backup_text,
			string agent_text
		) {
			var differ = new OLLMfiles.Diff.Differ(backup_text, agent_text);
			differ.diff();
			if (action_state != 0 && part_index >= differ.patches.size) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"part_index out of range"
					)
				});
				return;
			}
			var new_id = (int64) 0;
			var new_path = "";
			if (action_state == 1 || action_state == -1) {
				var part = new FileDiffPart();
				part.file_history_id = history.id;
				part.part_index = part_index;
				part.accepted = action_state == 1 ? 1 : 0;
				part.decided_at = new GLib.DateTime.now_local().to_unix();
				part.id = FileDiffPart.query(this.rpc_manager.db).insert(part);
				new_id = part.id;
				new_path = part.path(history);
				var parts_dir = GLib.Path.get_dirname(new_path);
				if (!GLib.FileUtils.test(parts_dir, GLib.FileTest.EXISTS)) {
					try {
						GLib.File.new_for_path(parts_dir).make_directory_with_parents(null);
					} catch (GLib.Error e) {
						FileDiffPart.query(this.rpc_manager.db).deleteId(new_id);
						request.reply(new OLLMrpc.Response() {
							id = request.id,
							error = new OLLMrpc.Error(
								OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
								e.message
							)
						});
						return;
					}
				}
				try {
					GLib.FileUtils.set_contents(new_path, agent_text);
				} catch (GLib.Error e) {
					FileDiffPart.query(this.rpc_manager.db).deleteId(new_id);
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
							e.message
						)
					});
					return;
				}
			}
			this.write_kept.begin(
				request, history, file, parts, existing_at, part_index, action_state,
				differ, backup_text, new_id, new_path,
				(obj, res) => {
					this.write_kept.end(res);
				});
		}

		/**
		 * Apply the kept patches, write the project file, and reply.
		 *
		 * Accept leaves the project file alone. Not a wire call.
		 *
		 * @param request inbound RPC
		 * @param history batch row
		 * @param file project file
		 * @param parts saved rows for this batch, without a row just inserted
		 * @param existing_at index of this hunk in ''parts'', or -1
		 * @param part_index hunk index in that batch
		 * @param action_state 1 accept, -1 reject, 0 reset
		 * @param differ batch diff
		 * @param backup_text backup text
		 * @param new_id row just inserted, or 0
		 * @param new_path hunk file just written, or empty
		 */
		private async void write_kept(
			OLLMrpc.Request request,
			FileHistory history,
			File file,
			Gee.ArrayList<FileDiffPart> parts,
			int existing_at,
			int part_index,
			int action_state,
			OLLMfiles.Diff.Differ differ,
			string backup_text,
			int64 new_id,
			string new_path
		) {
			if (action_state == -1 || (action_state == 0 && parts.get(existing_at).accepted == 0)) {
				var keep = new Gee.ArrayList<OLLMfiles.Diff.Patch>();
				for (var i = 0; i < differ.patches.size; i++) {
					if (i == part_index && action_state == -1) {
						continue;
					}
					var skipped = false;
					foreach (var part in parts) {
						if (part.part_index != i) {
							continue;
						}
						if (part.accepted != 0) {
							continue;
						}
						if (action_state == 0 && part.part_index == part_index) {
							continue;
						}
						skipped = true;
						break;
					}
					if (skipped) {
						continue;
					}
					keep.add(differ.patches.get(i));
				}
				var next_text = "";
				try {
					next_text = new OLLMfiles.Diff.PatchApplier().apply(keep, backup_text);
				} catch (GLib.Error e) {
					if (action_state != 0) {
						FileDiffPart.query(this.rpc_manager.db).deleteId(new_id);
						if (GLib.FileUtils.test(new_path, GLib.FileTest.EXISTS)) {
							GLib.FileUtils.unlink(new_path);
						}
					}
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
							e.message
						)
					});
					return;
				}
				try {
					yield file.buffer.write(next_text);
				} catch (GLib.Error e) {
					if (action_state != 0) {
						FileDiffPart.query(this.rpc_manager.db).deleteId(new_id);
						if (GLib.FileUtils.test(new_path, GLib.FileTest.EXISTS)) {
							GLib.FileUtils.unlink(new_path);
						}
					}
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						error = new OLLMrpc.Error(
							OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
							e.message
						)
					});
					return;
				}
			}
			if (action_state == 0) {
				if (GLib.FileUtils.test(
					parts.get(existing_at).path(history), GLib.FileTest.EXISTS)) {
					GLib.FileUtils.unlink(parts.get(existing_at).path(history));
				}
				FileDiffPart.query(this.rpc_manager.db).deleteId(
					parts.get(existing_at).id);
			}
			var after = new Gee.ArrayList<FileDiffPart>();
			FileDiffPart.query(this.rpc_manager.db).select(
				"WHERE file_history_id = %lld".printf(history.id),
				after
			);
			history.reviewed = after.size == differ.patches.size ? 1 : 0;
			var max_stmt = FileHistory.query(this.rpc_manager.db).selectPrepare(
				"SELECT MAX(id) FROM file_history"
			);
			var max_ids = FileHistory.query(this.rpc_manager.db).fetchAllInt64(max_stmt);
			history.since_id = (max_ids.size > 0 ? max_ids.get(0) : (int64) 0) + 1;
			FileHistory.query(this.rpc_manager.db).updateById(history);
			var open_rows = new Gee.ArrayList<FileHistory>();
			FileHistory.query(this.rpc_manager.db).select(
				"WHERE path = '" + history.path.replace("'", "''") + "' AND reviewed = 0",
				open_rows
			);
			file.is_need_approval = open_rows.size > 0;
			if (!file.is_need_approval) {
				file.last_change_type = "";
			}
			file.saveToDB(this.rpc_manager.db, null, false);
			var row = new File(this.rpc_manager);
			row.copy_from(file, {
				"manager",
				"buffer",
				"parent"
			});
			request.reply(new OLLMrpc.Response() {
				id = request.id,
				retval = OLLMrpc.val("o", row),
				msg = "ok"
			});
		}
```

### 6. `libocfiles/FileHistory.vala` — `decide`: client call

**Why:** The bar (Phase 2) needs a client method for the same wire call. This method does not reload the editor.

**Where:** `OLLMfiles.FileHistory`, after `rpc_approve()`, before `rpc_revert()`.

**Depends on:** §2 and §3 (the daemon prefix must be registered).

- ℹ️ After reject, and after reset of a reject, the caller runs `File.read`. Accept does not change the project file.

#### Add — `decide` after `rpc_approve`

Send `OLLMfilesd-FileHistory.decide` with this row's id.

```vala
		/**
		 * ''OLLMfilesd-FileHistory.decide'' — one hunk accept, reject, or reset.
		 *
		 * Does not reload the editor. After reject, and after reset of a
		 * reject, the caller runs {@link File.read}.
		 *
		 * @param part_index hunk index in this batch
		 * @param action_state 1 accept, -1 reject, 0 reset
		 * @throws GLib.Error if the RPC fails
		 */
		public async void decide(int part_index, int action_state) throws GLib.Error
		{
			yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "OLLMfilesd-FileHistory.decide",
				args = OLLMrpc.args("xii", this.id, part_index, action_state)
			});
		}
```

---

## Phase 2 — Review bar and editor

Depends on Phase 1. The bar calls `decide`. It does not write the file itself.

### Bands

- 🔷 ⏳ Accept turns the band light blue and moves to the next hunk.
- 🔷 ⏳ Reject turns the band light grey and moves to the next hunk.
- 🔷 ⏳ Reset sends the band back to pending red or green.
- 🔷 ⏳ Click a decided band to scroll to that hunk. Reset is the existing bar button.
- ✅ Shades in `resources/style.css` are approved until you change them. Source lines: `.oc-diff-add` `rgb(239, 252, 239)`, `.oc-diff-remove` `rgb(252, 239, 239)`. Active source and active bar: `.oc-diff-add-active` `rgb(191, 242, 191)`, `.oc-diff-remove-active` `rgb(242, 191, 191)`. Other bar bands: `.oc-diff-add-band` `rgb(215, 247, 215)`, `.oc-diff-remove-band` `rgb(247, 215, 215)`. Accepted bar: `.oc-diff-accepted` `rgb(191, 191, 242)`. Rejected bar: `.oc-diff-rejected` `rgb(221, 221, 221)`.

### After accept, in the editor

The colour on a decided hunk is the bar band, not a wash on the source text. The band does not draw line numbers. Clicking it scrolls the editor (`navigate_to_line`). The editor gutter is where the line numbers are.

- 🔷 ⏳ Red (removed) lines leave the view.
- 🔷 ⏳ Green highlighting comes off the added lines.
- 🔷 ⏳ Those lines look like normal source.
- ℹ️ Reject does not yet say how the editor text changes.

### Which hunk is active

- 🔷 ⏳ The active hunk uses the deeper red and green. `ReviewBar` owns the bar bands.
- 🔷 ⏳ Click a red or green hunk to make it the active review.
- 🔷 ⏳ Click white space and there is no active hunk. Accept and Reject hide until a hunk is selected again.
- 🚫 Accept / Reject buttons drawn inside the green or red area.
- 🔷 ⏳ A tap on the editor scroll view, such as dismissing a menu, belongs to the scroll view, not `ReviewBar`.
- ℹ️ You can scroll the source by hand. Accept and Reject still move to the next hunk. That already works on the bar.

### Header Approvals

The footer already lists the pending files ([`4.2.3.5.2`](CODER-4.2.3.5.2-source-view-diff-approval-phase-b.md)). The header list goes away once the footer menu really saves rows.

- 🔷 ⏳ Remove the header changed-files popover.
- 🔷 ⏳ Whole-file Approve and Reject move off that header. They are not a second way to open the diff.
- 🔷 ⏳ `show_pending_diff` is the only way to open a pending diff.
- 🔷 ⏳ Whole-file reject still restores the full backup. It stays on the header or the bulk menu, not on a band click.
- 🔷 ⏳ The accept-all menu item calls Phase 1 `decide` for each pending hunk. No undo button on the bar.

---

## LLM notes

- 🚫 Rewrite disk on **accept**, or on unapprove of an accept.
- 🔷 Unapprove of a **reject** does write disk: put that hunk back on **V_disk**.
- 🚫 Approve / unapprove aliased to GtkSource undo/redo.
- 🚫 Match carried hunks inside `OLLMfiles.Diff`. Matching is by hunk text when the next batch is reviewed.
- 🚫 Accept all files as primary header button.
- 🚫 Keep header changed-files popover after footer file nav ships.
- 🚫 Split **`ReviewBar.vala`** without explicit user request.
- 🚫 Add review-state APIs to **`SourceView`** — **ReviewBar** only.
- ℹ️ Touch points: `liboccoder/Diff/ReviewBar.vala`, `liboccoder/SourceView.vala`, `liboccoder/Approvals.vala`, `ollmfilesd/FileHistory.vala`, `ollmfilesd/FileDiffPart.vala`, `libocfiles/ReviewFiles.vala`.
