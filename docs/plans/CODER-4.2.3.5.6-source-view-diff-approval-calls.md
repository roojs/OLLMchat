# 4.2.3.5.6 — Approval calls

**Status:** **✔️** in tree — fences applied on `ollmfilesd` and on the flip editor `examples/oc-test-source-diff/` (`SourceView.vala`, `ReviewBar.vala`). `liboccoder` has the same editor calls. Not user-smoked.

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md)

**Design:** [`CODER-4.2.3.5.4-source-view-diff-wire-model.md`](CODER-4.2.3.5.4-source-view-diff-wire-model.md)

**Supersedes:** [`done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md) — do not apply its fences.

**Depends on:** [`CODER-4.2.3.5.5-source-view-diff-items.md`](CODER-4.2.3.5.5-source-view-diff-items.md) — diff items stored on the file server, hunk text on the wire.

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans

---

## Purpose

- 🔷 One hunk goes through the diff item. That item applies the change. The file server updates the stored item.
- 🔷 **Accept file changes**, **Reject file changes**, and **Reset** are one method, `FileHistory.decide`. The action is accept, reject, or reset.
- 🔷 Accept leaves the project file alone. Reject undoes that hunk. Reset of a reject puts the hunk back. Reset of an accept does not change the file.

---

## Calls

The bar and the menu send a decision. They do not send the file body.

```
desktop                                          ollmfilesd
────────────────────────────────────────────────────────────────
one hunk — Accept / Reject / Reset
  FileDiffPart.apply
    diff-item id, action        →
                                      that item applies it
                                      server updates the stored item
                                  ←  that item, updated

menu — Accept file changes
       Reject file changes
       Reset
  FileHistory.decide
    history id, action              →
                                      action is accept, reject, or reset
                                      applied to every diff item
                                      on that history
```

- 🔷 One hunk is a call on the diff item. The request is that item and the approval.
- 🔷 `decide` covers every diff item on that history. It does not call the diff item once per hunk.
- 🔷 The file server updates the stored items, so the next load still has the decision.
- 🔷 The daemon does not run `Differ` again for a decision. The hunk text is already on the item.
- 🔷 When every diff item on that history has a decision, `file_history.reviewed` is set. A row existing is not enough. The item still has to be decided.
- 🔷 Accept turns the band light blue and moves to the next hunk. Reject turns the band light grey and moves to the next hunk. Reset sends the band back to pending red or green.
- 🔷 Click a decided band to scroll to that hunk. Reset is the existing bar button.
- 🔷 After accept, removed lines leave the view and the green comes off the added lines. Those lines look like normal source. The colour of a decided hunk is the bar band.
- 🔷 The active hunk uses the deeper red and green. Click a red or green hunk to make it active. Click white space and there is no active hunk. Accept and Reject hide until a hunk is selected again.
- 🔷 Remove the header changed-files popover. `show_pending_diff` is the only way to open a pending diff. Whole-file approve and reject are the bulk menu, not a second way to open the diff.
- ✅ Shades in `resources/style.css` stay. Source: `.oc-diff-add` `rgb(239, 252, 239)`, `.oc-diff-remove` `rgb(252, 239, 239)`. Active source and active bar: `.oc-diff-add-active` `rgb(191, 242, 191)`, `.oc-diff-remove-active` `rgb(242, 191, 191)`. Other bar bands: `.oc-diff-add-band` `rgb(215, 247, 215)`, `.oc-diff-remove-band` `rgb(247, 215, 215)`. Accepted bar: `.oc-diff-accepted` `rgb(191, 191, 242)`. Rejected bar: `.oc-diff-rejected` `rgb(221, 221, 221)`.
- ℹ️ Menu labels are in `liboccoder/Diff/ReviewBar.vala`. Today they only flip in-memory decisions. Today the whole-file wire is `FileHistory.rpc_approve` and `FileHistory.rpc_revert`.
- ℹ️ No separate undo call. Looking back at approved batches is file history's job. Git already covers uncommitted work in the tree.
- 💩 **Accept changes to all files** and **Reject changes to all files** are `decide` once per file.
- 💩 The hunk reply is that one updated item. The desktop adjusts the editor from the hunk text it already has.
- 💩 The hunk method is `FileDiffPart.apply`. It is not `FileHistory.decide`.
- 💩 The action on the wire is an int. `1` accept, `-1` reject, `0` reset. Same values as `accepted`. Reset stores `accepted` 0 and `decided_at` 0.
- 💩 `live` and `live_stamp` stay instance properties on the one `FileHistory` handler. `part` is a `Gee.HashMap<int, FileDiffPart>` on that same handler, keyed by diff-item id. `apply` looks up that map. `FileDiffPart.for_rpc` is given that handler. Keys are `int`. An id is cast at the lookup. Line numbers are not columns.

---

## Phase 1

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding context before applying.

- 🔷 `FileDiffPart.apply` is one hunk. `FileHistory.decide` is every hunk on that history. One wire call each.
- 🔷 Accept of a pending hunk does not write the project file. Reject replaces that hunk's new lines with `hunk_remove`. Reset of a reject puts `hunk_add` back. Reset of an accept does not write the file.
- 💩 Accept of an already rejected hunk puts `hunk_add` back, then stores `accepted` 1. Bulk accept would otherwise leave the undone lines on disk.
- 💩 A file write updates `live_stamp` from that file's `mtime_on_disk`. `parts` and `rebuild_parts` use the same value. Otherwise the next `parts` treats the list as stale and runs `Differ` again.
- 💩 `decide` runs the same span write as `apply`, in process, from the bottom of the file upward. It does not send `FileDiffPart.apply` once per hunk.
- ℹ️ Band colours, the deeper active red and green, and scrolling to a clicked band are already in `ReviewBar`. No fence for those.
- ℹ️ `FileHistory.rpc_approve` and `FileHistory.rpc_revert` stay registered. The header popover was their caller. This phase stops showing that popover.

### 1. `ollmfilesd/FileHistory.vala` — the remembered list stays on the handler

**Why:** `apply` runs on a `FileDiffPart` handler. `decide` runs on the `FileHistory` handler. Both use the one `FileHistory` object registered for `"FileHistory"`. `parts` and `rebuild_parts` keep `this.live` and `this.live_stamp`. `part` is the same objects, keyed by diff-item id, so `apply` does not walk every list.

**Where:** visibility of `live`, `live_stamp`, and `rpc_manager`. The `part` map is new. `rebuild_parts` drops the previous ids for that history and stores the list it just kept. The project file is the `File` from the active project. Its buffer supplies the text. The backup path is a cache file, not a project `File`.

**Depends on:** [`4.2.3.5.5`](CODER-4.2.3.5.5-source-view-diff-items.md).

#### Remove

```vala
		private ProjectManager rpc_manager;
```

#### Replace with

```vala
		internal ProjectManager rpc_manager;
```

#### Remove

```vala
		private Gee.HashMap<int, Gee.ArrayList<FileDiffPart>> live {
			get; set; default = new Gee.HashMap<int, Gee.ArrayList<FileDiffPart>>();
		}
		private Gee.HashMap<int, int> live_stamp {
			get; set; default = new Gee.HashMap<int, int>();
		}
```

#### Replace with

```vala
		internal Gee.HashMap<int, Gee.ArrayList<FileDiffPart>> live {
			get; set; default = new Gee.HashMap<int, Gee.ArrayList<FileDiffPart>>();
		}
		internal Gee.HashMap<int, int> live_stamp {
			get; set; default = new Gee.HashMap<int, int>();
		}
		internal Gee.HashMap<int, FileDiffPart> part {
			get; set; default = new Gee.HashMap<int, FileDiffPart>();
		}
```

#### Remove — `rebuild_parts` stores a fresh list

```vala
				this.live.set((int) history.id, fresh);
				this.live_stamp.set((int) history.id, (int) stamp);
				return fresh;
```

#### Replace with

```vala
				if (this.live.has_key((int) history.id)) {
					foreach (var old in this.live.get((int) history.id)) {
						this.part.unset((int) old.id);
					}
				}
				foreach (var part in fresh) {
					this.part.set((int) part.id, part);
				}
				this.live.set((int) history.id, fresh);
				this.live_stamp.set((int) history.id, (int) stamp);
				return fresh;
```

#### Remove — `rebuild_parts` stores the kept list

```vala
			this.live.set((int) history.id, kept);
			this.live_stamp.set((int) history.id, (int) stamp);
```

#### Replace with

```vala
			if (this.live.has_key((int) history.id)) {
				foreach (var old in this.live.get((int) history.id)) {
					this.part.unset((int) old.id);
				}
			}
			foreach (var part in kept) {
				this.part.set((int) part.id, part);
			}
			this.live.set((int) history.id, kept);
			this.live_stamp.set((int) history.id, (int) stamp);
```

#### Remove — `parts` reads the stamp from a path

```vala
			var stamp = (int64) 0;
			try {
				var info = GLib.File.new_for_path(histories.get(0).path).query_info(
					GLib.FileAttribute.TIME_MODIFIED_USEC,
					GLib.FileQueryInfoFlags.NONE,
					null);
				stamp = (int64) info.get_attribute_uint64(
					GLib.FileAttribute.TIME_MODIFIED_USEC);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						e.message
					)
				});
				return;
			}
