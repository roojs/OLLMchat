# RPC-1.10 — Vfunc id lookups (numbered, not another name map)

> Archived 2026-09-17. Never a libocrpc plan — no Vala landed here. Consumer follow-on: gnome-shell-rpc https://github.com/roojs/gnome-shell-rpc/issues/1

**Status:** **ARCHIVED** — discussion walkthrough only.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

**Prefix:** `RPC` (`libocrpc`) · see [`../RPC-1.0-summary.md`](../RPC-1.0-summary.md)

**Parent idea:** [`../RPC-1.9-method-id-lookups.md`](../RPC-1.9-method-id-lookups.md) **B** — later FFI is token → slot → `fn`. Same idea the other way.

**Related:**

- **ℹ️** [`RPC-1.8-DONE-vfunc-hooks.md`](RPC-1.8-DONE-vfunc-hooks.md) — `Gi.vfunc_offset` / `vfunc_slot` / `vfunc_names`
- **ℹ️** [`RPC-8.3.6-rpc-live-callbacks.md`](RPC-8.3.6-rpc-live-callbacks.md) — `hook_id` mint (`RPC-Live-Callback.register`)
- **ℹ️** Consumer `add_hook` / peer map is **not this repo** (RPC-1.8). gnome-shell-rpc https://github.com/roojs/gnome-shell-rpc/issues/1 (`docs/bugs/2026-09-17-vfunc-id-lookups.md`, `docs/plans/0.8.5-vfunc-id-lookups.md`).

---

## Purpose

- **🔷** Split **local registration** (no socket) from **runtime registration** (wire) and **runtime fire**.
- **🔷** Local phase cannot talk to the other process. No inter-process id handshake there.
- **🔷** Strings (`vfunc_name`) stay in the process that already has them. Phase B sends `vfunc_id`, not the name.
- **🔷** Integers are named `*_id`. Phase B binds the method to the id the other end will send later. Phase C sends that id, not the name.
- **ℹ️** libocrpc already has the two ints: `Gi.vfunc_offset` → `vfunc_id`, `RPC-Live-Callback.register` → `hook_id`.

---

## Names (string vs int)

- **🔷** `vfunc_name` — **string**. Typelib / our literals (`allocate`, …).
- **🔷** `vfunc_id` — **int**. Class-struct slot. `Gi.vfunc_offset` (same typelib on both processes, no conversation).
- **🔷** `hook_id` — **int**. Which `Live.Hook` row. Minted by `RPC-Live-Callback.register`. `Live.Invoke.id`. Needs a live connection.
- **ℹ️** `lease_id` — **int**. Which live peer. Needs a live connection.
- **ℹ️** `reply_id` — **int**. One emit wait. Not a vfunc name.

Do not call `hook_id` a “callback id” in this plan.

---

## Who is who

- **🔷** **libocrpc** — `Gi.vfunc_offset`, `Connection.callbacks[hook_id]`, `Hook.emit`. Not `add_hook`.
- **🔷** **Consumer** — owns `add_hook` and the peer’s hook map (RPC-1.8). Not this tree.

---

## Phase A — local registration (no conversation)

- **🔷** Each process, at boot or first local use. **No socket.** Cannot mint `hook_id`. Cannot tell the peer anything.
- **🔷** Local table: `vfunc_name` → `vfunc_id`.

```
# EACH PROCESS — no socket
# vfunc_name is a STRING from OUR code or OUR typelib load
vfunc_id = Gi.vfunc_offset(ns, class_name, vfunc_name)  # INT, local
local_vfuncs[vfunc_name] = vfunc_id
```

- **🔷** Both processes can fill the same `vfunc_id` from the same typelib **without talking**. That is not inter-process registration.
- **🔷** `hook_id` does **not** exist yet.

---

## Phase B — runtime registration (conversation)

