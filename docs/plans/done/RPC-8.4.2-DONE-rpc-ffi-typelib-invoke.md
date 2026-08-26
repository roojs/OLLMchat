# 8.4.2 — Typelib register and remote `new`

> `docs/plans/RPC-1.0-summary.md` is **not** updated for this sub-plan until it is done and archived.

**Status:** `✔️` agent-done — awaiting user **✅**

**Parent:** [`RPC-8.4-rpc-positional-values-and-ffi.md`](RPC-8.4-rpc-positional-values-and-ffi.md)

**Depends on:** [`8.4.1`](RPC-8.4.1-DONE-rpc-positional-values.md) (`Request.values` as `GLib.Value`s).

**Next:** [`8.4.3`](RPC-8.4.3-DONE-rpc-ffi-typelib-method.md). Leftovers: [`8.4.4`](../RPC-8.4.4-rpc-invoke-errors.md) (invoke errors), [`8.4.5`](RPC-8.4.5-DONE-rpc-ffi-leftovers.md) (boxed / GObject `INTERFACE` / invoke return), [`8.4.6-DONE`](RPC-8.4.6-DONE-rpc-ffi-leftovers.md) (float, array, width).

**Already in tree:** `Connection.export` / leases (`Live.Remote` ref/unref), client `proxies` (`tests/rpc/live-handles-test.vala`, `tests/rpc/proxies-test.vala`).

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

---

## Purpose

- **🔷** `✔️` Phase 1 — load the typelib and register every object type.
- **🔷** `✔️` Phase 2 — RPC `new` on that type (no handle): server constructs, leases, returns a handle.
- **🔷** `✔️` Land Phase 1 and Phase 2 together. Register-only is not a shippable slice; the first proof is `Gio-Menu.new`.
- **🔷** `✔️` Handled objects on the RPC path do **not** dump properties on the wire. If the client wants properties, it asks later (not this plan).
- **ℹ️** Method-on-handle is [`8.4.3`](RPC-8.4.3-DONE-rpc-ffi-typelib-method.md).
- **ℹ️** Existing `Request.register` / `call_`* handlers (ollmfilesd) stay. Typelib types are a second dispatch path when the prefix is not a handler singleton.

Intro: edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

---

## Shape

- **🔷** Wire method: `{alias}.{method}` — alias is typelib namespace + hyphen + object name (`Gio-Menu.new`).
- **🔷** Phase 2 `new` is type-level: **no handle** on the request. Constructor args (if any) are `Request.values` in GIR order.
- **ℹ️** `Request.dispatch` today only looks up `handlers` singletons and emits `call_`*. Typelib types are not singletons — `new Gi(request).dispatch()` when the prefix is in `Gi.types`.
- **🔷** `register` and `types` stay static. Per-call: `new Gi(request)` then `dispatch()`. `dispatch` finds the `FunctionInfo` and routes constructors to `dispatch_new`. Non-constructors return false ([`8.4.3`](RPC-8.4.3-DONE-rpc-ffi-typelib-method.md) `dispatch_function`). `convert` is one TypeTag slot; the arg walk stays in `dispatch_new`.
- **🔷** Windows/Android compile `windows/Gi.vala` (meson `use_unix_sockets`, same swap as `ClientBoot`). No `#if` in `Gi.vala`. Stub `dispatch` returns false.
- **🔷** A handled object on the wire is type alias + handle id, **not** a property snapshot.
- **🔷** Pack `GI.Argument`s from **GIR**, not from `GValue.type()`.
  - Schema: `CallableInfo.get_n_args` / `ArgInfo` / `TypeInfo.get_tag`.
  - Payload: `this.request.values` in that order. `dispatch_new` walks GIR args; `convert` fills one `in_args` slot from `this.request.values`.
  - `gobject-introspection-1.0` has no `g_value_to_gi_argument`. Filling the union from the tag is what gjs / pygobject / the gnome-shell-rpc generator do.
  - `TypeInfo.argument_from_hash_pointer` is GList/GHash stuffed pointers, not this.
- **🔷** `Stream` does not grow `lease_ids` / `proxies`, and this path does not copy `live_handles` onto `Stream`. Unowned refs to the owners: `Connection` (server encode) and `Client` (client decode). Encode/decode read `connection.live_handles` / `client.live_handles`.

