# 8.6 URGENT — Bin wire: learn method names (name tokens)

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Status:** **URGENT** · **✔️** implemented (agent) — awaiting user **✅**

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`done/8.1-DONE-bin-protocol-libocrpc.md`](done/8.1-DONE-bin-protocol-libocrpc.md) · wire spec [`docs/bin-rpc-protocol.md`](../bin-rpc-protocol.md) (**v3.1**)

**Related:** [`RPC-8.2-full-rpc-system.md`](RPC-8.2-full-rpc-system.md) · chat context 2026-08-26 (method names not learned; class aliases + property keys are)

---

## Purpose

- **🔷** `✔️` On the **bin** socket, **method name strings** are **learned** into the per-connection name table and later sent as **ids**.
- **🔷** `✔️` First use introduces the string; repeats use the compact id only.
- **🔷** `✔️` `Request.method` and `Notification.method` (live `Subscription` is not `Bin.Serializable` — notifies via `Notification`).
- **ℹ️** NDJSON / `Bin.Json` still shows full method strings; the bin bridge expands / learns tokens.

**Suggested order**

1. `✔️` Wire codec (`Stream` name-ref) + `bin_*_prop`
2. `✔️` Spec bump in `docs/bin-rpc-protocol.md`
3. `✔️` `bin-test` second encode has no full method UTF-8

---

## Design note (implement-time fix)

- **✔️** Plan first suggested reusing `TOKEN_REG_KEY` after the property tag. That collides with the reader’s `0xFF` → `TOKEN_REG_TYPE` branch (type byte position).
- **✔️** Shipped form: **`TYPE_NAME_REF_REG` (`0x7D`)** = introduce (uint16 + len + UTF-8); **`TYPE_NAME_REF` (`0x7E`)** = uint16 token only. Same even/odd tables.

---

## Implemented

- **✔️** `libocrpc/Bin/Stream.vala` — `TYPE_NAME_REF_REG` / `TYPE_NAME_REF`, `write_name_ref`, `read_name_ref`
- **✔️** `libocrpc/Request.vala` / `Notification.vala` — `method` via name-ref
- **✔️** `libocrpc/Bin/Json.vala` — JSON string ↔ name-ref for member `method` (stdio bridge)
- **✔️** `docs/bin-rpc-protocol.md` — v3.1
- **✔️** `tests/rpc/bin-test.vala` — two `Request`s, second payload has no `"RPC-Daemon.hello"` UTF-8

**Verify:** `meson test -C build --suite rpc` — `test-rpc-bin` / `test-rpc` / `test-rpc-t1` OK; `test-rpc-t2` still has unrelated pre-existing asserts (scan/DB).

---

## LLM notes

- **🚫** Third name table.
- **🚫** Tokenize all strings.
- **🚫** Change NDJSON text method strings (JSON stays full strings).
- **🚫** `TOKEN_REG_KEY` for method-value introduction after a property tag.
