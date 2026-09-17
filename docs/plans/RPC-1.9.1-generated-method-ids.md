# RPC-1.9.1 — Generated method ids (integer call)

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Status:** **⏳** proposed — walkthrough only. No Vala until this flow is approved.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Prefix:** `RPC` (`libocrpc`) · see [`RPC-1.0-summary.md`](RPC-1.0-summary.md)

**Parent:** [`RPC-1.9-method-id-lookups.md`](RPC-1.9-method-id-lookups.md) **C** / **D** — client integer + generated table. **A+B** already landed (server token → `FfiSlot`).

**Related:**

- **ℹ️** [`done/RPC-8.6-URGENT-rpc-bin-learn-method-names.md`](done/RPC-8.6-URGENT-rpc-bin-learn-method-names.md) — bin already sends `Request.method` as a uint16 after first use
- **ℹ️** gnome-shell-rpc stub generator — emits client stubs; this is the generator
- **ℹ️** `libocrpc/Request.vala` · `libocrpc/Client.vala` · `libocrpc/Bin/Stream.vala`
- **ℹ️** Vfunc numbered path (other direction): [`done/RPC-1.10-ARCHIVED-vfunc-id-lookups.md`](done/RPC-1.10-ARCHIVED-vfunc-id-lookups.md)

---

## Purpose

- **🔷** After **A+B**, the server already gets a short name (name-ref → string, then `slot` when bound).
- **🔷** The leftover is the **client**: every call site still starts from a method string (`RPC-Folder.fetch_files`, or a typelib name like `Clutter-Actor.show`).
- **🔷** gnome-shell-rpc’s generator already knows every method the stubs will call. It can emit **integer constants** for that set.
- **🔷** Both ends **register** those integers (same meaning on client and server). That is the **shared table**.
- **🔷** A slightly modified RPC call then sends the **integer**, not the string.

---

## Where 1.9 A+B left the string

- **ℹ️** Client: `new Request()` with `method` set to the full handler name.
- **ℹ️** Encode: `write_name_ref` hashes that string. First use on this socket: UTF-8 + uint16. Later: `NAME_REF` + uint16 only.
- **ℹ️** That uint16 is **per connection** (even/odd, first-use order). It is not a process-wide constant.
- **ℹ️** Server: `read_name_ref` expands the token **back to a string**. If `ref_slots` already bound it, `Request.slot` is set and Ffi skips `methods`.
- **🔷** Caller still starts from a string. There is no client-side integer constant today.

---

## Three numbers (do not mix them)

- **🔷** **Catalog id** — this plan. Stable integer both processes already know. Generator (or the same table) assigns it.
- **ℹ️** **Name-ref token** — 8.6. Per-socket uint16. Exists only after this connection first sees the name (unless we pre-seed).
- **ℹ️** **`FfiSlot` index** — 1.9 **A**. Process-local `rows` index from `add_class` order. Listed FFI only. Gi has no row.

**🔷** The shared table is catalog id → what that method is (name, `FfiSlot`, or Gi). It is **not** today’s name-ref token unless we force those two to match.

---

## Phase A — generator constants + local register (no socket)

- **🔷** The generator walks the methods it will emit.
- **🔷** Each method gets a dense integer constant.
- **🔷** Both processes load the **same** table. No conversation. Same as both sides already knowing the method string today, except the key is an int.

Generator (gnome-shell-rpc stub gen) emits one constant per stub method it will call, e.g. folder-fetch-files = 7, actor-show = 128.

Each process, at boot / first local use, no socket:

- register(7, folder fetch-files wire name) — INT → name
- register(128, actor show wire name)
- server listed FFI: 7 → `FfiSlot` (rows index from `add_class`)
- server Gi: 128 → still Gi, but lookup is the id, not a string hash
- client: 7 and 128 are legal call ids

- **🔷** Registration is **local** on both ends. The table is shared because both loaded the same generated catalog, not because one side assigned ids after connect.
- **ℹ️** Listed FFI in this tree (~40 `add_class` methods) can use the same idea: generate constants from the `add_class` lists (**1.9 D**).
- **ℹ️** Gi / gnome-shell-rpc is not a closed set in libocrpc. The generator’s set **is** closed: only methods the stubs actually call.

