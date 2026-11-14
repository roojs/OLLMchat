# No approve option on load

Status: ✔️ built, not user-verified

## Problem

🔷 Load the OLLMchat project. An unapproved file should open with an Accept
control. The editor opens `tests/README.md` and there is no way to approve.

## Evidence

ℹ️ Client log `~/.cache/ollmchat/ollmchat.debug.log` at 10:55:39.

- ℹ️ `Folder.fetch_pending_approvals` replied.
- ℹ️ Two `File.fetch` calls, then `File.read` of `tests/README.md`.
- ℹ️ No `FileHistory.parts` call. Accept is drawn only after parts for the open file.
- ✔️ Pending SQL for this project still returns unapproved rows, including
  `tests/editing/Hello world` (filebase 113029, `is_need_approval=1`,
  `delete_id=43132`, backup 253 bytes).
- ✔️ That path is not on disk. `File.fetch` reads `child_map` only, so the
  startup open of the first pending row returns "file not found" and stops.
- ✔️ `AgentPi/Factory.initialize_widget` then opens the restored README, which
  has no pending hunks, so Accept stays hidden.

## Root cause

✔️ The pending list is not empty. The first row is a deleted unapproved file
that `File.fetch` cannot return, and the restored file is opened on top of
that failed open.

## Proposed fix

🔷 `File.fetch`: when the path is not in `child_map`, load the `filebase` row
that still needs approval and is not ignored.

#### Add

```vala
			if (project_file == null) {
				var found = new Gee.ArrayList<FileBase>();
				FileBase.query(this.manager.db, this.manager).select(
					"WHERE path = '" + path.replace("'", "''")
						+ "' AND is_need_approval = 1 AND is_ignored = 0"
						+ " AND base_type = 'f'",
					found
				);
				if (found.size < 1) {
					request.reply(new OLLMrpc.Response() {
						id = request.id,
						msg = "file not found"
					});
					return;
				}
				var row = new File(this.manager);
				row.copy_from(found.get(0), {"manager", "buffer", "parent"});
				request.reply(new OLLMrpc.Response() {
					id = request.id,
					retval = OLLMrpc.val("o", row)
				});
				return;
			}
```

🔷 Startup must not open the restored file once the pending list has rows.
The pending refresh already opens the first row.

#### Replace with

```vala
				if (this.project_manager.review_files.get_n_items() < 1 &&
					this.project_manager.active_file != null) {
					yield this.widget.editor.open_file(this.project_manager.active_file);
				}
```

Same condition in `liboccoder/AgentFactory.vala`,
`liboccoder/AgentPi/Factory.vala`, and `liboccoder/Skill/Factory.vala`.

🔷 `ReviewBar.update_diff` with an empty part list must not clear the pending
file nav. Hide Accept and return.

#### Add

```vala
			if (parts.size < 1) {
				this.parts = parts;
				this.hunks.clear();
				this.hunk_line_sum = 0;
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				return;
			}
```

## Next

⏳ Restart the daemon and the app. The first pending file should open and
Accept should be visible. 🚫 Do not add a `/.git/` path test.