**Dispatch order:**

- **ℹ️** If `handlers` has the prefix → today's `call_`* (ollmfilesd). Unchanged.
- **🔷** Else `new Gi(this).dispatch()` — this plan: constructors only. Stub returns false.
- **ℹ️** Else today's critical (unknown handler).

---

## Phase 1 — Load typelib, register object types

- **🔷** `⏳` `GI.Repository.require` the namespace (installed `Gio-2.0` is the first consumer).
- **🔷** `⏳` Walk `get_n_infos` / `get_info`. Register each `GI.InfoType.OBJECT` that has a `GType`.
- **🔷** `⏳` Wire alias: `namespace + "-" + info.get_name()` (`Gio-Menu`, `Gio-SimpleAction`).
- **🔷** `⏳` `Bin.register(alias, gtype)` so the type can appear on the wire later.
- **🔷** `⏳` Keep a `Gi.types` map (`alias` → `GLib.Type`) for Phase 2 dispatch (and [`8.4.3`](RPC-8.4.3-DONE-rpc-ffi-typelib-method.md)). Skip `GType.INVALID`. Skip a second `Bin.register` of the same alias (`alias_to_gtype.has_key`).
- **🔷** No Phase 1 test. Register-only `has_key` asserts do not prove RPC. First smoke is Phase 2 `Gio-Menu.new`.
- **ℹ️** `gobject-introspection-1.0` is unix-only (same dep gate as `Live/`). Meson compiles `Gi.vala` on unix and `windows/Gi.vala` otherwise (Android included) — same swap as `ClientBoot`. No `#if` in either file.
- **ℹ️** Vala `GI.ObjectInfo` does not inherit `RegisteredTypeInfo` in the vapi. C still is one struct — cast to `GI.RegisteredTypeInfo` and call `get_g_type()` (runs `type_init`). If valac rejects the cast, `GLib.Type.from_name(obj.get_type_name())` after require.

### 1. `libocrpc/meson.build` — `gobject-introspection-1.0` + `Gi.vala`

**Why:** `GI.Repository` is not in gio. Unix gets the library and `Gi.vala`. Windows/Android get `windows/Gi.vala` (no GI pkg).

**Where:** existing `if use_unix_sockets` dep block, and next to `client_boot_src`.

**Depends on:** none.

#### Add — inside `if use_unix_sockets` after `ocrpc_deps += dependency('gio-unix-2.0')` — GI library + vapi

```meson
  ocrpc_deps += dependency('gobject-introspection-1.0')
  ocrpc_vapi_pkgs += '--pkg=gobject-introspection-1.0'
  ocrpc_vapi_gen_pkgs += [
    '--pkg', 'gobject-introspection-1.0',
  ]
```

#### Add — after `client_boot_src = files(['windows/ClientBoot.vala'])` — stub Gi by default

```meson
gi_src = files(['windows/Gi.vala'])
```

#### Add — inside `if use_unix_sockets` after `client_boot_src = files(['ClientBoot.vala'])` — unix Gi

```meson
  gi_src = files(['Gi.vala'])
```

#### Add — after `ocrpc_core_src += live_src` — compile the chosen Gi file

```meson
ocrpc_core_src += gi_src
```

---

### 2. `docs/meson.build` — valadoc input

**Why:** Public `Gi` (unix sources) needs the same source list as the library. Valadoc is unix — not `windows/Gi.vala`.

**Where:** libocrpc sources block, immediately after `'../libocrpc/CallParam.vala',`.

**Depends on:** none.

#### Add — after `'../libocrpc/CallParam.vala',` — valadoc source

```meson
    '../libocrpc/Gi.vala',
```

---

### 3. `libocrpc/Gi.vala` — unix `register` + `dispatch` / `dispatch_new` / `convert`

**Why:** All GI work stays on `Gi`. `register` / `types` are static. Each call is `new Gi(request)`. `dispatch` finds the callable and routes. `dispatch_new` constructs. `convert` is only the TypeTag fill of one slot (the loop stays in `dispatch_new`). `dispatch_function` is [`8.4.3`](RPC-8.4.3-DONE-rpc-ffi-typelib-method.md) — do not add it here. Windows/Android use §3b.

