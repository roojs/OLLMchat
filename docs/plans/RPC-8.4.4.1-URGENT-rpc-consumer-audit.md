# 8.4.4.1 — URGENT — Audit RPC call consumers

> `docs/plans/RPC-1.0-summary.md` is **not** updated for this sub-plan until it is done and archived.

**Status:** **URGENT** **PROPOSED**

**Parent:** [`RPC-8.4.4-rpc-invoke-errors.md`](RPC-8.4.4-rpc-invoke-errors.md)

**Depends on:** [`8.4.4`](RPC-8.4.4-rpc-invoke-errors.md) Phase 1 — `Client.call` throws `GLib.Error`.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

---

## Purpose

- **🔷** `⏳` Audit every consumer of `Client.call` and of the libocfiles RPC wrappers.
- **🔷** `⏳` Decide per site: propagate, already throws, or a real (specific) catch.
- **🔷** `⏳` Fence the agreed edits here after the audit. Full-tree compile waits on those fences.
- **ℹ️** Urgent because 8.4.4 makes `call()` throw. Wrappers that still check `response.error` will not compile.

---

## How to audit

- **🔷** `⏳` For each site, record:
  - File + method.
  - Direct `yield rpc.call` vs wrapper (`fetch_file`, `read`, `rpc_project_description`, …).
  - Today: swallow (`if (response.error != null) return …`), `IOError.FAILED` wrap, or already `throws GLib.Error`.
  - After 8.4.4: compile break, runtime knock-on, or already fine.
- **🔷** `⏳` Decide per site (not one rule for the tree):
  - Already throws → no signature edit; note runtime (error now surfaces).
  - Should propagate → add `throws GLib.Error`, delete swallow / `IOError.FAILED` wrap.
  - Has a real catch (specific domain, user-visible) → keep that catch, do not broaden it.
- **🔷** `⏳` Then add **Remove** / **Replace with** / **Add** fences in this file.

---

## Starting inventory (search, then walk callers)

- **ℹ️** `yield` / `.call(` on `OLLMrpc.Client` — `libocfiles`, `liboctools`, `libochf`, `examples`, `tests/rpc`.
- **ℹ️** Wrappers that today check `response.error`:
  - `libocfiles/Folder.vala` — `rpc_project_description`, `rpc_roots`, `fetch_file`, `contains_folder`, `fetch_files`
  - `libocfiles/File.vala` — `exists`, `read`, `rpc_write`, `check_changed`, `register`, `rpc_delete`, `apply_permissions`
  - `libocfiles/ReviewFiles.vala` — `fetch_pending`
  - `libocfiles/FileHistory.vala` — `rpc_approve`, `rpc_revert`
  - `libocfiles/ProjectManager.vala` — `rpc_load_projects_from_db`, `fetch_folder`, `rpc_create_project`
  - `libocfiles/ProjectFiles.vala` — `refresh`, load-more
  - `liboctools/ReadFile/Summarize.vala`
- **ℹ️** Already throw, wrap as `IOError.FAILED(response.error.message)`:
  - `liboctools/CodebaseSearch/Request.vala`
  - `libochf/Model.vala` `fetch_siblings`
  - `liboctools/HuggingFace/Request.vala`
  - `examples/oc-hf.vala`, `examples/oc-vector-index.vala`, `examples/oc-vector-search.vala`

---

## Sample: `rpc_project_description` (audit only)

All five yield sites already `throws GLib.Error`:

- `liboccoder/Skill/Runner.vala` — `task_creation_prompt`, `iteration_prompt`, `continue_prompt`
- `liboccoder/Task/Details.vala` — `refinement_prompt`
- `liboccoder/Task/Tool.vala` — `executor_prompt`

Those sit under `send_async` / iteration / continue / `refine` / `Tool.run`. `examples/oc-test-skill-agent.vala` `run_test` already throws.

- **ℹ️** Today a daemon/RPC failure becomes `project_description = ""` and the LLM still runs.
- **ℹ️** After 8.4.4, the throw leaves prompt fill immediately (retry loops wrap `chat_call.send` only).
- **ℹ️** Replay’s `task_creation_prompt` catch already does `GLib.error`.

---

## LLM notes

- **🚫** Add `throws` everywhere the compiler complains without reading the site.
- **🚫** Catch-all that turns the error into `false` / `""` / `null` / empty list / a fake `Folder`.
- **🚫** Wrap `rpc_project_description` in `catch` to keep a blank prompt.
- **🚫** Fence 8.4.4 wire / `reply_error` / `Client.call` here — that is [`RPC-8.4.4`](RPC-8.4.4-rpc-invoke-errors.md).
- **🚫** Edit ollmfilesd `*Params` handlers.
