# File read wipes manager → focus-check crash + stale changed banner

**Status:** OPEN — analysis complete; fix not applied (awaiting approval per `docs/bug-fix-process.md`)

**Started:** 2026-07-05

**Process:** `docs/bug-fix-process.md`

---

## Problem

When opening or reloading a file in the V2 RPC client, a **“file modified on disk”** banner can appear even when the editor view is out of sync with expectations. Shortly after a successful `File.read` RPC, critical assertions fire:

```
G_LOG_LEVEL_CRITICAL : oll_mfiles_project_manager_get_rpc: assertion 'self != NULL' failed
G_LOG_LEVEL_CRITICAL : oll_mrpc_client_call: assertion 'self != NULL' failed
```

The banner offers **Overwrite / Refresh / Ignore**. Interacting with the window (focus regain, or banner actions that call `check_active_file_changed` / `reload_file_from_disk`) can hit the NULL `ProjectManager` and crash.

**Expected:** After `File.read`, the active `File` keeps its `manager` reference; focus checks and banner actions work. Changed-on-disk detection should reflect real external edits, not stale metadata from a mismatched load path.

**Actual:** `File.read` succeeds on the wire, then `copy_from` clears `manager` on the live client `File`. A later RPC (e.g. `File.changed.check` on window focus) dereferences `this.manager.rpc` on NULL.

---

## Reproduce (suspected)

1. Run `build/ollmapp/ollmchat --debug` with V2 window (`ollmapp/meson.build` → `V2/Window.vala`).
2. Open a project and select a file in the code editor.
3. Trigger `File.read` on the active file — e.g. agent **ReadFile** tool, **Refresh** on the changed banner, `ProjectManager.reload_file_from_disk`, or `FileHistory.revert`.
4. Regain window focus (or click **Refresh** on the banner).

**Observed log sequence (user report, 2026-07-05 ~09:40):**

```
Client.vala:339: send id=24 method=File.read
Client.vala:465: replied id=24 result_type= array=false
… ~4s later …
oll_mfiles_project_manager_get_rpc: assertion 'self != NULL' failed
oll_mrpc_client_call: assertion 'self != NULL' failed
```

`id=23` immediately before `File.read` was another successful RPC reply (method not logged on receive side).

---

## Root cause (confirmed in code)

### 1. `copy_from` clears `manager` after `File.read` / `File.register`

RPC deserialization creates a **new** `File` via `GLib.Object.new(gtype)` — no constructor, so `manager == null` (`libocrpc/Bin/Stream.vala` `parse_object`).

`manager` is intentionally omitted on the wire (`libocfiles/V2/FileBase.vala` `bin_read_prop` / `bin_write_prop` skip `"manager"`).

After `File.read`, the client merges the deserialized row onto the live object:

```365:372:libocfiles/V2/File.vala
				this.copy_from(row, {
					"buffer",
					"parent",
					"cursor-line",
					"cursor-offset",
					"scroll-position",
					"is-unsaved",
				});
```

**`"manager"` is not in the except list.** `Copyable.copy_from` copies every writable property from source → target, including `manager = null`.

Same gap in `File.register()` (`libocfiles/V2/File.vala` ~526).

**Contrast — correct pattern already used elsewhere:**

- Daemon replies: `row.copy_from(indexed, {"manager", "buffer", "parent"})` (`ollmfilesd/File.vala`)
- Client `FileHistory.revert`: `cached.copy_from(..., {"manager", "buffer", "parent"})` (`libocfiles/V2/FileHistory.vala`)
- `Folder.fetch_file` / `fetch_files`: explicitly `file.manager = this.manager` after RPC (no merge onto an existing live row)

**Why the crash is ~4s after `File.read`:** RPC uses `this.manager` **before** `copy_from`. Focus handler `Window.notify["is-active"]` → `check_active_file_changed` → `active_file.check_changed()` → `this.manager.rpc.call(...)` runs **after** `manager` was cleared.