**Where:** new file. Unix-only in meson (§1). Needs `gobject-introspection-1.0`.

**Depends on:** §1.

#### Add — create `libocrpc/Gi.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc
{
	/**
	 * Register GObject types from a typelib and apply RPC calls to them.
	 *
	 * {@link register} requires the namespace, then maps every object
	 * type to a wire alias ({@link Bin.register}) so a client can call
	 * ''Alias.new'' with no handle, then other methods on the lease.
	 * {@link Request.dispatch} constructs {@link Gi} with the inbound
	 * {@link Request} and calls {@link dispatch}. That method finds the
	 * typelib callable and routes constructors to {@link dispatch_new}.
	 * Windows and Android compile ''windows/Gi.vala'' instead (meson,
	 * not ''#if'').
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Gi.register("Gio", "2.0");
	 * var gi = new OLLMrpc.Gi(req);
	 * gi.dispatch();
	 * }}}
	 */
	public class Gi : GLib.Object
	{
		/**
		 * Wire alias → GType for typelib objects (''Gio-Menu'').
		 */
		public static Gee.HashMap<string, GLib.Type> types;

		/**
		 * Inbound call this instance applies. Owner of method / values /
		 * connection — not copied onto {@link Gi}.
		 */
		public Request request { get; construct; }

		public GI.Argument[] in_args = {};

		public GI.Argument[] out_args = {};

		public Gi(Request request)
		{
			GLib.Object(request: request);
		}

		/**
		 * Require ''ns'' / ''version'' and register each object GType.
		 *
		 * Alias is ''ns-Name'' (hyphen, same style as ''RPC-Live-Remote'').
		 * Skips infos that are not objects, or have no GType. A second
		 * register of the same alias is a no-op.
		 *
		 * @param ns typelib namespace (''Gio'', ''Meta'')
		 * @param version typelib version (''2.0'', ''16'')
		 * @throws GLib.Error when {@link GI.Repository.require} fails
		 */
		public static void register(string ns, string version) throws GLib.Error
		{
			if (types == null) {
				types = new Gee.HashMap<string, GLib.Type>();
			}
			GI.Repository.get_default().require(ns, version, 0);
			var n = GI.Repository.get_default().get_n_infos(ns);
			for (var i = 0; i < n; i++) {
				var info = GI.Repository.get_default().get_info(ns, i);
				if (info.get_type() != GI.InfoType.OBJECT) {
					continue;
				}
				var registered = (GI.RegisteredTypeInfo) info;
				var gtype = registered.get_g_type();
				if (gtype == GLib.Type.INVALID) {
					continue;
				}
				var alias = ns + "-" + info.get_name();
				if (Bin.alias_to_gtype != null && Bin.alias_to_gtype.has_key(alias)) {
					types.set(alias, gtype);
					continue;
				}
				Bin.register(alias, gtype);
				types.set(alias, gtype);
			}
		}

		/**
		 * Find the typelib callable and route it.
		 *
		 * Prefix must be in {@link types}. Looks up
		 * {@link GI.ObjectInfo.find_method} for the wire method name.
		 * Constructors go to {@link dispatch_new}. Other callables
		 * return false until 8.4.3 ''dispatch_function''. Missing
		 * method replies METHOD_NOT_FOUND. Prefix not in {@link types}
		 * returns false so {@link Request.dispatch} can fall through.
		 *
		 * @return true when this call was a GI path
		 */
		public bool dispatch()
		{
			if (types == null) {
				return false;
			}
			var dot = this.request.method.index_of_char('.');
			var object_name = this.request.method[0:dot];
			var method_name = this.request.method.substring(dot + 1);
			if (!types.has_key(object_name)) {
				return false;
			}
			var info = GI.Repository.get_default().find_by_gtype(
				types.get(object_name));
			var fn = ((GI.ObjectInfo) info).find_method(method_name);
			if (fn == null) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.METHOD_NOT_FOUND);
				return true;
			}
			if ((fn.get_flags() & GI.FunctionInfoFlags.IS_CONSTRUCTOR) != 0) {
				return this.dispatch_new(fn);
			}
			return false;
		}

		/**
		 * Construct, export, and reply (Phase 2 ''Alias.new'').
		 *
		 * Arg walk stays here. Each IN slot calls {@link convert}.
		 *
		 * @param fn constructor from {@link dispatch}
		 * @return true — this method always replies
		 */
		public bool dispatch_new(GI.FunctionInfo fn)
		{
			if (!this.request.connection.live_handles) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			var n_in = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (arg.get_direction() != GI.Direction.IN) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
				n_in++;
			}
			if (n_in != this.request.values.size) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			this.in_args = new GI.Argument[n_in];
			this.out_args = new GI.Argument[0];
			var vi = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (!this.convert(arg, vi)) {
					return true;
				}
				vi++;
			}
			var ret = GI.Argument();
			try {
				fn.invoke(this.in_args, this.out_args, out ret);
			} catch (GLib.Error e) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INTERNAL_ERROR);
				return true;
			}
			var created = (GLib.Object) ret.v_pointer;
			this.request.connection.export(created);
			var response = new Response();
			response.result.add(created);
			this.request.reply(response);
			return true;
		}

		/**
		 * Fill one {@link in_args} slot from {@link request}.values.
		 *
		 * Uses ''arg'' TypeTag. Reads {@link request}.values at ''vi'' —
		 * does not copy request fields onto {@link Gi}. Unknown tags
		 * reply INVALID_PARAMS.
		 *
		 * @param arg one IN argument from the callable
		 * @param vi index in {@link in_args} and {@link request}.values
		 * @return false when this method already replied an error
		 */
		public bool convert(GI.ArgInfo arg, int vi)
		{
			var val = this.request.values.get(vi);
			switch (arg.get_type().get_tag()) {
				case GI.TypeTag.BOOLEAN:
					this.in_args[vi].v_boolean = val.get_boolean();
					return true;

				case GI.TypeTag.INT32:
					this.in_args[vi].v_int32 = val.get_int();
					return true;

				case GI.TypeTag.INT64:
					this.in_args[vi].v_int64 = val.get_int64();
					return true;

				case GI.TypeTag.UINT32:
					this.in_args[vi].v_uint32 = val.get_uint();
					return true;

				case GI.TypeTag.UINT64:
					this.in_args[vi].v_uint64 = val.get_uint64();
					return true;

				case GI.TypeTag.UTF8:
				case GI.TypeTag.FILENAME:
					this.in_args[vi].v_string = val.get_string();
					return true;

				default:
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return false;
			}
		}
	}
}
```

---

### 3b. `libocrpc/windows/Gi.vala` — stub `register` / `dispatch`

**Why:** `Request.dispatch` always does `new Gi(this).dispatch()`. Meson compiles this file when `use_unix_sockets` is false (Windows and Android). Same public surface, no GI types, no `#if`.