```

#### Replace with

```vala
			var file = this.rpc_manager.get_file_from_active_project(
				histories.get(0).path);
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
			var stamp = file.mtime_on_disk();
```

#### Remove — `rebuild_parts` reads the project file from a path

```vala
			var project = (string) GLib.File.new_for_path(
				history.path).load_bytes(null).get_data();
			var info = GLib.File.new_for_path(history.path).query_info(
				GLib.FileAttribute.TIME_MODIFIED_USEC, GLib.FileQueryInfoFlags.NONE, null);
			var stamp = (int64) info.get_attribute_uint64(GLib.FileAttribute.TIME_MODIFIED_USEC);
```

#### Replace with

```vala
			var file = this.rpc_manager.get_file_from_active_project(history.path);
			if (file == null) {
				throw new GLib.IOError.FAILED("file not found");
			}
			if (file.buffer == null) {
				file.manager.buffer_provider.create_buffer(file);
			}
			var project = file.buffer.get_text();
			var stamp = file.mtime_on_disk();
```

### 2. `ollmfilesd/FileDiffPart.vala` — `apply` one hunk

**Why:** The bar sends the diff-item id and the action. That row writes `accepted` and, for a reject or a restore, the project file.

**Where:** `rpc_register`, then `for_rpc` and `apply` after `compare`. `commit` is the in-process body `decide` also runs.

**Depends on:** §1.

#### Remove

```vala
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("FileDiffPart", typeof(FileDiffPart));
		}