---

## Phase B — integer call (the modified RPC call)

- **🔷** Call site uses the constant, not the method string.
- **🔷** String path stays for HTTP / JSON / tests / anything not in the catalog.

Today: construct `Request` with the method string, then `rpc.call`.

This plan: phase A already registered; construct the request with integer 7, not the string; then the same (or slightly modified) `rpc.call`.

- **🔷** Server dispatch uses the catalog id (or the already-bound `slot`). It does not hash the method string to find the method.
- **💩** Exact client API (set outbound `Request.slot` vs a new `Client.call` taking the int vs keep `method` optional) is not named yet.

---

## Shared table vs today’s name-ref

- **🔷** Shared table: both ends already agree that `7` means the folder fetch-files method. First call can be an integer.
- **ℹ️** Today’s name-ref: first call still introduces UTF-8; the token is whatever even/odd this socket minted.
- **🚫** Do not treat today’s name-table token as the catalog id unless both ends **pre-seed** the name tables in catalog order on connect.

**💩** Wire shape — pick one in review (not all three):

- Pre-seed `client_names` / `name_to_token` from the shared table at connect. Then today’s `NAME_REF` uint16 **is** the catalog id. No spec bump. Client can write the uint16 without hashing a string.
- Encode writes the catalog id from outbound `slot` / the constant. Decode sets `Request.slot` without `read_name_ref` expanding a string. May still be `NAME_REF` bytes if the ids match a pre-seeded table.
- New type byte for catalog method id. Spec bump. Only if pre-seed / `NAME_REF` reuse is the wrong lead.

---

## What this is not

- **ℹ️** Not 1.9 **E** (handshake catalog). **E** is: after connect, the **server assigns** ids and sends the list. This plan’s ids already exist in the generated table before connect.
- **ℹ️** Not 1.9 **F** (two-level object id + method id). One dense catalog id per method is enough for this cut.
- **ℹ️** Not vfuncs. Those are [`done/RPC-1.10-ARCHIVED-vfunc-id-lookups.md`](done/RPC-1.10-ARCHIVED-vfunc-id-lookups.md). Offset / `hook_id` are a different pair of ints.

---

## Open points

- **⏳** `🔷` Generator emits integer constants for every method it will call.
- **⏳** `🔷` Both ends register those integers (shared table).
- **⏳** `🔷` Modified RPC call uses the integer, not the string.
- **⏳** `💩` Wire: pre-seed name-ref vs write catalog id on today’s `NAME_REF` vs new type byte.
- **⏳** `💩` Client API name for the integer call.
- **⏳** `💩` In-tree `add_class` lists also generate constants (ollmfilesd / live), or gnome-shell-rpc generator only for this cut.
- **⏳** `💩` Gi catalog ids need a server int → typelib method table, or Gi stays on the string path.
- **ℹ️** HTTP / NDJSON keep full method strings.

---

## Suggested order

1. **⏳** Approve the shared-table + integer-call shape (this file).
2. **⏳** Pick the wire (pre-seed vs new type byte).
3. **⏳** libocrpc: register catalog id on both ends; integer call path; string path stays.
4. **⏳** Generator (consumer repo) emits the constants. Not this tree.

---

## LLM notes

- **🚫** Do not implement until this walkthrough is approved.
- **🚫** Do not edit gnome-shell-rpc (or any other consumer) from this file.
- **🚫** Do not mix catalog id, name-ref token, and `FfiSlot` index as if they were one number.
- **🚫** Do not pack the call signature into the integer (RPC-1.9).
- **🚫** Do not replace HTTP / JSON method strings in this cut.
- **🚫** Do not implement handshake **E** or two-level **F** here.
- **🚫** Do not add helper methods unless a later approved fence names them. User asked for register + a modified integer call — those two surfaces only.
- **ℹ️** Parent **C** (hand-written constants) is the fallback if the generator is not ready. Same table, ids typed by hand.
- **ℹ️** Parent **D** is the in-tree form: generate from `add_class` lists rather than from the stub generator.
