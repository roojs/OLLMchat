# RPC-1.1 — `rpc_register` live stack

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Status:** **✔️** **DONE** — `OLLMrpc.rpc_register(bool live = false)` shipped. User asked to archive.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

**ℹ️** Category index: [`RPC-1.0-summary.md`](../RPC-1.0-summary.md). See [`-README.md`](../-README.md).

---

## Purpose

- **🔷** `✔️` One libocrpc call for stock envelope types, with a flag for the live stack.
- **🔷** `✔️` `register_live` is listen-side only. Clients do not call this helper.
- **🔷** `✔️` ollmfilesd uses `OLLMrpc.rpc_register()` (envelopes, no live).
- **🔷** `✔️` gnome-shell-rpc `Server.start()` uses `OLLMrpc.rpc_register(true)`.

---

## What landed

- **✔️** `OLLMrpc.rpc_register(bool live = false)` in `libocrpc/namespace.vala`.
- **✔️** Always: `Request` / `Response` / `Notification` / `Error`.
- **✔️** When `live`: Live `rpc_register()` chunk (`Remote`, `Subscribe`, `Invoke`, `Callback`), then `register_live` chunk.
- **✔️** `ollmfilesd/Application.vala` — `OLLMrpc.rpc_register()` first, then domain types.
- **✔️** gnome-shell-rpc `src/rpc/Server.vala` — `OLLMrpc.rpc_register(true)` first, then domain types.
- **✔️** Live-subset tests left as they are.

**Files**

- **ℹ️** `libocrpc/namespace.vala`
- **ℹ️** `ollmfilesd/Application.vala`
- **ℹ️** `/home/alan/git/gnome-shell-rpc/src/rpc/Server.vala`

---

## LLM notes

- **🚫** Do not fold `Client` static construct into this helper, and do not call `rpc_register(true)` from a client.
- **🚫** Do not put `Daemon.rpc_register()` here.
- **💩** gnome-shell-rpc `gi-rpc-echo` could call `OLLMrpc.rpc_register()` (no live) instead of four envelope lines. Not done.