```

#### Replace with

```vala
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("FileDiffPart", typeof(FileDiffPart));
			OLLMrpc.Request.add_class(
				"FileDiffPart", typeof(FileDiffPart),
				"apply", "xi"
			);
		}

		private ProjectManager rpc_manager;
		private FileHistory history;

		/**
		 * Wire handler for {@code FileDiffPart.apply}.
		 *
		 * @param manager daemon projects and the database
		 * @param history the registered {@code FileHistory} handler
		 */
		public FileDiffPart.for_rpc(ProjectManager manager, FileHistory history)
		{
			Object();
			this.rpc_manager = manager;
			this.history = history;
		}
```

#### Add — `apply` and `commit` after `compare`

`apply` is the wire method. `commit` writes one hunk. `1` accept, `-1` reject, `0` reset.

```vala
		/**
		 * ''FileDiffPart.apply'' — accept, reject, or reset one hunk.
		 *
		 * @param request inbound RPC
		 * @param id file_diff_part.id
		 * @param action 1 accept, -1 reject, 0 reset
		 */
		public void apply(OLLMrpc.Request request, int64 id, int action)
		{
			if (!this.history.part.has_key((int) id)) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"diff item is not loaded"
					)
				});
				return;
			}
			var item = this.history.part.get((int) id);
			item.commit.begin(this.history, this.rpc_manager.db, action, (obj, res) => {
				try {
					item.commit.end(res);
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
					retval = OLLMrpc.val("o", item)
				});
			});
		}

		/**
		 * Store one decision and write the project file when the
		 * hunk text on disk has to change.
		 *
		 * A decision that leaves the file alone stores and returns.
		 * Reject of a pending or accepted hunk writes ''hunk_remove''.
		 * Accept or reset of a rejected hunk writes ''hunk_add''
		 * through the project file's buffer. Later hunks on the
		 * remembered list shift by the line delta. Updates
		 * ''live_stamp'' from {@link File.mtime_on_disk} after the
		 * write. The store after a write repeats the no-write store.
		 *
		 * @param history the registered {@code FileHistory} handler
		 * @param db daemon database
		 * @param action 1 accept, -1 reject, 0 reset
		 * @throws GLib.Error the project file could not be read or written
		 */
		public async void commit(FileHistory history, SQ.Database db, int action) throws GLib.Error
		{
			var histories = new Gee.ArrayList<FileHistory>();
			FileHistory.query(db).select(
				"WHERE id = %lld".printf(this.file_history_id),
				histories
			);
			if (histories.size == 0) {
				throw new GLib.IOError.FAILED("history row not found");
			}
			var list = history.live.get((int) this.file_history_id);
			if ((action != -1 && this.accepted != -1) || (action == -1 && this.accepted == -1)) {
				this.accepted = action == 0 ? 0 : action;
				this.decided_at = action == 0 ? (int64) 0 : GLib.get_real_time();
				FileDiffPart.query(db).updateById(this);
				var open = false;
				foreach (var item in list) {
					if (item.accepted == 0) {
						open = true;
					}
				}
				histories.get(0).reviewed = open ? 0 : 1;
				FileHistory.query(db).updateById(histories.get(0));
				return;
			}
			var insert = this.hunk_add;
			if (action == -1) {
				insert = this.hunk_remove;
			}
			var file = history.rpc_manager.get_file_from_active_project(
				histories.get(0).path);
			if (file == null) {
				throw new GLib.IOError.FAILED("file not found");
			}
			if (file.buffer == null) {
				file.manager.buffer_provider.create_buffer(file);
			}
			var add_count = this.new_line_end < this.new_line_start
				? 0 : this.new_line_end - this.new_line_start + 1;
			var remove_count = this.old_line_end < this.old_line_start
				? 0 : this.old_line_end - this.old_line_start + 1;
			var span = this.accepted == -1 ? remove_count : add_count;
			var at = this.new_line_start;
			var inserted = insert == "" ? 0 : insert.split("\n").length;
			var changes = new Gee.ArrayList<FileChange>();
			changes.add(new FileChange(file) {
				start = at,
				end = at + span,
				replacement = insert
			});
			yield file.buffer.apply_edits(changes);
			var delta = inserted - span;
			this.new_line_end = inserted == 0
				? this.new_line_start - 1
				: this.new_line_start + inserted - 1;
			foreach (var other in list) {
				if (other.id == this.id || other.new_line_start < at + span) {
					continue;
				}
				other.new_line_start += delta;
				other.new_line_end += delta;
			}
			history.live_stamp.set((int) this.file_history_id, (int) file.mtime_on_disk());
			this.accepted = action == 0 ? 0 : action;
			this.decided_at = action == 0 ? (int64) 0 : GLib.get_real_time();
			FileDiffPart.query(db).updateById(this);
			var open = false;
			foreach (var item in list) {
				if (item.accepted == 0) {
					open = true;
				}
			}
			histories.get(0).reviewed = open ? 0 : 1;
			FileHistory.query(db).updateById(histories.get(0));
		}
