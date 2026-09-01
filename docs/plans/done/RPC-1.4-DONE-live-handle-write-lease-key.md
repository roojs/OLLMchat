# RPC-1.4 — Live-handle write uses wrong lease_ids key (handle 0)

> Landed. Index: [`RPC-1.0-summary.md`](../RPC-1.0-summary.md).

**Status:** **✔️** **done** — `libocrpc/Bin/StreamValue.vala`, `libocrpc/Live/Remote.vala`, `tests/rpc/gi-test.vala`.

**Prefix:** `RPC` (`libocrpc`) · see [`RPC-1.0-summary.md`](../RPC-1.0-summary.md)

**Unblocks:** gnome-shell-rpc nested boot — `RPC-Bootstrap.get_display` exports handle **3**, client receives **proxy[0]** / `rpc-lid=0` → `Meta-Display.get_context: no rpc-lid`.

**Related:** [`RPC-1.3-DONE-live-proxy-lease-on-decode.md`](RPC-1.3-DONE-live-proxy-lease-on-decode.md) (decode stamp `rpc-lid` is fine; **write** was broken).

**Follow-on:** [`RPC-1.5-DONE-base-level-function-dispatch.md`](RPC-1.5-DONE-base-level-function-dispatch.md).

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

---

## Purpose

- **🔷** **✔️** Live GObject encode must look up `connection.lease_ids` with the **same** low-half truncation as {@link Transport.Connection.export}.
- **🔷** **✔️** Never write lease handle **0** on the wire when the object was exported.

---

## Bug `ℹ️`

`Connection.export` truncates the pointer into locals:

```vala
var ptr = (uint64) (void*) gobject;
var hi = (int) (ptr >> 32);
var lo = (int) ptr;
```

`Bin.StreamValue` live write already has `ptr`, then nests the cast in the call:

```vala
ctx.connection.lease_ids.get((int) (ptr >> 32)).get((int) ptr)
```

Vala C codegen for that nested `(int) ptr` emits **`(gintptr) ptr`** (full 64-bit) as the inner map key, **not** `(gint) ptr`. Export stored under truncated `lo`; write misses → Gee default **0** → client `proxies[0]` / empty `rpc-lid`.

Evidence (gnome-shell-rpc nested):

```text
Bootstrap.get_display: export=3 lookup=3 ptr=0x… hi=25535 lo=-13402432 …
get_display: type=MetaDisplay rpc-lid=0 proxies=1
  proxy[0]=… same=true
```

**ℹ️** Same nested cast in `Live.Remote` unref `lease_ids…unset((int) ptr)` — fix there too or the reverse map leaks.

---

## Fix `🔷` `✔️`

### 1. `libocrpc/Bin/StreamValue.vala` — both live-handle write sites

**Why:** Force low-half truncation **before** `.get()`, same as `export`’s `lo`. Do **not** copy `export`’s `hi` local — `(int) (ptr >> 32)` is already fine nested.

**Where:** single-object live branch and `Gee.ArrayList` element live branch (both already have `var ptr = …`).

**Depends on:** none.

#### Replace with — after existing `var ptr = (uint64) (void*) live;` / `child` — truncated lo + miss throw

```vala
					var lo = (int) ptr;
					var id = ctx.connection.lease_ids.get((int) (ptr >> 32)).get(lo);
					if (id == 0) {
						throw new StreamError.PROTOCOL(
							"live object %s not in connection.lease_ids",
							live.get_type().name()
						);
					}
					ctx.out_stream.put_uint64((uint64) id);
					ctx.out_stream.put_uint16(Stream.TOKEN_END);
```

**ℹ️** Array branch: same, but type name from `child.get_type().name()`.

**🚫** No `hi` temp. **🚫** No auto-`export` inside `StreamValue`.

### 2. `libocrpc/Live/Remote.vala` — unref reverse-map unset

**Why:** Same nested `(int) ptr` bug; unset would miss the key.

**Where:** `call_unref` after `var ptr = (uint64) (void*) obj;`.

#### Replace with — truncate before unset

```vala
			var ptr = (uint64) (void*) obj;
			var lo = (int) ptr;
			request.connection.lease_ids.get((int) (ptr >> 32)).unset(lo);
```

### 3. Test

**✔️** **🔷** `tests/rpc/gi-test.vala` — `RPC-Daemon.actors` export → retval checks `rpc-lid != 0` and `proxies` bind (Menu.new path already covered by RPC-1.3).

---

## Done when

- **🔷** `✔️` Live write uses `lo = (int) ptr` then `.get(lo)` (not nested `(int) ptr`).
- **🔷** `✔️` Missing lease throws instead of writing 0.
- **🔷** `✔️` `Live.Remote` unref uses the same truncation.
- **🔷** `✔️` Round-trip test: client `rpc-lid` == server export id.
