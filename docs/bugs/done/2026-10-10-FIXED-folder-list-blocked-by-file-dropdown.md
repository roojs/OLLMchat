# Folder list never sent

**Status:** ✔️ 09:22 `--test-flow` opened `/home/alan/gitlive/OLLMchat`, `replied id=3`, `Folder.fetch_children` replied, `folders=232`.

**Related:** ℹ️ `docs/bugs/done/2026-07-07-FIXED-ollmfilesd-second-startup-rpc-blocked.md` (one request in flight is the contract). ℹ️ `docs/plans/CODER-4.2.5-project-file-selector.md`

## Problem

- **🔷** The file UI under test is `examples/oc-test-source-diff/FileSelector.vala`. It does not use `OLLMcoder.FileDropdown`.
- **🔷** Opening the file pop-down on Tree asks for the project's child folders with `Folder.fetch_children`.
- **🔷** The tree stays empty.
- **🔷** The client log shows `Folder.fetch_files` go out at project pick, then 120s later `Folder.fetch_children` times out with no send line.

## Evidence

- **ℹ️** Log: `~/.cache/ollmchat/com.roojs.ollmchat.test-source-diff.debug.log` (19:54 run, project `/home/alan/gitlive/OLLMchat`).
- **✔️** `19:54:54.684` `opening project path=/home/alan/gitlive/OLLMchat`
- **✔️** `19:54:54.685` `Client.vala:666` `id=3 method=Folder.fetch_files` (the only send).
- **✔️** `19:56:55.002` `call timed out Folder.fetch_files id=3 after 120 s`, then `ProjectFiles.refresh: call timed out`. That refresh is `FileDropdown.update_project`.
- **✔️** Same millisecond: `id=4` `Folder.fetch_pending_approvals` is sent and times out at once. `id=5` `ProjectManager.rpc_activate_project`, `id=6` `Folder.fetch_children`, and `id=7` `Folder.fetch_files` time out with no `Client.vala:666` send line.
- **✔️** `FolderTreeStore.vala:239` `folder list failed: call timed out`.
- **✔️** `send_head` writes `pending.get(0)` only, and returns when that head is already sent (`libocrpc/Client.vala`).
- **✔️** `examples/oc-test-source-diff.vala` builds `new OLLMcoder.SourceView(manager)` on the selector manager and hides the first child. The constructor still connects `active_project_changed` to `apply_manager_state`, which yields `file_dropdown.update_project`.
- **✔️** Daemon `fetch_files_reply` yields `wait_scan_idle` before it replies (`ollmfilesd/Folder.vala`). A scan already running holds that call until the client timeout.
- **✔️** `call()` starts `call_timeout_seconds` when the call is queued, not when it is written. id=6 expires with id=3.

## Root cause

- **✔️** The selector never calls `FileDropdown`. The smoke window also builds a `SourceView` on the same manager. That hidden header still sends `Folder.fetch_files` on project activate and holds the only RPC slot. `Folder.fetch_children` stays queued and is never written.

## Proposed fix

- **🔷** `CoderView` is the screen. It holds the selector header and the editor. Project selection stays on that screen.
- **🔷** The header is the selector row already in the smoke app (`ProjectSelector`, `FileSelector`). It is not `ProjectDropdown` or `FileDropdown`.
- **🔷** The test-app `SourceView` is the copied editor (buffer, gutter, diff, save, approvals, review bar). It does not open projects. It emits `file_changed`. `CoderView` listens and sets the file button. A chosen file calls `open_file`.
- **🔷** The copy does not own `FileDropdown` or `ProjectDropdown`, and it does not call `activate_project`. `liboccoder` stays as it is. `Client.send_head` stays one request in flight.

**Why:** The buffer and the file list are different objects. The fetch in the log is the old header living inside `SourceView`.

**Where:** the new `examples/oc-test-source-diff/SourceView.vala`, these sites from the library file:

- field `file_dropdown`
- constructor: `active_project_changed` → `apply_manager_state`, `new FileDropdown`, `file_selected`, `header_bar.append`, `invalidate_cache` → `file_dropdown.refresh`
- `apply_manager_state`: `update_project` / `file_dropdown.visible`
- `on_project_selected`: sensitivity, css, `grab_focus`
- `open_project`: `yield this.file_dropdown.update_project`
- placeholder updates in `on_file_selected` and the deleted-file path
- key handler check of `file_dropdown.popup.visible`

#### Remove

```vala
			this.manager.active_project_changed.connect((project) => this.apply_manager_state.begin());
```