```

### 3. `ollmfilesd/FileHistory.vala` — `decide` every hunk on one history

**Why:** Accept file changes, Reject file changes, and Reset are one method. The action is the difference.

**Where:** `add_class` gains `decide`. The method follows `parts`.

**Depends on:** §2.

#### Remove

```vala
			OLLMrpc.Request.add_class(
				"FileHistory", typeof(FileHistory),
				"rpc_approve", "sx",
				"rpc_revert", "sx",
				"parts", "x"
			);
```

#### Replace with

```vala
			OLLMrpc.Request.add_class(
				"FileHistory", typeof(FileHistory),
				"rpc_approve", "sx",
				"rpc_revert", "sx",
				"parts", "x",
				"decide", "xi"
			);
```

#### Add — `decide` after `parts`

Bottom of the file first, so a later hunk's `new_line_start` still matches the text. Reply is the remembered list.

```vala
		/**
		 * ''FileHistory.decide'' — accept, reject, or reset every
		 * hunk on one history row.
		 *
		 * Does not call {@code FileDiffPart.apply} on the wire.
		 * Runs {@link FileDiffPart.commit} from the bottom upward.
		 *
		 * @param request inbound RPC
		 * @param id file_history.id
		 * @param action 1 accept, -1 reject, 0 reset
		 */
		public void decide(OLLMrpc.Request request, int64 id, int action)
		{
			if (!this.live.has_key((int) id)) {
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					error = new OLLMrpc.Error(
						OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"diff items are not loaded"
					)
				});
				return;
			}
			var rows = new Gee.ArrayList<FileDiffPart>();
			rows.add_all(this.live.get((int) id));
			rows.sort((a, b) => {
				return b.new_line_start - a.new_line_start;
			});
			this.commit_decided.begin(request, (int) id, rows, action);
		}

		/**
		 * Yields {@link FileDiffPart.commit} from the bottom upward,
		 * then replies with the remembered list.
		 *
		 * @param request inbound RPC
		 * @param id file_history.id cast for the {@code live} key
		 * @param rows hunks, highest {@code new_line_start} first
		 * @param action 1 accept, -1 reject, 0 reset
		 */
		private async void commit_decided(
			OLLMrpc.Request request,
			int id,
			Gee.ArrayList<FileDiffPart> rows,
			int action
		)
		{
			try {
				foreach (var part in rows) {
					yield part.commit(this, this.rpc_manager.db, action);
				}
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
				retval = OLLMrpc.val("o", this.live.get(id))
			});
		}