**Where:** new file, next to `windows/ClientBoot.vala`.

**Depends on:** §1.

#### Add — create `libocrpc/windows/Gi.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMrpc
{
	/**
	 * Compile-only {@link Gi} shell when typelib invoke is not built.
	 *
	 * {@link register} is a no-op. {@link dispatch} always returns false
	 * so {@link Request.dispatch} stays on handler singletons.
	 */
	public class Gi : GLib.Object
	{
		public static Gee.HashMap<string, GLib.Type> types;

		public Request request { get; construct; }

		public Gi(Request request)
		{
			GLib.Object(request: request);
		}

		public static void register(string ns, string version) throws GLib.Error
		{
		}

		public bool dispatch()
		{
			return false;
		}
	}
}
```

---

## Phase 2 — RPC `new` (no handle)

Goal: the client can create a live object on the server and get a handle back. No instance methods yet. Implement with Phase 1.

**Call:**

- **🔷** `⏳` `method = "Gio-Menu.new"`.
- **🔷** No handle on the request (`new` is type-level).
- **🔷** `values` are constructor args in GIR order. First smoke is zero-arg (`values` empty).
- **ℹ️** Constructor-with-args (`Gio-SimpleAction.new`) / `INTERFACE` args → [`8.4.5`](RPC-8.4.5-DONE-rpc-ffi-leftovers.md).

**Server:**

- **🔷** `⏳` `Request.dispatch`: if `handlers` has the prefix, today's `call_`*. Else `new Gi(this).dispatch()`. No GI types and no `#if` in `Request.vala`.
- **🔷** `⏳` `dispatch`: prefix in `types`, `find_method`, constructors → `dispatch_new`. Non-constructor returns false ([`8.4.3`](RPC-8.4.3-DONE-rpc-ffi-typelib-method.md) `dispatch_function`). Missing method → `METHOD_NOT_FOUND`.
- **🔷** `⏳` `dispatch_new`: `live_handles`, walk IN args, `convert` per slot, invoke, export, reply.
- **🔷** Phase 2 tags in `convert`: `BOOLEAN`, `INT32`/`INT64`, `UINT32`/`UINT64`, `UTF8`/`FILENAME`. `INTERFACE` (GObject / boxed) → [`8.4.5`](RPC-8.4.5-DONE-rpc-ffi-leftovers.md). `ARRAY` / float / `GValue.transform` width → [`8.4.6-DONE`](RPC-8.4.6-DONE-rpc-ffi-leftovers.md).
- **🔷** `⏳` `this.request.connection.export(obj)` then `this.request.reply` with that object in `Response.result`.
- **🔷** `new` requires `this.request.connection.live_handles`. Otherwise `reply_error` (`INVALID_PARAMS`).
- **🔷** Windows/Android stub `dispatch` always returns false (handler-only path).

