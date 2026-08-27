# 8.4.4.1 — URGENT — RPC consumers: throw, then audit callers (items 1–5)

> `docs/plans/RPC-1.0-summary.md` is **not** updated for this sub-plan until it is done and archived.

**Status:** **URGENT** — Phase 1 + Phase 2 items **1–5** agent-done (**✔️**). Remaining callers → [`RPC-8.4.4.2-URGENT-rpc-consumer-audit.md`](RPC-8.4.4.2-URGENT-rpc-consumer-audit.md).

**Parent:** [`RPC-8.4.4-rpc-invoke-errors.md`](RPC-8.4.4-rpc-invoke-errors.md)

**Depends on:** [`8.4.4`](RPC-8.4.4-rpc-invoke-errors.md) Phase 1 — `Client.call` throws `GLib.Error`.

**Continuation:** [`RPC-8.4.4.2-URGENT-rpc-consumer-audit.md`](RPC-8.4.4.2-URGENT-rpc-consumer-audit.md) — items **6–13**.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** `✔️` **Phase 1** — wrappers and `rpc.call` sites throw. Delete old `response.error` / canned-`FAILED` handling.
- **🔷** `✔️` **Phase 2 items 1–5** — see below. Tree is source of truth (no fence archive).
- **🔷** `⏳` Items **6–13** — [`8.4.4.2`](RPC-8.4.4.2-URGENT-rpc-consumer-audit.md).
- **ℹ️** `tests/rpc` is [`RPC-8.4.4`](RPC-8.4.4-rpc-invoke-errors.md).

---

## Phase 1 — Throw, drop dead handling (`✔️`)

- **🔷** `✔️` Wrappers `throws GLib.Error`; delete `response.error` swallows (`Folder`, `File`, `ReviewFiles`, `FileHistory`, `ProjectManager`).
- **🔷** `✔️` Direct `rpc.call`: delete canned `FAILED(response.error.message)`.
- **🔷** `✔️` `File.to_real` / `DeleteManager.remove`: drop canned `FAILED` on wrapper `false`.
- **ℹ️** See tree under `libocfiles/`, `liboctools/`, `examples/`.

---

## Phase 2 items 1–5 (`✔️`)

### 1. `✔️` `rpc_project_description`

- **🔷** Catch in wrapper, drop `throws`, `GLib.critical`, return `""`.
- **ℹ️** `libocfiles/Folder.vala`

### 2. `✔️` `rpc_roots`

- **🔷** Catch in wrapper, drop `throws`, `GLib.critical`, return empty list.
- **ℹ️** `libocfiles/Folder.vala`

### 3. `✔️` Tools / CLI that already throw

- **🔷** No code. Keep throwing (`execute_request`, examples, etc.).

### 4. `✔️` `fetch_file` — restore / revert reload + Window alerts

- **🔷** `Alert.show` / `Banner.show` + banner FIFO queue on `Window`.
- **🔷** Restore miss/throw → `Alert.show`. Revert lookup miss/throw → `Alert.show`.
- **ℹ️** `libocfiles/ProjectManager.vala`, `FileHistory.vala`, `ollmapp/Window.vala`

### 5. `✔️` Overlay scan (`has_file` / `created` / `modified`)

- **🔷** `has_file` `throws`; `Scan` catch + `continue`. No `lookup_failed` set.
- **🔷** `created` / `modified` / `removed`: one try, soft fail `throw`, catch → `Banner.show`.
- **🚫** Catch-then-rethrow only to Banner; side-channel skip sets.
- **ℹ️** `liboctools/FileVerification.vala`, `libocbwrap/Scan.vala`, `libocbwrap/FileVerification.vala`

---

## Shared contract (carried into 8.4.4.2)

| Severity | Transport |
| --- | --- |
| **Progress / FYI** | `client.*` / `event.*` → `ActivityBanner` |
| **Banner** | `Banner.show` → sticky `Adw.Banner` + FIFO (non-blocking) |
| **Alert** | `Alert.show` → modal dialog |
| **Log only** | `GLib.critical` / `warning` |

---

## LLM notes

- **🚫** Re-open Phase 1 or items 1–5 fences here — see tree or git.
- **🚫** Put items 6–13 work back into this file — use [`8.4.4.2`](RPC-8.4.4.2-URGENT-rpc-consumer-audit.md).
- **ℹ️** Do not mark this plan **✅** or update `RPC-1.0-summary.md` until **8.4.4.2** is done and both are archived.