```

### 4. `ollmfilesd/Application.vala` — register `FileDiffPart`

**Why:** `add_class` names `apply`. `Request.register` binds the handler that has the database. That handler is given the same `FileHistory` object registered as `"FileHistory"`.

**Where:** the `FileHistory` register.

**Depends on:** §2.

#### Remove

```vala
			OLLMrpc.Request.register("FileHistory", new FileHistory.for_rpc(this.project_manager));
```

#### Replace with

```vala
			var history = new FileHistory.for_rpc(this.project_manager);
			OLLMrpc.Request.register("FileHistory", history);
			OLLMrpc.Request.register("FileDiffPart",
				new FileDiffPart.for_rpc(this.project_manager, history));
```

### 5. `liboccoder/Diff/ReviewBar.vala` — send the decision

**Why:** Accept, Reject, and the bar's Unapprove button send one hunk. The file menu sends `decide` for the open history. Accept all files and Reject all files send `decide` once per pending file.

**Where:** the Accept and Reject `clicked` handlers, the Unapprove `clicked` handler, and the bulk action lambdas. They call `send_part`.

**Depends on:** §3, §4.

#### Remove — Accept and Reject call `send_part`

```vala
			this.accept_btn.clicked.connect(() => {
				this.on_accept_clicked();
			});
```

#### Replace with

```vala
			this.accept_btn.clicked.connect(() => {
				this.send_part.begin(1);
			});
```

#### Remove

```vala
			this.reject_btn.clicked.connect(() => {
				this.on_reject_clicked();
			});
```

#### Replace with

```vala
			this.reject_btn.clicked.connect(() => {
				this.send_part.begin(-1);
			});
```

#### Remove

```vala
		private void on_accept_clicked()
		{
			if (this.active < 0 || this.active >= this.hunks.size) {
				return;
			}
			if (this.hunks.get(this.active).decision != HunkDecision.PENDING) {
				return;
			}
			var decided = this.active;
			this.hunks.get(decided).decision = HunkDecision.ACCEPTED;
			this.next();
		}

		private void on_reject_clicked()
		{
			if (this.active < 0 || this.active >= this.hunks.size) {
				return;
			}
			if (this.hunks.get(this.active).decision != HunkDecision.PENDING) {
				return;
			}
			var decided = this.active;
			this.hunks.get(decided).decision = HunkDecision.REJECTED;
			this.next();
		}