**Return (type + handle, no properties):**

- **ℹ️** `Response.result` today casts each row to `Bin.Serializable` and dumps properties. A Gio instance is not `Serializable`.
- **🔷** When `connection.live_handles` (encode) / `client.live_handles` (decode) is on and the row type is **not** `Serializable`: array header still `write_gtype`; each body is `uint64` handle (big-endian, `put_uint64` / `read_uint64`) + `TOKEN_END`. No property tags.
- **🔷** `Serializable` rows in the same `result` list stay on today's `bin_write` path (ollmfilesd unchanged).
- **🔷** Decode: `Object.new(gtype)`, `proxies.set(handle, obj)`, consume `TOKEN_END`. `parse_object` returns `GLib.Object` (root `parse()` still casts to `Serializable`).
- **🔷** `Stream.connection` is the same `Connection` that owns `lease_ids` (assigned when creating `bin`). `Stream.client` is the same `Client` that owns `proxies`. Unowned refs — do not copy the maps onto `Stream`.

**Smoke** (first test binary — `tests/rpc/gi-test.vala` + meson `test-rpc-gi`):

- **🔷** `⏳` Listen + client with `live_handles = true`. `Gi.register("Gio", "2.0")` once (same process). `RPC-Daemon.hello` like `values-test.vala`.
- **🔷** `⏳` `Gio-Menu.new`. Assert `response.result.size == 1`, `rpc.proxies.size == 1`, handle ≠ 0, proxy is the result object.
- **🔷** `⏳` Do **not** call a method on it yet — that is [`8.4.3`](RPC-8.4.3-DONE-rpc-ffi-typelib-method.md).

This plan does **not** add `Request.lease_id` — that is [`8.4.3`](RPC-8.4.3-DONE-rpc-ffi-typelib-method.md).

---

### 4. `libocrpc/Request.vala` — `dispatch()`: `new Gi(this).dispatch()`

**Why:** Handler singletons stay here. GI construct/invoke is `new Gi(this).dispatch()` (stub class on Windows/Android).

**Where:** `dispatch()`, after `object_name` / `method_name` are set, replace the handler-only tail.

**Depends on:** Phase 1 §3 / §3b. Smoke needs §5–10 for the handle on the wire.

##### Keep

```vala
			var object_name = this.method[0:dot];
			var method_name = this.method.substring(dot + 1);

```

##### Remove

