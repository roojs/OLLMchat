# RPC-1.3 — Stamp lease id on live proxy decode

> Landed. Index: [`RPC-1.0-summary.md`](../RPC-1.0-summary.md).

**Status:** **✔️** **done** — `libocrpc/Bin/Stream.vala`, `libocrpc/Client.vala`, `tests/rpc/gi-test.vala`, `docs/bin-rpc-protocol.md`.

**Prefix:** `RPC` (`libocrpc`) · see [`RPC-1.0-summary.md`](../RPC-1.0-summary.md)

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Requested by:** gnome-shell-rpc nested shell boot (consumer). **🚫** That repo must not patch `libocrpc` directly — land the fix here.

**Related (done track):** [`RPC-8.3-libocrpc-live-handles-and-signals.md`](RPC-8.3-libocrpc-live-handles-and-signals.md) / live handle wire format.

**Follow-on:** live **write** key truncation — [`RPC-1.4-live-handle-write-lease-key.md`](../RPC-1.4-live-handle-write-lease-key.md).

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

---

## Purpose

- **🔷** **✔️** When `live_handles` is on and the client decodes a **live GObject** (wire: type + handle + `TOKEN_END`), stamp the **lease handle** on the new proxy so callers can use it as a stub without hand-packing `Response.args` uint64s.
- **ℹ️** Before this cut, `Bin.Stream.parse_object` put the proxy in `Client.proxies` but did **not** stamp the handle on the object.
- **🔷** **✔️** Consumers read `(uint64) get_data("rpc-lid")` — no `args`/`t` live-return workaround for ordinary returns.

---

## Landed (see the tree)

- **ℹ️** `libocrpc/Bin/Stream.vala` — `parse_object` live path: `set_data("rpc-lid", (void*) handle)` after `proxies.set`
- **ℹ️** `libocrpc/Client.vala` — `proxies` docblock names the qdata key
- **ℹ️** `docs/bin-rpc-protocol.md` — client qdata contract
- **ℹ️** `tests/rpc/gi-test.vala` — retval live object qdata matches export id

---

## Out of scope (deferred)

- **🚫** Prefer live-handle **write** over Serializable dump when already leased — not this cut.
- **🚫** Live write `lease_ids` key truncation — [`RPC-1.4`](../RPC-1.4-live-handle-write-lease-key.md).
- **🚫** JSON/HTTP live semantics; gnome-shell-rpc consumer edits.

---

## Done when

- **🔷** **✔️** Live decode stamps lease handle on the proxy.
- **🔷** **✔️** Test covers retval live object round-trip.
- **ℹ️** Consumer can drop `args`/`t` live-return workarounds after depending on this `libocrpc`.