- **🔷** Socket is up. Consumer `add_hook` is **here**, not phase A.
- **🔷** Register the function and the **id this connection will use later** when talking about that method.
- **🔷** That id cannot be minted in phase A. It needs the peer.
- **🔷** Name → `vfunc_id` is phase A. Phase B sends `vfunc_id` + `hook_id`. One FFI signature (`"it"`). The name does not cross the wire.
- **🔷** The other end stores: this method ↔ this id. When it wants that method, it sends the **id** on the wire, not the name.

```
# CONSUMER CLIENT — runtime registration (socket up)
lease_id = create(...)                             # WIRE
for vfunc_name in names_we_care_about:             # STRING from phase A
    vfunc_id = local_vfuncs[vfunc_name]            # INT, local
    hook_id = RPC-Live-Callback.register()         # INT, WIRE
    bind trampoline to hook_id
    add_hook(vfunc_id, hook_id)                    # WIRE INT + INT ("it")

# CONSUMER SERVER — add_hook
# remember: when I want this method, I send hook_id
peer = leases[lease_id]
hook = connection.callbacks[hook_id]
peer.vfuncs[vfunc_id] = hook                       # INT → Hook
```

- **🔷** Later talk (phase C) uses `hook_id`. The name is not on that wire.
- **🔷** `vfunc_id` is the local slot (phase A). Sent at registration so fire does not hash `vfunc_name`.
- **🔷** Each object can still mint a new `hook_id` (new trampoline).
- **ℹ️** `Request.method` for `add_hook` is already 8.6-tokenized. That is not `vfunc_name`.

---

## Phase C — runtime fire (hot)

```
# CONSUMER SERVER — GObject already entered this vfunc (C pointer ran)
hook = this.vfuncs[vfunc_id]                       # INT lookup
if hook is missing:
    chain to base
    return
hook.emit(args)                                    # WIRE: hook_id — the id registered in phase B

# CONSUMER CLIENT — trampoline for that hook_id
RPC-Live-Callback.reply(reply_id, ...)             # INT
```

- **🔷** No `vfunc_name` on this path.

---

## Today vs that split

```
# TODAY (typical consumer)
add_hook(vfunc_name, hook_id)                      # WIRE STRING + INT
peer.vfuncs[vfunc_name] = hook                     # STRING key
fire: hook = this.vfuncs["allocate"]               # STRING hash every fire
```

```
# PROPOSED
phase A (no socket):  vfunc_name → vfunc_id        # local, Gi.vfunc_offset
phase B (runtime registration): add_hook(vfunc_id, hook_id)
                      other end: when I want this method, I send hook_id
phase C (fire):       vfuncs[vfunc_id] → emit(hook_id)
```

---

## This tree

- **ℹ️** `Gi.vfunc_offset` / `vfunc_slot` / `vfunc_names` — RPC-1.8.
- **ℹ️** `hook_id` — `RPC-Live-Callback.register` + `Live.Invoke.id` — RPC-8.3.6.
- **ℹ️** Ffi letter `"i"` packs as int (`default` in `Ffi.pack`). `"t"` is `uint64`.
- **🔷** No new libocrpc string HashMap. No library `add_hook`.

---

## Open points

- **🔷** `vfunc_id` is the class-struct offset. `hook_id` is the wire id on `Live.Invoke`.
- **🔷** Consumer `add_hook` signature `"it"`. Name stays local. That change is the consumer’s plan, not this file.

---

## Suggested order

1. **ℹ️** This repo: nothing to land.
2. **ℹ️** Consumer repo: their `add_hook` + peer map keyed by `vfunc_id`.

---

## LLM notes

- **🚫** Do not edit gnome-shell-rpc (or any other consumer) from this file.
- **🚫** Do not add `vfunc_name_lists` or any new string HashMap in `Gi`.
- **🚫** Do not mint `hook_id` or call `add_hook` in phase A.
- **🚫** Do not implement `g_vfunc_info_invoke`.
- **🚫** Do not add a library `add_hook` / `VfuncPeer`.
- **🚫** Do not densify `vfunc_offsets` into `FfiSlot` rows.
- **🚫** Do not use `hook_id` as `vfunc_id`.
- **ℹ️** 1.9 **G** dropped — wrong lead.