```

#### Replace with

```vala
		/**
		 * ''FileDiffPart.apply'' for the active hunk, then the next pending band.
		 *
		 * @param action 1 accept, -1 reject, 0 reset
		 */
		private async void send_part(int action)
		{
			if (this.active < 0 || this.active >= this.parts.size) {
				return;
			}
			if (action != 0 && this.parts.get(this.active).accepted != 0) {
				return;
			}
			if (action == 0 && this.parts.get(this.active).accepted == 0) {
				return;
			}
			var before = this.parts.get(this.active);
			var file = this.source_view.current_file;
			OLLMrpc.Response response;
			try {
				response = yield this.source_view.manager.rpc.call(new OLLMrpc.Request() {
					method = "FileDiffPart.apply",
					args = OLLMrpc.args("xi", before.id, action)
				});
			} catch (GLib.Error e) {
				GLib.warning("Failed to apply diff item: %s", e.message);
				return;
			}
			if (response.error != null) {
				GLib.warning("Failed to apply diff item: %s", response.error.message);
				return;
			}
			this.parts.set(this.active,
				(OLLMfiles.FileDiffPart) response.retval.get_object());
			switch (action) {
				case 1:
					this.hunks.get(this.active).decision = HunkDecision.ACCEPTED;
					break;

				case -1:
					this.hunks.get(this.active).decision = HunkDecision.REJECTED;
					break;

				default:
					this.hunks.get(this.active).decision = HunkDecision.PENDING;
					break;
			}
			if (action == 0) {
				this.accept_btn.visible = true;
				this.reject_btn.visible = true;
				this.unapprove_btn.visible = false;
				this.map_area.queue_draw();
			}
			if (action != 0) {
				this.next();
			}
			if (file != null && (action == -1 || before.accepted == -1)) {
				var add_count = before.new_line_end < before.new_line_start
					? 0 : before.new_line_end - before.new_line_start + 1;
				var remove_count = before.old_line_end < before.old_line_start
					? 0 : before.old_line_end - before.old_line_start + 1;
				var span = before.accepted == -1 ? remove_count : add_count;
				var want = action == -1 ? before.hunk_remove : before.hunk_add;
				var buffer = file.buffer as Gtk.TextBuffer;
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				buffer.get_iter_at_line(out start_iter, before.new_line_start - 1);
				end_iter = start_iter;
				var at_end = start_iter.is_end();
				if (span > 0 && buffer.get_iter_at_line(
					out end_iter, before.new_line_start - 1 + span)) {
					at_end = false;
				}
				if (span > 0 && at_end) {
					buffer.get_end_iter(out end_iter);
				}
				buffer.delete(ref start_iter, ref end_iter);
				if (want != "") {
					var replacement = want;
					if (!at_end) {
						replacement = want + "\n";
					}
					buffer.insert(ref start_iter, replacement, -1);
				}
			}
			if (file != null) {
				this.source_view.show_pending_diff.begin(file);
			}
		}

		/**
		 * ''FileHistory.decide'' for one pending row.
		 *
		 * When that row is the open file, the source buffer deletes
		 * each hunk's line range and inserts the hunk text, from
		 * the bottom upward, before the next paint. The reply's
		 * shifted line numbers are not used for that edit.
		 *
		 * @param history_id file_history.id
		 * @param action 1 accept, -1 reject, 0 reset
		 */
		private async void decide_file(int64 history_id, int action)
		{
			OLLMrpc.Response response;
			try {
				response = yield this.source_view.manager.rpc.call(new OLLMrpc.Request() {
					method = "FileHistory.decide",
					args = OLLMrpc.args("xi", history_id, action)
				});
			} catch (GLib.Error e) {
				GLib.warning("Failed to decide file: %s", e.message);
				return;
			}
			if (response.error != null) {
				GLib.warning("Failed to decide file: %s", response.error.message);
				return;
			}
			if (this.queue.size < 1 || this.file_index >= this.queue.size) {
				return;
			}
			if (this.queue.get(this.file_index).approve_id != history_id) {
				return;
			}
			var file = this.source_view.current_file;
			if (file == null) {
				return;
			}
			var ordered = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
			ordered.add_all(this.parts);
			ordered.sort((a, b) => {
				return b.new_line_start - a.new_line_start;
			});
			foreach (var before in ordered) {
				var write = (action == -1 && before.accepted != -1)
					|| (action != -1 && before.accepted == -1);
				if (!write) {
					continue;
				}
				var add_count = before.new_line_end < before.new_line_start
					? 0 : before.new_line_end - before.new_line_start + 1;
				var remove_count = before.old_line_end < before.old_line_start
					? 0 : before.old_line_end - before.old_line_start + 1;
				var span = before.accepted == -1 ? remove_count : add_count;
				var want = action == -1 ? before.hunk_remove : before.hunk_add;
				var buffer = file.buffer as Gtk.TextBuffer;
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				buffer.get_iter_at_line(out start_iter, before.new_line_start - 1);
				end_iter = start_iter;
				var at_end = start_iter.is_end();
				if (span > 0 && buffer.get_iter_at_line(
					out end_iter, before.new_line_start - 1 + span)) {
					at_end = false;
				}
				if (span > 0 && at_end) {
					buffer.get_end_iter(out end_iter);
				}
				buffer.delete(ref start_iter, ref end_iter);
				if (want != "") {
					var replacement = want;
					if (!at_end) {
						replacement = want + "\n";
					}
					buffer.insert(ref start_iter, replacement, -1);
				}
			}
			this.source_view.show_pending_diff.begin(file);
		}
```

#### Remove — Unapprove click body

```vala
			this.unapprove_btn.clicked.connect(() => {
				if (this.active < 0 || this.active >= this.hunks.size) {
					return;
				}
				if (this.hunks.get(this.active).decision == HunkDecision.PENDING) {
					return;
				}
				this.hunks.get(this.active).decision = HunkDecision.PENDING;
				this.accept_btn.visible = true;
				this.reject_btn.visible = true;
				this.unapprove_btn.visible = false;
				this.map_area.queue_draw();
			});
```

#### Replace with

```vala
			this.unapprove_btn.clicked.connect(() => {
				this.send_part.begin(0);
			});
```

#### Remove — bulk file actions set bands in memory only

The three `activate` lambdas for `accept-file`, `reject-file`, and `reset-file`.

```vala
			accept_file_action.activate.connect(() => {
				foreach (var hunk in this.hunks) {
					hunk.decision = HunkDecision.ACCEPTED;
				}
				if (this.file_index < this.file_bulk.length) {
					this.file_bulk[this.file_index] = HunkDecision.ACCEPTED;
				}
				this.active = -1;
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.map_area.queue_draw();
			});
```

#### Replace with

```vala
			accept_file_action.activate.connect(() => {
				if (this.file_index >= this.queue.size) {
					return;
				}
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.decide_file.begin(this.queue.get(this.file_index).approve_id, 1);
			});