```vala
			if (!handlers.has_key(object_name)) {
				GLib.critical(
					"RPC dispatch: no handler for '%s' (%s)",
					object_name,
					this.method
				);
				return false;
			}
			var handler = handlers.get(object_name);
			var signal_name = "call_" + method_name.replace(".", "_");
			if (GLib.Signal.lookup(signal_name, handler.get_type()) == 0) {
				GLib.critical(
					"RPC dispatch: no signal call_%s on %s for %s",
					method_name.replace(".", "_"),
					object_name,
					this.method
				);
				return false;
			}
			GLib.debug("emit %s id=%d", signal_name, this.id);
			GLib.Signal.emit_by_name(handler, signal_name, this);
			GLib.debug("emit returned id=%d", this.id);
			return true;
		}
```

##### Replace with

```vala
			if (handlers != null && handlers.has_key(object_name)) {
				var handler = handlers.get(object_name);
				var signal_name = "call_" + method_name.replace(".", "_");
				if (GLib.Signal.lookup(signal_name, handler.get_type()) == 0) {
					GLib.critical(
						"RPC dispatch: no signal call_%s on %s for %s",
						method_name.replace(".", "_"),
						object_name,
						this.method
					);
					return false;
				}
				GLib.debug("emit %s id=%d", signal_name, this.id);
				GLib.Signal.emit_by_name(handler, signal_name, this);
				GLib.debug("emit returned id=%d", this.id);
				return true;
			}
			if (new Gi(this).dispatch()) {
				return true;
			}
			GLib.critical(
				"RPC dispatch: no handler for '%s' (%s)",
				object_name,
				this.method
			);
			return false;
		}
```

---

### 5. `libocrpc/Bin/Stream.vala` — unowned `connection` / `client`

**Why:** Live encode looks up the handle on {@link Transport.Connection.lease_ids}. Live decode binds {@link Client.proxies}. Point at those owners. Do not copy the maps onto `Stream` (cycle-safe: `unowned`).

**Where:** class body, immediately after `live_handles`.

**Depends on:** none.

#### Add — after `public bool live_handles { get; set; default = false; }` — owners

```vala
		/**
		 * Server {@link Stream}: the {@link OLLMrpc.Transport.Connection}
		 * that owns {@link OLLMrpc.Transport.Connection.lease_ids}.
		 */
		public unowned OLLMrpc.Transport.Connection connection { get; set; }

		/**
		 * Client {@link Stream}: the {@link OLLMrpc.Client} that owns
		 * {@link OLLMrpc.Client.proxies}.
		 */
		public unowned OLLMrpc.Client client { get; set; }
```

---

### 6. `libocrpc/Bin/Stream.vala` — `parse()`: root still `Serializable`

**Why:** `parse_object` returns `GLib.Object` for live Menu rows. Root envelopes stay `Serializable`.

**Where:** `parse()`, the `return this.parse_object();` line.

**Depends on:** §7.

##### Keep

```vala
			if (b != (uint8) GLib.Type.OBJECT) {
				throw new StreamError.PROTOCOL(
					"expected object type byte, got 0x%02X",
					b
				);
			}
```

##### Remove

```vala
			return this.parse_object();
		}
```

##### Replace with

```vala
			return (Serializable) this.parse_object();
		}
```

---

### 7. `libocrpc/Bin/Stream.vala` — `parse_object`: live handle body

**Why:** Gio types are not `Serializable`. Live body is handle + `TOKEN_END`.

**Where:** `parse_object` signature and body after `decode_type` is set.

**Depends on:** §5.

##### Part 1 — signature

##### Remove

```vala
		public Serializable parse_object(
```

##### Replace with

```vala
		public GLib.Object parse_object(
```

##### Part 2 — live body after `decode_type`

##### Keep

```vala
			if (wire_gtype == typeof(GLib.Object)
				&& expected_type != GLib.Type.INVALID
				&& expected_type.is_a(typeof(Serializable))) {
				decode_type = expected_type;
			}
```

##### Remove

```vala
			var obj = (Serializable) GLib.Object.new(decode_type);
			obj.bin_read(this);
			return obj;
		}
```

##### Replace with

```vala
			if (this.client.live_handles && !decode_type.is_a(typeof(Serializable))) {
				var handle = this.in_stream.read_uint64();
				var live = GLib.Object.new(decode_type);
				this.client.proxies.set((int) handle, live);
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

### 8. `libocrpc/Response.vala` — `bin_write_prop` `result`: live handle body

**Why:** `Gio.Menu` cannot `bin_write`. Handle-only body when not `Serializable`.

**Where:** `bin_write_prop`, the `foreach` over `this.result`.

**Depends on:** §5.

##### Keep

```vala
					foreach (var child in this.result) {
```

##### Remove

```vala
						((Bin.Serializable) child).bin_write (ctx);
					}
