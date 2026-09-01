# RPC-1.3 — Stamp lease id on live proxy decode

> **`RPC-1.0-summary.md` is not updated until this plan is done and archived.**

**Status:** **PROPOSED**

**Prefix:** `RPC` (`libocrpc`) · see [`RPC-1.0-summary.md`](RPC-1.0-summary.md)

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Requested by:** gnome-shell-rpc nested shell boot (consumer). **🚫** That repo must not patch `libocrpc` directly — land the fix here.

**Related (done track):** [`done/RPC-8.3-libocrpc-live-handles-and-signals.md`](done/RPC-8.3-libocrpc-live-handles-and-signals.md) / live handle wire format.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

---

## Purpose

- **🔷** When `live_handles` is on and the client decodes a **live GObject** (wire: type + handle + `TOKEN_END`), stamp the **lease handle** on the new proxy so callers can use it as a stub without hand-packing `Response.args` uint64s.
- **ℹ️** Today `Bin.Stream.parse_object` puts the proxy in `Client.proxies` but does **not** stamp the handle on the object. Consumers (e.g. gnome-shell-rpc `gsr-lease-id` / `Runtime.attach_lease`) either walk `proxies` after the fact or work around by returning handles in `args` and rebuilding stubs locally.
- **🔷** That workaround is the wrong design.

---

## Current behaviour `ℹ️`

```text
Server: export(obj) → write live handle in retval
Client: parse_object → Object.new(T); proxies[handle] = live; return live
        // live has no lease qdata
Consumer: attach_lease(live) walks proxies by identity, or avoids retval entirely
```

`attach_lease` in consumers is fragile (`get_object()` null CRITICAL; identity walk). Returning `args = ("t", handle)` + `new T()` + `set_data(gsr-lease-id)` duplicates every live getter.

Object arrays already call `parse_object` per element — one stamp site covers both.

---

## Proposed change `🔷` `⏳`

### In `libocrpc` (this repo)

1. **✔️** **🔷** In `Bin.Stream.parse_object` live-handle path: after `proxies.set(handle, live)`, stamp the handle on `live` with qdata — `set_data("rpc-lid", (void*) handle)`.
2. **✔️** **🔷** Document the key on `Client.proxies` and in `docs/bin-rpc-protocol.md` (decode stamps lease; `proxies` remains authoritative for notify).
3. **✔️** **🔷** Test: round-trip `live_handles` object in `Response.retval` → client object has qdata handle == server `export` id.

**🚫** Do not require consumers to pack lease ids in `args` for ordinary live returns.

### Optional follow-on (same plan or tiny child)

4. **⏳** **💩** Prefer live-handle **write** when `live_handles` and the object is already in `connection.lease_ids`, even if the type is also `Serializable` (today Serializable wins and sends a property dump). Confirm with a test before flipping — snapshot types must keep Serializable encode.

### 1. `libocrpc/Bin/Stream.vala` — `parse_object`: stamp lease qdata

**Why:** Decode already binds `Client.proxies`. Callers that hold the object need the handle without walking that map.

**Where:** `parse_object`, live-handle branch after `proxies.set`; plus the method docblock.

**Depends on:** none.

**ℹ️** `parse_object_array` already calls `parse_object` per element — no second stamp site.

##### Part 1 — Stamp after `proxies.set`

#### Add — after `this.client.proxies.set((int) handle, live);` — qdata handle on the proxy

```vala
				live.set_data("rpc-lid", (void*) handle);
```

##### Part 2 — Method docblock

**Where:** `parse_object` docblock, after the anonymous nested-object sentence, before `@param object_type`.

#### Add — after “when that type implements {@link Serializable}.” — live-handle decode + qdata

```vala
		 * When {@link Client.live_handles} is on and the type is not
		 * {@link Serializable}, the body is a uint64 handle then
		 * {@link TOKEN_END}. Decode constructs the proxy, stores it in
		 * {@link Client.proxies}, and stamps the handle as qdata
		 * ''rpc-lid'' with value ''(void*) handle''.
```

### 2. `libocrpc/Client.vala` — `proxies` docblock: decode stamps lease

**Why:** The key is public contract for consumers (`(uint64) get_data("rpc-lid")`).

**Where:** `proxies` property docblock, after the unbound-ids sentence, before `== Example ==`.

**Depends on:** §1.

#### Add — after “Unbound ids still emit {@link notification}.” — qdata note

```vala
		 * {@link Bin.Stream.parse_object} also inserts the decoded
		 * proxy here and stamps the wire handle as qdata key
		 * ''rpc-lid'' (''(void*) handle''). This map stays
		 * the notify table; qdata is for callers that hold the object
		 * without walking keys.
```

### 3. `docs/bin-rpc-protocol.md` — live-handle decode stamps qdata

**Why:** Wire doc already points live bodies at `StreamValue` / `parse_object`. Name the client qdata key there.

**Where:** retval / GIR C return paragraph that ends “Live-handle bodies follow `StreamValue` / `parse_object`.”

**Depends on:** §1.

#### Add — after that live-handle sentence — client qdata key

```markdown
Client `parse_object` stamps that handle on the proxy as qdata
`set_data("rpc-lid", (void*) handle)`. Consumers read
`(uint64) get_data("rpc-lid")`. `Client.proxies` remains the
notify table.
```

### 4. `tests/rpc/gi-test.vala` — `Gio-Menu.new` retval has lease qdata

**Why:** That call already round-trips a live object on `Response.retval` and records the handle from `proxies`.

**Where:** `run_rpc_test`, after the `foreach` that sets `lease_id` from `rpc.proxies.keys`, before `response = null`.

**Depends on:** §1.

#### Add — after the `foreach` that assigns `lease_id` — qdata matches export id

```vala
			this.check(
				command_line,
				(uint64) response.retval.get_object().get_data("rpc-lid") == lease_id,
				"proxy missing lease qdata"
			);
```

---

## Consumer note (gnome-shell-rpc) `ℹ️`

After this lands:

- `Ui.Display.get_*` can reply `retval = val("o", exported)` again.
- Overrides can `return (T) response.retval.get_object()` and read lease from `(uint64) get_data("rpc-lid")` (map key → `gsr-lease-id` in `Runtime.attach_lease` if they keep a local name).
- **🚫** New `args`/`t` + manual stub rebuild for live returns.

---

## Out of scope

- **🚫** Changing JSON/HTTP live semantics.
- **🚫** gnome-shell-rpc edits inside this plan (consumer migrates after release/bump).
- **🚫** Inventing leases for non-`live_handles` / Serializable snapshot rows (`Ui.Window` list snapshots stay property streams).
- **🚫** New helper, new `const` for the key, or a second stamp site in `parse_object_array`.

---

## Done when

- **🔷** **✔️** Live decode stamps lease handle on the proxy.
- **🔷** **✔️** Test covers retval live object round-trip.
- **ℹ️** Consumer can drop `args`/`t` live-return workarounds after depending on this `libocrpc`.