```vala
			this.file_dropdown = new FileDropdown();
			this.file_dropdown.file_selected.connect(this.on_file_selected);
			this.file_dropdown.visible = false;
			header_bar.append(this.file_dropdown);
```

```vala
				this.file_dropdown.refresh.begin();
```

```vala
			yield this.file_dropdown.update_project(this.manager.active_project);
			this.file_dropdown.visible = true;
```

```vala
			yield this.file_dropdown.update_project(project);
```

## Ruled out

- **🚫** Changing `liboccoder/FileDropdown.vala` or `liboccoder/SourceView.vala`. The header lives on `CoderView`. The editor copy is the one that loses `FileDropdown`.
- **🚫** Writing the next queued request while one is in flight. That reverses the 2026-07-07 client contract.
- **🚫** A second `ProjectManager` for the editor. The real client has one manager.
- **🚫** Skipping `update_project` because the header is hidden, watching `visible-child-name`, or a helper named `open_desktop`.
- **🚫** Moving the `folders.load` call between popover map, button click, and project notify. The folder request is already queued. It is not the head.

## Attempts

- **ℹ️** Spinner, call-site moves, and an inlined pop-down open sequence. The 19:54 log is after those. id=3 is still `Folder.fetch_files`. id=6 `Folder.fetch_children` still has no send line.
- **ℹ️** `send_head` was briefly changed to write the first unsent entry, then restored. `Client.vala` matches git.
- **ℹ️** A second `ProjectManager` was put on the editor and then removed.
- **ℹ️** A short `SourceViewWrap` plus an off-screen library `SourceView` for `ReviewBar` was built, then removed. The editor in the test app is a full copy.
- **ℹ️** `liboccoder/SourceView.vala` and `liboccoder/Diff/ReviewBar.vala` were edited, then restored. Both match git.

## Current failure (21:26 click)

- **🔷** `./build/examples/oc-test-source-diff --test-flow --debug` shows the window and runs `TestSourceDiff.test_flow`: project button, then the first project row.
- **✔️** Row was `/home/alan/gitlive/OLLMchat`. Client log `21:26:41.065` sent `id=3 method=ProjectManager.rpc_activate_project`. No `replied id=3`. No `Folder.fetch_children`. Printed `folders=0 loading=false`.
- **✔️** Daemon log `~/.cache/ollmchat/ollmfilesd.debug.log` same millisecond: `recv id=3 method=ProjectManager.rpc_activate_project`, then `ProjectManager.vala:272` `opening project skipped already active path=/home/alan/gitlive/OLLMchat`. Nothing after that line.
- **ℹ️** That branch calls `request.reply` with `msg = "ok"` and returns. The live daemon is `/usr/bin/ollmfilesd` pid 517358. It was back in `do_poll` after the window quit.
- **✔️** `09:08:35` `folder wait available=0`. The reply is not in the client `DataInputStream`.
- **✔️** `ss` during that wait: daemon fd 10 on `ollmfilesd.sock` has `Send-Q` 11520 toward the client socket `1770983` (client fd 15). `Recv-Q` is 0. The daemon is in `do_poll`, so the bytes are already in the kernel send buffer and the client read watch is not taking them.

## Root cause (09:08 unread reply)

- **✔️** `Client.on_read` completes the load-projects `Gee.Promise` on the stack of the socket callback. `run_test` continues there and called `selector_loop.run()`.
- **✔️** The read watch cannot fire again until that callback returns. `rpc_activate_project` is written, the daemon replies `ok`, and the bytes stay in the kernel send buffer (`Send-Q` 11520, client `get_available()` 0). `choose` is still waiting, so `Folder.fetch_children` is never sent.

## Proposed fix

- **🔷** Start `selector_loop` from an idle, then `yield`, so `on_read` returns before the window loop runs. `test_flow` stays the click sequence. `Client.send_head` stays one request in flight. The live daemon is not restarted.

**Why:** The reply is already in the socket. The client stops reading it for as long as the load-projects callback has not returned.

**Where:** `examples/oc-test-source-diff.vala` `run_test`, after `window.present()`.

```vala
		GLib.Idle.add(() => {
			selector_loop.run();
			this.run_test.callback();
			return false;
		});
		yield;
```

## Verified

- **✔️** `09:22:45` `--test-flow --debug`: `project /home/alan/gitlive/OLLMchat`, `id=3` `rpc_activate_project` `replied id=3` at `.451`, `id=4` `Folder.fetch_children` `replied id=4` at `.469`. Printed `folders=232 loading=false`.