### 2. Editor load path vs changed-check path are out of sync (banner false positives)

V2 `SourceView.open_file` still loads buffer content from **local disk**:

```414:416:liboccoder/V2/SourceView.vala
			if (!file.buffer.is_loaded) {
				try {
					yield file.buffer.read_async();
```

`GtkSourceFileBuffer.read_async()` reads via `GLib.File` on the client — **not** `File.read` RPC.

Changed detection uses daemon RPC with **stale `last_modified`**:

```483:489:libocfiles/V2/File.vala
			var response = yield this.manager.rpc.call(new OLLMrpc.Request() {
				method = "File.changed.check",
				param = new OLLMfilesd.FileParams() {
					path = this.path,
					buffer_dirty = this.buffer != null && this.buffer.is_modified,
					last_known_mtime = this.last_modified
				}
			});
```

Daemon logic (`ollmfilesd/File.vala` `call_changed_check`):

- `mtime_on_disk() > last_known_mtime` **and** `buffer_dirty` → `CHANGED_HAS_UNSAVED`

So if `file.last_modified` came from DB/index (via `File.fetch` / dropdown) and disk mtime moved ahead — e.g. external edit, or index lag — **any** unsaved buffer edit triggers the banner even when buffer content already matches disk (no content comparison; old non-V2 `check_updated` did compare).

Opening via `buffer.read_async` does **not** refresh `file.last_modified` from the post-load disk mtime.

---

## What is ruled in / out

| Hypothesis | Verdict |
|------------|---------|
| RPC client disconnected | **Out** — `File.read` id=24 completed normally |
| `active_file == null` on focus check | **Out** — would return early; crash is in `get_rpc`, not null `active_file` |
| `copy_from` overwrites `manager` with null | **In** — matches assertion name and code |
| Banner from real external edit only | **Partial** — possible, but stale `last_modified` + local buffer load makes false positives likely |
| `ProjectManager` itself destroyed | **Out** — window still holds `this.project_manager`; only the **File’s** `manager` field is cleared |

---

## Proposed fix (needs approval before coding)

### A — Minimal crash fix (root cause)

Add `"manager"` to `copy_from` except lists in:

- `libocfiles/V2/File.vala` — `read()` (~365)
- `libocfiles/V2/File.vala` — `register()` (~526)

Align with `FileHistory.revert` and daemon reply builders.

**Do not** add null-guards on `this.manager` before RPC — that would hide the defect.

### B — Changed-banner / load sync (follow-up, separate concern)

Pick one coherent load + check strategy for V2:

1. **Editor uses `File.read` RPC** in `SourceView.open_file` (and `reload_file_from_disk` already does) so buffer content and `last_modified` come from the same source; deprecate local `buffer.read_async` for GUI open in RPC mode.
2. **After any buffer load**, set `file.last_modified` from daemon row or fresh `mtime_on_disk` RPC so `last_known_mtime` is current before edits.
3. **Strengthen `File.changed.check`** on daemon to compare content (like old `check_updated`) or auto-reload when `!buffer_dirty` (old behaviour returned `NO_CHANGE` after reload).

Recommend **A first** (one-line except list), verify crash gone, then **B** as a second change with reproduction case for false banner.

---

## Verification plan

1. `--debug` run; open file; trigger `File.read` (ReadFile tool or banner Refresh).
2. Alt-tab away and back — expect **no** `get_rpc` assertion; `File.changed.check` debug line if logged.
3. Edit buffer, touch file on disk externally, refocus — banner should still appear **without** crash; Overwrite/Refresh should work.
4. Optional: log `file.manager` pointer before/after `copy_from` in `File.read` (temporary; remove when merged).

---

## Changelog

| Date | Change |
|------|--------|
| 2026-07-05 | Opened from user log + code review; root cause identified; fix proposed, not applied |