```

#### Remove

```vala
			reject_file_action.activate.connect(() => {
				foreach (var hunk in this.hunks) {
					hunk.decision = HunkDecision.REJECTED;
				}
				if (this.file_index < this.file_bulk.length) {
					this.file_bulk[this.file_index] = HunkDecision.REJECTED;
				}
				this.active = -1;
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.map_area.queue_draw();
			});
```

#### Replace with

```vala
			reject_file_action.activate.connect(() => {
				if (this.file_index >= this.queue.size) {
					return;
				}
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.decide_file.begin(this.queue.get(this.file_index).approve_id, -1);
			});
```

#### Remove

```vala
			reset_file_action.activate.connect(() => {
				foreach (var hunk in this.hunks) {
					hunk.decision = HunkDecision.PENDING;
				}
				if (this.file_index < this.file_bulk.length) {
					this.file_bulk[this.file_index] = HunkDecision.PENDING;
				}
				this.active = this.hunks.pending_after(-1);
				this.active = this.active < 0 && this.hunks.size > 0 ? 0 : this.active;
				if (this.active >= 0) {
					this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
				}
				var pending = this.active >= 0
					&& this.hunks.get(this.active).decision == HunkDecision.PENDING;
				this.accept_btn.visible = pending;
				this.reject_btn.visible = pending;
				this.unapprove_btn.visible = false;
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.map_area.queue_draw();
			});
```

#### Replace with

```vala
			reset_file_action.activate.connect(() => {
				if (this.file_index >= this.queue.size) {
					return;
				}
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.decide_file.begin(this.queue.get(this.file_index).approve_id, 0);
			});
```

#### Remove — accept all files only flips the open file's bands, then signals

```vala
			accept_all_files_action.activate.connect(() => {
				for (var fi = 0; fi < this.file_bulk.length; fi++) {
					this.file_bulk[fi] = HunkDecision.ACCEPTED;
				}
				foreach (var hunk in this.hunks) {
					hunk.decision = HunkDecision.ACCEPTED;
				}
				this.active = -1;
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.map_area.queue_draw();
				this.accept_all_files();
			});
```

#### Replace with

```vala
			accept_all_files_action.activate.connect(() => {
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				for (var fi = 0; fi < this.queue.size; fi++) {
					this.decide_file.begin(this.queue.get(fi).approve_id, 1);
				}
			});
```

#### Remove

```vala
			reject_all_files_action.activate.connect(() => {
				for (var fi = 0; fi < this.file_bulk.length; fi++) {
					this.file_bulk[fi] = HunkDecision.REJECTED;
				}
				foreach (var hunk in this.hunks) {
					hunk.decision = HunkDecision.REJECTED;
				}
				this.active = -1;
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.map_area.queue_draw();
				this.reject_all_files();
			});
```

#### Replace with

```vala
			reject_all_files_action.activate.connect(() => {
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				for (var fi = 0; fi < this.queue.size; fi++) {
					this.decide_file.begin(this.queue.get(fi).approve_id, -1);
				}
			});
```

### 6. `liboccoder/Diff/ReviewBar.vala` — keep the hunk `next` already chose

**Why:** `send_part` calls `next`, then `show_pending_diff`, which calls `update_diff`. That reset jumps back to the first pending hunk. A refresh of the same file keeps the current band.

**Where:** `update_diff`, the `this.parts = parts` line and the `this.active = this.hunks.pending_after(-1)` lines.

**Depends on:** §5.

#### Remove

```vala
			this.parts = parts;
```

#### Replace with

```vala
			var same_file = this.parts.size > 0 && parts.size > 0
				&& this.parts.get(0).file_history_id == parts.get(0).file_history_id;
			var keep = this.active;
			this.parts = parts;
```

#### Remove

```vala
			this.active = this.hunks.pending_after(-1);
			this.active = this.active < 0 && this.hunks.size > 0 ? 0 : this.active;
```

#### Replace with

```vala
			if (!same_file || keep < 0 || keep >= this.hunks.size) {
				this.active = this.hunks.pending_after(-1);
				this.active = this.active < 0 && this.hunks.size > 0 ? 0 : this.active;
			}
```

### 7. `liboccoder/Diff/ReviewBar.vala` — white space clears the active hunk

**Why:** Click white space and there is no active hunk. Accept and Reject hide until a hunk is selected again.

**Where:** `on_map_clicked`, the `i < 0` branch.

**Depends on:** none.

#### Remove

```vala
			if (i < 0) {
				return;
			}
