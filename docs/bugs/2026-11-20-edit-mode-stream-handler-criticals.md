# Edit-mode `stream_handler` null GLib criticals after failed `write`

**Status:** ⏳ OPEN — partial fix in tree (`RequestBase.execute` unregisters on throw); verify on device. Map growth: [`active_tools` stack](2026-11-20-active-tools-stack.md).

**Started:** 2026-11-20

**Pointer:** `docs/bug-fix-process.md`

**Related:** [2026-11-20-desktop-write-file-edit-loop.md](2026-11-20-desktop-write-file-edit-loop.md) (gtktest1 session; model re-calls `write` instead of streaming).

## Problem

- 🔷 After a `write` / edit-mode tool call **fails** before edit mode starts (`execute_request` throws, e.g. invalid `edit_mode`), the next assistant stream logs multiple GLib criticals and may leave a stale tool monitor connected.
- 🔷 Expected: failed tool call returns `ERROR:` only; no stream callbacks on that request; no `self != NULL` criticals.
- 🔷 Actual (gtktest1, 2026-11-20 **09:13:21–09:13:23**): eight criticals on `oll_mtools_edit_mode_stream_*` while the model’s **next** completion is still streaming.

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

## Root cause

- ✔️ `BaseTool.execute` (`libollmchat/Tool/BaseTool.vala`) calls `register_tool_monitoring` **before** `yield request.execute()`.
- ✔️ `EditMode.Request.execute_request` creates `stream_handler` only on the success path (`liboctools/EditMode/Request.vala` after validation). On throw, `stream_handler` stays null.
- ✔️ Before the fix, `RequestBase.execute` returned `ERROR:` from the `catch` **without** `unregister_tool`, so `on_stream_chunk` / `on_message_completed` on that `Request` still ran on the **next** assistant stream.
- ✔️ `EditMode.Request.on_stream_chunk` and `on_message_completed` call `this.stream_handler.*` unconditionally → Vala emits null-deref assertions (`self != NULL`).
- 🚫 Do **not** add `if (stream_handler == null) return` in those callbacks as the only fix. That hides a request that should not be subscribed.

## Proposed fix

### 1. Always disconnect failed tool monitors — ✔️ applied

**Where:** `libollmchat/Tool/RequestBase.vala` — `execute()`, permission denial and `catch`.

#### Replace with

```vala
				if (!(yield permission_provider.request(this))) {
					GLib.debug("RequestBase.execute: Permission denied for tool '%s'", this.tool.name);
					this.agent.unregister_tool(this.request_id);
					return "ERROR: Permission denied: " + this.permission_question;
				}
```

```vala
			} catch (Error e) {
				GLib.debug("RequestBase.execute: Tool '%s' threw error: %s", this.tool.name, e.message);
				this.agent.unregister_tool(this.request_id);
				if (e.message != "") {
					return "ERROR: " + e.message;
				}
				return "ERROR: " + e.domain.to_string() + " " + e.code.to_string();
			}
```

### 2. Register monitoring only after edit mode is ready — 💩 optional hardening

**Where:** `liboctools/EditMode/Request.vala` + `BaseTool.execute` contract.

- 💩 Move `register_tool_monitoring` for edit-mode tools to **after** `stream_handler` is constructed (end of successful `execute_request`), or override `execute()` on `EditMode.Request` to register locally and never rely on pre-`execute_request` registration from `BaseTool`.
- 🔷 Keeps the invariant: if `on_stream_chunk` is connected, `stream_handler` exists.

### 3. `on_message_completed` teardown order — 💩 if criticals persist after (1)

**Where:** `EditMode.Request.on_message_completed` (`Request.vala` ~331–372).

- ✔️ Today: `unregister_tool` runs **before** `stream_handler.add_linebreak()` and `finalize_and_handle_response`.
- 💩 If overlap or re-call `write` tears down state mid-turn, ensure finalize runs only while this request is still the active monitor for that file, or defer `unregister_tool` until after finalize completes (coordinate with `reply_with_errors`).

### 4. `activate_request` vs async finalize — ℹ️ overlap

- ℹ️ `Tool.activate_request` unregisters the **previous** same-file `request_id` but does not wait for async finalize — apply/teardown ordering, not the main cause of `active_tools.size=11` ([`active_tools` stack bug](2026-11-20-active-tools-stack.md)).
- ℹ️ Duplicate `write` guard: [edit-loop bug](2026-11-20-desktop-write-file-edit-loop.md).

## Attempts / changelog

- ✔️ 2026-11-20 — Root cause from gtktest1 log + `BaseTool` / `Request` / `Stream` code.
- ✔️ 2026-11-20 — Applied `unregister_tool` on permission denial and `execute_request` throw in `RequestBase.execute`.

## Next

- 🔷 ⏳ Re-run gtktest1 flow: first `write` with invalid `edit_mode`, confirm **zero** `edit_mode_stream_*` criticals on the following stream.
- ⏳ 💩 If clean, consider (2) register-after-ready so edit-mode never depends on catch-side unregister.
- ℹ️ Track `markdown_gtk_render_tool_output_output` separately if it still appears after (1).