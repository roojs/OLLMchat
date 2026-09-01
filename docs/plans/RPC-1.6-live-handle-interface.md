# RPC-1.6 — Live decode: `Live.Handle` + construct `rpc-lid`

> **`RPC-1.0-summary.md` is not updated until this plan is done and archived.**

**Status:** **✔️** agent-done — awaiting user **✅**

**Files:** `libocrpc/Live/Handle.vala`, `libocrpc/meson.build`, `libocrpc/Bin/Stream.vala`, `docs/bin-rpc-protocol.md`; test type `TestActor` implements `Handle` (existing live decode type).

**ℹ️** In-tree `gi-test` registers client `Handle` stubs (`TestMenu` / `TestFile`) for Gio wire aliases; `register_alias` maps stock server GTypes for encode.

**Prefix:** `RPC` (`libocrpc`) · see [`RPC-1.0-summary.md`](RPC-1.0-summary.md)

**Unblocks:** Consumers that need the wire lease **during** stub `construct` (inside `GLib.Object.new`), without a `Client` side-channel.

**Related:** [`done/RPC-1.3-DONE-live-proxy-lease-on-decode.md`](done/RPC-1.3-DONE-live-proxy-lease-on-decode.md) (qdata stamp after `Object.new` — keep).

**🚫** Stub generator / emitted class bodies — consumer repo. This plan only defines the interface and client decode path.

Edits are **Keep** / **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying. Each edited method is shown **top → bottom in full**.

**Slugs read for proposed Vala:** `temporary-variables`, `this-prefix`, `reducing-nesting`, `defensive-code-null-checks`, `method-names-new-methods`, `line-length-breaking`, `docblocks`, `underscore-prefix`, `property-initialization`, `brace-placement`, `agent-compliance-gate` (+ `docs/code-documentation.md`); Meson: `docs/build-rules.md`

---

## Purpose

- **🔷** Add {@link OLLMrpc.Live.Handle}: construct property `rpc_lid` so the lease is a normal GObject construct arg.
- **🔷** Live `parse_object` always constructs with `Object.new(decode_type, "rpc-lid", handle)` — every live proxy type implements {@link Live.Handle} (no fallback plain `Object.new`).
- **🔷** Keep RPC-1.3 `set_data("rpc-lid", …)` after construct (Runtime / existing readers).

**🚫** `Client.live_construct_lid` (or any pending field).
**🚫** Conditional `is_a(Handle)` / plain-`Object.new` branch on the live path.

---

## Why

Post-new qdata is too late for Vala `construct`. A field on `Client` works but is a hidden connection global.

Construct property: Stream always passes the handle into `Object.new`. Stub `construct` reads `this.rpc_lid`. No side channel.

Stubs already subclass real parents (`Actor`, …) → **interface**, not a base class. Every live wire type implements it — the live `parse_object` path has no non-Handle case.

---

## Fix

### 1. `libocrpc/Live/Handle.vala` — new file

**Why:** Contract for live proxy types that accept the lease at construct time.

**Where:** new file under `OLLMrpc.Live`.

**Depends on:** nothing.