```

#### Replace with

```vala
			if (i < 0) {
				this.active = -1;
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				this.map_area.queue_draw();
				return;
			}
```

### 8. `liboccoder/SourceView.vala` — paint a decided hunk as plain lines

**Why:** After accept, removed lines leave the view and the green comes off the added lines. A decided hunk's colour is the bar band. The open `Gtk.TextBuffer` deletes that line range and inserts the hunk. It does not replace the whole buffer. Line numbers are from before the reply. The reply's shifted numbers are only for the next paint.

**Where:** `show_pending_diff`, inside the hunk loop. `send_part` edits `current_file.buffer` before that paint.

**Depends on:** §5.

`send_part` deletes the hunk's line range in the source buffer and inserts the hunk text, using line numbers from before the reply. This section only changes the paint.

#### Remove — red and green rows for every hunk

```vala
				if (remove_count > 0 && part.hunk_remove != "") {
					this.diff_remove_at.add(part.new_line_start);
					this.diff_remove_n.add(remove_count);
					var removed = part.hunk_remove.split("\n");
					for (var r = 0; r < remove_count && r < removed.length; r++) {
						display.add(removed[r]);
						this.diff_baseline.add(0);
						kinds.add(2);
					}
				}
				if (add_count == 0) {
					if (part.new_line_start > new_i) {
						new_i = part.new_line_start;
					}
					continue;
				}
				for (var ln = part.new_line_start; ln < part.new_line_start + add_count && ln <= editor_lines.length; ln++) {
					display.add(editor_lines[ln - 1]);
					this.diff_baseline.add(ln);
					kinds.add(1);
				}
```

#### Replace with

A decided hunk copies the editor lines with kind 0. A pending hunk keeps the red removed rows and the green added rows.

```vala
				if (part.accepted != 0) {
					if (add_count == 0) {
						if (part.new_line_start > new_i) {
							new_i = part.new_line_start;
						}
						continue;
					}
					for (var ln = part.new_line_start;
						ln < part.new_line_start + add_count && ln <= editor_lines.length;
						ln++) {
						display.add(editor_lines[ln - 1]);
						this.diff_baseline.add(ln);
						kinds.add(0);
					}
					new_i = part.new_line_start + add_count;
					continue;
				}
				if (remove_count > 0 && part.hunk_remove != "") {
					this.diff_remove_at.add(part.new_line_start);
					this.diff_remove_n.add(remove_count);
					var removed = part.hunk_remove.split("\n");
					for (var r = 0; r < remove_count && r < removed.length; r++) {
						display.add(removed[r]);
						this.diff_baseline.add(0);
						kinds.add(2);
					}
				}
				if (add_count == 0) {
					if (part.new_line_start > new_i) {
						new_i = part.new_line_start;
					}
					continue;
				}
				for (var ln = part.new_line_start; ln < part.new_line_start + add_count && ln <= editor_lines.length; ln++) {
					display.add(editor_lines[ln - 1]);
					this.diff_baseline.add(ln);
					kinds.add(1);
				}
```

### 9. `liboccoder/SourceView.vala` — drop the header changed-files popover

**Why:** `show_pending_diff` is the only way to open a pending diff. Whole-file approve and reject are the bulk menu.

**Where:** header-bar construction. `Approvals.vala` stays in the tree. It is not added to the header.

**Depends on:** §5.

#### Remove

```vala
			// Create Approvals widget with ProjectManager
			this.approvals = new Approvals(this.manager);
			
			// Add approvals bar to header bar (after save button)
			header_bar.append(this.approvals);
			
			// Connect file_selected signal to open files
			this.approvals.file_selected.connect((file) => {
				this.open_file.begin(file);
			});
```

---

## LLM notes

- 🚫 Apply any fence from [`4.2.3.5.3`](done/CODER-4.2.3.5.3-SUPERSEDED-source-view-diff-part-rows.md). That `decide` took `part_index` and re-read both full texts.
- 🚫 Rewrite the project file on accept, or on reset of an accept.
- 🚫 Approve / reset aliased to GtkSource undo/redo.
- 🚫 Accept / Reject buttons drawn inside the green or red area.
- 🚫 Accept all files as the primary header button.
- 🚫 Keep the header changed-files popover.
- 🚫 Split `ReviewBar.vala`.
- 🚫 Review-state APIs on `SourceView`. `ReviewBar` only.
- ℹ️ Touch points: `liboccoder/Diff/ReviewBar.vala`, `liboccoder/Approvals.vala`, `liboccoder/SourceView.vala`, `ollmfilesd/FileHistory.vala`, `ollmfilesd/FileDiffPart.vala`.
