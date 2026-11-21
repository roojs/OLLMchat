# Edit-mode `stream_handler` null GLib criticals after failed `write`

**Status:** ✅ 2026-11-21. User closed. Deferred `add_stream_monitor` for edit `write` (`defer_stream_monitor`); agent API renamed to `add_stream_monitor` / `remove_stream_monitor`.

**Started:** 2026-11-20

**Pointer:** `docs/bug-fix-process.md`

**Related:** [2026-11-20-desktop-write-file-edit-loop.md](2026-11-20-FIXED-desktop-write-file-edit-loop.md) (gtktest1 session; model re-calls `write` instead of streaming). [monitored-requests stack](2026-11-21-FIXED-monitored-requests-stack.md).

## Problem

- 🔷 After a `write` / edit-mode tool call **fails** before edit mode starts (`execute_request` throws, e.g. invalid `edit_mode`), the next assistant stream logged multiple GLib criticals and could leave a stale **stream monitor** connected.
- 🔷 Expected: failed tool call returns `ERROR:` only; that request is **not** in `monitored_requests`; no `on_stream_chunk` / `on_message_completed` for it; no `self != NULL` criticals.
- 🔷 Actual (gtktest1, 2026-11-20 **09:13:21–09:13:23**): eight criticals on `oll_mtools_edit_mode_stream_*` while the model’s **next** completion was still streaming.

## Evidence

- ℹ️ Log: `~/.cache/ollmchat/ollmchat.debug.log`, same session as edit-loop bug.
- ✔️ **09:13:21.200** — `write` throws: `edit_mode must be one of: ast_path, line_numbers, complete_file` (`curry-combined`).
- ✔️ **09:13:21.203** — next `ChatCompletions` request starts (model recovery turn).
- ✔️ **09:13:23.038–09:13:23.754** — while that turn streams (`content_total=0` on done):
  - seven × `oll_mtools_edit_mode_stream_process_chunk: assertion 'self != NULL' failed`
  - one × `oll_mtools_edit_mode_stream_add_linebreak: assertion 'self != NULL' failed`
  - one × `oll_mtools_edit_mode_stream_finalize_and_handle_response: assertion 'self != NULL' failed`
- ✔️ **09:13:23.773** — second `write` succeeds (`complete_file`); different `request_id`.
- ℹ️ Same session (non-fatal): `markdown_gtk_render_tool_output_output: assertion 'self != NULL'` — separate renderer issue, not this bug’s primary scope.

## Vocabulary

- ℹ️ **Tools** (`write`, `bash`, …) stay in **History** — unchanged.
- ℹ️ **`Agent.monitored_requests`** — map of tool **invocations** (each `RequestBase` + `request_id`) hooked to assistant **`stream_chunk`** / **`message_completed`**.
- ℹ️ **`add_stream_monitor` / `remove_stream_monitor`** — agent API (renamed from `register_tool_monitoring` / `unregister_tool`).
- ℹ️ **`defer_stream_monitor`** on `RequestBase` — when true, `BaseTool.execute` skips up-front `add_stream_monitor`; edit mode adds the monitor after `stream_handler` exists.

## Root cause

- ✔️ `BaseTool.execute` used to subscribe **before** `yield request.execute()`, so failed gtktest1 `write` was in `monitored_requests` when validation threw.
- ✔️ `stream_handler` is created only on the success path; stale monitor still received the next stream → null `stream_handler` assertions.
- 🚫 Null-guards in stream callbacks alone — hides requests that should never have been subscribed.

## Fix applied

### 1. Defer stream monitor for edit `write` — ✔️

- ✔️ `defer_stream_monitor` default **false**; `EditMode.Request` overrides **true**.
- ✔️ `BaseTool.execute`: `if (!request.defer_stream_monitor) { add_stream_monitor(...); }`
- ✔️ `EditMode.Request.execute_request`: `add_stream_monitor` after `stream_handler` + `activate_request`.

### 2. Agent API rename — ✔️

| Old | New |
|-----|-----|
| `register_tool_monitoring` | `add_stream_monitor` |
| `unregister_tool` | `remove_stream_monitor` |

### 3. Other-tool throw path — ✔️

- ✔️ `RequestBase.execute`: `remove_stream_monitor` on permission denial and `execute_request` throw when the request had already been added (non-deferred tools).

## Out of scope / follow-ups

- ℹ️ **`markdown_gtk_render_tool_output_output`** — separate renderer bug if it still appears.
- ℹ️ **`on_message_completed` vs async finalize** ordering — only if criticals recur; not needed to close this bug.
- ℹ️ Edit-loop / model re-calling `write` — [desktop-write-file-edit-loop.md](2026-11-20-FIXED-desktop-write-file-edit-loop.md).

## Attempts / changelog

- ✔️ 2026-11-20 — Root cause from gtktest1 log + `BaseTool` / `Request` / `Stream` code.
- ✔️ 2026-11-20 — Catch-path `remove_stream_monitor` in `RequestBase.execute` (non-deferred tools).
- ✔️ 2026-11-21 — `defer_stream_monitor` + deferred `add_stream_monitor` for edit mode; API rename.
- ✅ 2026-11-21 — User closed bug.