#### Add — new file `libocrpc/Live/Handle.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc.Live
{
	/**
	 * Live proxy that takes the wire lease as a construct property.
	 *
	 * {@link Bin.Stream.parse_object} calls
	 * {@link GLib.Object.new} with ''rpc-lid'' when the decode type
	 * implements this. Stub {@code construct} reads {@link rpc_lid}
	 * (non-zero → already leased; skip ''Ns-Type.new'').
	 *
	 * == Example ==
	 *
	 * {{{
	 * public class Actor : GLib.Object, OLLMrpc.Live.Handle {
	 *     public uint64 rpc_lid { get; set construct; default = 0; }
	 *     construct {
	 *         if (this.rpc_lid != 0) {
	 *             return;
	 *         }
	 *         // else create remote peer and set rpc_lid / qdata
	 *     }
	 * }
	 * }}}
	 */
	public interface Handle : GLib.Object
	{
		/**
		 * Wire lease handle for this proxy (0 = none / local create).
		 *
		 * GObject name ''rpc-lid''. Set by live decode via
		 * {@link GLib.Object.new}.
		 */
		public abstract uint64 rpc_lid { get; set construct; }
	}
}
```

---

### 2. `libocrpc/meson.build` — compile `Handle.vala` on all hosts

**Why:** `Bin.Stream` always needs `typeof(Live.Handle)`. Not Unix-only live handlers.

**Where:** `live_src` initial `files([...])` (with `namespace.vala`).

**Depends on:** §1.

#### Keep

```meson
live_src = files(['Live/namespace.vala'])
```

#### Replace with — Always include Handle

```meson
live_src = files([
  'Live/namespace.vala',
  'Live/Handle.vala',
])
```

---

### 3. `libocrpc/Bin/Stream.vala` — `parse_object()` (full method)

**Why:** Pass `rpc-lid` into `Object.new` (live types are always {@link Live.Handle}).

**Where:** entire `parse_object` method, top → bottom.

**Depends on:** §1–§2.

#### Keep

```vala
		/**
		 * Read one object body after its {@link GLib.Type.OBJECT} type byte.
		 *
		 * When object_type is set (homogeneous object arrays), skip
		 * {@link read_gtype} and decode the property stream for that class.
		 * When wire {@link GLib.Object} is anonymous, decode as expected_type
		 * when that type implements {@link Serializable}.
		 *
		 * When {@link Client.live_handles} is on and the type is not
		 * {@link Serializable}, the body is a uint64 handle then
		 * {@link TOKEN_END}. Decode constructs the proxy, stores it in
		 * {@link Client.proxies}, and stamps the handle as qdata
		 * ''rpc-lid'' with value ''(void*) handle''.
```

#### Add — after the qdata sentence, before `@param object_type`

Document Handle construct property (required on live types).

```vala
		 * Live decode types implement {@link Live.Handle}; construction
		 * always passes ''rpc-lid'' into {@link GLib.Object.new}.
```

#### Keep

```vala
		 *
		 * @param object_type element class when already read from an array header
		 * @param expected_type GObject property type for anonymous nested objects
		 */
		public GLib.Object parse_object(
			GLib.Type object_type = GLib.Type.INVALID,
			GLib.Type expected_type = GLib.Type.INVALID
		) throws GLib.Error
		{
			var wire_gtype = object_type != GLib.Type.INVALID
				? object_type
				: this.read_gtype();
			var decode_type = wire_gtype;
			if (wire_gtype == typeof(GLib.Object)
				&& expected_type != GLib.Type.INVALID
				&& expected_type.is_a(typeof(Serializable))) {
				decode_type = expected_type;
			}
			if (!decode_type.is_a(typeof(Serializable)) && this.client.live_handles) {
				var handle = this.in_stream.read_uint64();
```

#### Remove

```vala
				var live = GLib.Object.new(decode_type);
				this.client.proxies.set((int) handle, live);
				live.set_data("rpc-lid", (void*) handle);
```

#### Replace with — Always construct with `rpc-lid`; stamp qdata

Live wire types implement {@link Live.Handle}. No plain-`Object.new` fallback.

```vala
				var live = GLib.Object.new(decode_type, "rpc-lid", handle);
				this.client.proxies.set((int) handle, live);
				live.set_data("rpc-lid", (void*) handle);
```

#### Keep

```vala
				if (this.in_stream.read_uint16() != TOKEN_END) {
					throw new StreamError.PROTOCOL(
						"expected end after live handle"
					);
				}
				return live;
			}
			var obj = (Serializable) GLib.Object.new(decode_type);
			obj.bin_read(this);
			return obj;
		}
```

---

### 4. `docs/bin-rpc-protocol.md` — client live decode note

**Why:** Document construct property path next to RPC-1.3 qdata.

**Where:** live-handle decode / `rpc-lid` paragraph.

#### Keep (verbatim today)

```
Client `parse_object` stamps that handle on the proxy as qdata
`set_data("rpc-lid", (void*) handle)`. Consumers read
`(uint64) get_data("rpc-lid")`. `Client.proxies` remains the
notify table.
```

#### Replace with — qdata + Handle construct property (required)

```
Client `parse_object` constructs the proxy with
`GLib.Object.new(type, "rpc-lid", handle)` (live types implement
`OLLMrpc.Live.Handle`) then stamps that handle as qdata
`set_data("rpc-lid", (void*) handle)`. Consumers read
`(uint64) get_data("rpc-lid")`. `Client.proxies` remains the
notify table.
```

---

## Consumer note `ℹ️` (not this repo)

Emitted stubs should `…, OLLMrpc.Live.Handle` and implement:

```vala
public uint64 rpc_lid { get; set construct; default = 0; }
```

In `construct`: if `this.rpc_lid != 0`, treat as live decode (skip `Ns-Type.new`); else create remote peer as today. **🚫** No hunks here.

---

## Done when

- **🔷** `✔️` `OLLMrpc.Live.Handle` exists and is in the all-host build.
- **🔷** `✔️` Live `parse_object` always uses `Object.new(..., "rpc-lid", handle)`.
- **🔷** `✔️` RPC-1.3 qdata stamp unchanged.
- **🚫** Generator / stub emit — out of scope (consumer must implement `Handle` on live types).
- **ℹ️** `gi-test` client stubs `TestMenu` / `TestFile` (+ `register_alias` for server Gio types).