```

##### Replace with

```vala
						if (ctx.connection.live_handles
							&& !child.get_type().is_a(typeof(Bin.Serializable))) {
							var ptr = (uint64) (void*) child;
							ctx.out_stream.put_uint64(
								(uint64) ctx.connection.lease_ids.get(
									(int) (ptr >> 32)).get((int) ptr));
							ctx.out_stream.put_uint16(Bin.Stream.TOKEN_END);
							continue;
						}
						((Bin.Serializable) child).bin_write (ctx);
					}
```

---

### 9. `libocrpc/Transport/Connection.vala` — `start()`: give Stream the connection

**Why:** Result encode reads `lease_ids` / `live_handles` on this `Connection`, not copies on `Stream`.

**Where:** `start()`, the `new Bin.Stream` initializer.

**Depends on:** §5.

##### Remove

```vala
				this.bin = new Bin.Stream(in_stream, out_stream, true) {
					live_handles = this.live_handles
				};
```

##### Replace with

```vala
				this.bin = new Bin.Stream(in_stream, out_stream, true) {
					connection = this
				};
```

---

### 10. `libocrpc/Client.vala` — `connect()`: give Stream the client

**Why:** Live decode binds `proxies` / `live_handles` on this `Client`, not copies on `Stream`.

**Where:** `connect()`, the `new Bin.Stream` initializer (`this.bin = new Bin.Stream(this.input, this.output)`).

**Depends on:** §5.

##### Remove

```vala
			this.bin = new Bin.Stream(this.input, this.output) {
				live_handles = this.live_handles
			};
```

##### Replace with

```vala
			this.bin = new Bin.Stream(this.input, this.output) {
				client = this
			};
```

---

### 11. `tests/meson.build` — `test-rpc-gi`

**Why:** First smoke is Phase 2 `Gio-Menu.new`, not register-only.

**Where:** immediately after the `test('test-rpc-values'` block, before `test_rpc_scm`.

**Depends on:** Phase 1 §1, §12.

#### Add — after the `test('test-rpc-values'` block — smoke executable + test

```meson
test_rpc_gi = executable('test-rpc-gi',
  'rpc/gi-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
    dependency('gobject-introspection-1.0'),
    dependency('gio-unix-2.0'),
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  vala_args: rpc_test_vala_args + [
    '--pkg=gobject-introspection-1.0',
  ],
)
test('test-rpc-gi',
  test_rpc_gi,
  suite: 'rpc',
  timeout: 10,
)
```

---

### 12. `tests/rpc/gi-test.vala` — `Gio-Menu.new`

**Why:** Installed `Gio-2.0.typelib`, zero-arg constructor, live handle on the wire.

**Where:** new file.

**Depends on:** §4, §7, §8, §10, §11.

#### Add — create `tests/rpc/gi-test.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Typelib remote new smoke — Gio types are not shipped in libocrpc.
 */

namespace OLLMrpcTests
{
	public class Hello : GLib.Object
	{
		public signal void call_hello(OLLMrpc.Request request);

		construct
		{
			this.call_hello.connect((request) => {
				request.reply(new OLLMrpc.Response());
			});
		}
	}

	class TestRpcGi : RpcTestAppBase
	{
		public TestRpcGi()
		{
			base("com.roojs.ollmchat.test-rpc-gi");
		}

		protected override string get_app_name()
		{
			return "test-rpc-gi";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			OLLMrpc.Gi.register("Gio", "2.0");
			OLLMrpc.Bin.register("CallParam", typeof(OLLMrpc.CallParam));
			OLLMrpc.Request.register(
				"RPC-Daemon",
				new Hello(),
				typeof(OLLMrpc.CallParam)
			);
			var dir = GLib.DirUtils.make_tmp("ocrpc-gi-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var listen = new OLLMrpc.Transport.SocketListen(sock) {
				live_handles = true
			};
			this.check(command_line, listen.start(), "listen start failed");
			var rpc = new OLLMrpc.Client("", "", sock) {
				live_handles = true
			};
			var connected = false;
			var loop = new GLib.MainLoop();
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello"
			}, null, (obj, res) => {
				connected = rpc.connect.end(res);
				loop.quit();
			});
			loop.run();
			this.check(command_line, connected, "client connect failed");
			OLLMrpc.Response? response = null;
			var call_loop = new GLib.MainLoop();
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Gio-Menu.new"
			}, (obj, res) => {
				response = rpc.call.end(res);
				call_loop.quit();
			});
			call_loop.run();
			this.check(command_line, response.error == null, "new returned error");
			this.check(command_line, response.result.size == 1, "new returned no object");
			this.check(command_line, rpc.proxies.size == 1, "proxy not bound");
			foreach (var id in rpc.proxies.keys) {
				this.check(command_line, id != 0, "handle is 0");
				this.check(
					command_line,
					rpc.proxies.get(id) == response.result.get(0),
					"proxy is not result"
				);
			}
			rpc.disconnect();
			listen.stop();
		}
	}
}

