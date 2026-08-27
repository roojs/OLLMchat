# 8.4.4 — DONE — Invoke errors to the client

**Status:** **DONE** ✅

**Parent:** [`RPC-8.4-rpc-positional-values-and-ffi.md`](RPC-8.4-rpc-positional-values-and-ffi.md)

**Consumers:** [`RPC-8.4.4.1-DONE-rpc-consumer-audit.md`](RPC-8.4.4.1-DONE-rpc-consumer-audit.md) → [`RPC-8.4.4.2-DONE-rpc-consumer-audit.md`](RPC-8.4.4.2-DONE-rpc-consumer-audit.md)

---

## Purpose (landed)

- **🔷** `✔️` When the real function throws, `Client.call` throws that same `GLib.Error` (type, GError code, message).
- **🔷** `✔️` JSON-RPC `Error.code` stays the envelope; GError code is a separate property.
- **🔷** `✔️` `reply_error` can pass the thrown `GLib.Error` from the invoke `catch`.

**Tree:** `libocrpc/` (`Client`, wire `Error` / `reply_error`), `tests/rpc/`.