int main(string[] args)
{
	return new OLLMrpcTests.TestRpcGi().run(args);
}
```

---

## LLM notes

- **🚫** Restore `Gi.call(target, method, values)` as the product API. Entry is `new Gi(request).dispatch()`.
- **🚫** Static `dispatch` / `dispatch_new` / `convert`. Those are instance methods. Static `register` and static `types` stay.
- **🚫** Fence `dispatch_function` here. That is [`8.4.3`](RPC-8.4.3-DONE-rpc-ffi-typelib-method.md).
- **🚫** Copy `Request` fields onto `Gi`. Hold `this.request` and read it.
- **🚫** Copy `lease_ids` / `proxies` / `live_handles` onto `Stream` for this path. Hold unowned `connection` / `client` and read the owner.
- **🚫** `#if G_OS_WIN32` / `ANDROID` in `Gi.vala`. Meson picks `Gi.vala` vs `windows/Gi.vala`.
- **🚫** Switch on `GValue.type()` to decide the `GI.Argument` field. GIR `TypeTag` is the schema; the value is the payload.
- **🚫** Treat `TypeInfo.argument_from_hash_pointer` / `type_tag_argument_from_hash_pointer` as a `GValue` converter. Those unstuff GList/GHash pointers.
- **🚫** Invent `g_value_to_gi_argument` — libgirepository 1.0 does not have one. Language bindings all fill the union from `TypeTag`.
- **🚫** GI types, `GI.Repository`, or `#if` in `Request.vala`. `Request.dispatch` only constructs `Gi` and calls `dispatch`.
- **🚫** Invoke instance methods here — `dispatch` returns false unless `IS_CONSTRUCTOR`.
- **🚫** Migrate ollmfilesd handlers off `Request.register`.
- **🚫** Move the GIR arg walk into `convert`. The loop stays in `dispatch_new`. `convert` is one TypeTag fill (`arg`, `vi`).
- **🚫** `Gi.pack` / `Gi.require` helpers. `require` stays inside `register`.
- **🚫** Allowlist inside `libocrpc`.
- **🚫** Send GObject properties for a handled result.
- **🚫** A Phase 1 test that only asserts `Gi.types.has_key` / bin aliases. First smoke is Phase 2 `Gio-Menu.new`.
- **ℹ️** Unowned `Stream.connection` / `client` have no default. If valac wants one, `default = null` on a nullable unowned — do not copy the maps.
- **ℹ️** `fn.invoke` `return_value` by value — leftover [`8.4.5`](RPC-8.4.5-DONE-rpc-ffi-leftovers.md). Constructor-with-args / `INTERFACE` also there. `ARRAY` / float / width → [`8.4.6-DONE`](RPC-8.4.6-DONE-rpc-ffi-leftovers.md). Invoke throw → client is [`8.4.4`](../RPC-8.4.4-rpc-invoke-errors.md).
- **ℹ️** Land Phase 1 §1–3b with Phase 2 §4–12. `ninja -C build tests/test-rpc-gi && build/tests/test-rpc-gi` (keep `test-rpc-values` and `test-rpc-live-handles` green).

