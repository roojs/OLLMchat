# RPC-1.5 — Base-level (namespace) functions via bare `Clutter.` / `Meta.` wire prefix

> Landed. Index: [`RPC-1.0-summary.md`](../RPC-1.0-summary.md).

**Status:** **✔️** **done** — `libocrpc/Gi.vala` (`namespaces` + bare-prefix dispatch + no-lease `dispatch_function`).

**Prefix:** `RPC` (`libocrpc`) · see [`RPC-1.0-summary.md`](../RPC-1.0-summary.md)

**Unblocks:** gnome-shell-rpc nested boot — `Clutter.get_default_text_direction` (and peers: `Clutter.get_default_backend`, `Meta.prefs_*`, …) hit `RPC dispatch: no handler for 'Clutter'`.

**Related:** [`RPC-8.4.2-DONE-rpc-ffi-typelib-invoke.md`](RPC-8.4.2-DONE-rpc-ffi-typelib-invoke.md) (object Gi only: `Clutter-Actor.method`).

Edits are **Keep** / **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying. Apply **Parts in order** within each `###`. Each edited method is shown **top → bottom in full** (every line is either Keep, Remove, Replace, or Add) so early returns and fall-through are reviewable.

**Slugs read for proposed Vala:** `temporary-variables`, `this-prefix`, `reducing-nesting`, `defensive-code-null-checks`, `avoiding-nullable-types`, `method-names-new-methods`, `line-length-breaking`, `docblocks`, `underscore-prefix`, `property-initialization`, `gee-arraylist-access`, `brace-placement`, `agent-compliance-gate` (+ `docs/code-documentation.md`)

---

## Purpose

- **🔷** Typelib **namespace functions** (no object instance) dispatch on the Gi path.
- **🔷** Keep the wire the generator already emits:
  - **Namespace:** `Clutter.get_default_text_direction` — prefix before `.` is the library name.
  - **Object:** `Clutter-Actor.show` — hyphen joins library + type, then `.` + method.

**🚫** Do not change client wire names. **🚫** Do not invent a hyphen type for “the namespace.” **🚫** No new helper methods — extend `register`, `dispatch`, and `dispatch_function` only.

---

## Bug `ℹ️`

`Gi.register("Clutter", "16")` only fills `types` with **object/interface** aliases (`Clutter-Actor`, …).

`Gi.dispatch` requires `types.has_key(prefix)`. For `Clutter.get_default_text_direction`, prefix is `Clutter` → miss → CRITICAL `no handler for 'Clutter'`.

Even after a lookup fix, today’s `dispatch_function` rejects `!fn.is_method()` and requires a lease — namespace functions need **no** `this` and **lease_id** 0.

Client stubs are already generated; this is server `Gi` only.

---

## Fix

### 1. `libocrpc/Gi.vala` — `namespaces` field

**Why:** Remember which typelib namespaces `register` loaded, so bare `Clutter` / `Meta` are valid dispatch prefixes. **ℹ️** `ArrayList` (not `HashSet`) — only a handful of namespaces; matches the rest of the tree.

**Where:** class body, immediately after the `types` field.

**Depends on:** nothing.

#### Keep

```vala
		public static Gee.HashMap<string, GLib.Type> types;
```

#### Add — after the Keep line

Remember registered typelib namespace names for bare-prefix dispatch.

```vala

		/**
		 * Typelib namespace names from {@link register} (''Clutter'', ''Meta'').
		 *
		 * Bare wire prefix ''Clutter.get_default_text_direction'' looks up
		 * here; object aliases stay in {@link types} (''Clutter-Actor'').
		 */
		public static Gee.ArrayList<string> namespaces;
```

---

### 2. `libocrpc/Gi.vala` — `register()` (full method)

**Why:** Mark `ns` as a base-level dispatch prefix when the typelib is required.

**Where:** entire `register` method, top → bottom.

**Depends on:** §1 (`namespaces` field).

#### Keep

```vala
		/**
		 * Require ''ns'' / ''version'' and register each object or
		 * interface GType.
		 *
		 * Alias is ''ns-Name'' (hyphen, same style as ''RPC-Live-Remote'').
		 * Skips infos that are not objects or interfaces, or have no GType.
		 * A second register of the same alias is a no-op.
```

#### Add — after the “second register … no-op.” line, before `@param ns`

Document bare-prefix / `namespaces` behaviour.

```vala
		 * Also records ''ns'' in {@link namespaces} so bare
		 * ''Clutter.fn'' / ''Meta.fn'' dispatch to typelib namespace
		 * functions.
```

#### Keep

```vala
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
```

#### Add — after the `types` lazy-init block, before `require`

Init `namespaces` and add `ns` once.

```vala
			if (namespaces == null) {
				namespaces = new Gee.ArrayList<string>();
			}
			if (!namespaces.contains(ns)) {
				namespaces.add(ns);
			}
```

#### Keep

```vala
			GI.Repository.get_default().require(ns, version, 0);
			var n = GI.Repository.get_default().get_n_infos(ns);
			for (var i = 0; i < n; i++) {
				var info = GI.Repository.get_default().get_info(ns, i);
				if (info.get_type() != GI.InfoType.OBJECT
					&& info.get_type() != GI.InfoType.INTERFACE) {
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
```

---

### 3. `libocrpc/Gi.vala` — `dispatch()` (full method)

**Why:** Route bare `Clutter.*` via `Repository.find_by_name`; keep `Clutter-Actor.*` on `types` + `find_method`.

**Where:** entire `dispatch` method, top → bottom.

**Depends on:** §1, §2; §4 must land before namespace calls succeed (lookup alone still hits `!is_method`).

**ℹ️** Return meanings (unchanged contract):
- **`false`** — not a Gi prefix → `Request.dispatch` falls through / CRITICAL.
- **`true`** after `reply_error(METHOD_NOT_FOUND)` — this *was* a Gi prefix; method missing.
- **`true`** after `dispatch_new` / `dispatch_function` — handled.

**ℹ️** `find_by_name` is nullable in C despite the vapi; missing / non-`FUNCTION` → `METHOD_NOT_FOUND`.

#### Keep

```vala
		/**
		 * Find the typelib callable and route it.
		 *
```

#### Remove

```vala
		 * Prefix must be in {@link types}. Looks up
		 * {@link GI.ObjectInfo.find_method} for the wire method name.
		 * Constructors go to {@link dispatch_new}. Other callables
		 * go to {@link dispatch_function}. Missing
		 * method replies METHOD_NOT_FOUND. Prefix not in {@link types}
		 * returns false so {@link Request.dispatch} can fall through.
```

#### Replace with — Document `types` vs `namespaces` prefixes

```vala
		 * Prefix in {@link types} → object/interface
		 * {@link GI.ObjectInfo.find_method}. Prefix in {@link namespaces}
		 * → {@link GI.Repository.find_by_name} for a namespace function.
		 * Constructors go to {@link dispatch_new}. Other callables go to
		 * {@link dispatch_function}. Missing method replies
		 * METHOD_NOT_FOUND. Unknown prefix returns false so
		 * {@link Request.dispatch} can fall through.
```

#### Keep

```vala
		 *
		 * @return true when this call was a GI path
		 */
		public bool dispatch()
		{
```

#### Remove

```vala
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
			var fn = info.get_type() == GI.InfoType.INTERFACE
				? ((GI.InterfaceInfo) info).find_method(method_name)
				: ((GI.ObjectInfo) info).find_method(method_name);
			if (fn == null) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.METHOD_NOT_FOUND);
				return true;
			}
```

#### Replace with — Same `types == null` gate as today; object or namespace resolve; then shared tail

**ℹ️** After `register`, `types` and `namespaces` are both set. `namespaces == null` only means never registered — already covered by `types == null`. No extra null check on `namespaces` in `dispatch`.

**🚫** No ternary with method calls (Vala codegen bug) — `find_method` uses `if` / `else`.

```vala
			if (types == null) {
				return false;
			}
			var dot = this.request.method.index_of_char('.');
			var object_name = this.request.method[0:dot];
			var method_name = this.request.method.substring(dot + 1);
			GI.FunctionInfo fn;
			if (types.has_key(object_name)) {
				var info = GI.Repository.get_default().find_by_gtype(
					types.get(object_name));
				if (info.get_type() == GI.InfoType.INTERFACE) {
					fn = ((GI.InterfaceInfo) info).find_method(method_name);
				} else {
					fn = ((GI.ObjectInfo) info).find_method(method_name);
				}
				if (fn == null) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.METHOD_NOT_FOUND);
					return true;
				}
			} else {
				if (!namespaces.contains(object_name)) {
					return false;
				}
				var info = GI.Repository.get_default().find_by_name(
					object_name, method_name);
				if (info == null || info.get_type() != GI.InfoType.FUNCTION) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.METHOD_NOT_FOUND);
					return true;
				}
				fn = (GI.FunctionInfo) info;
			}
```

#### Keep

```vala
			this.skip_wire = new bool[fn.get_n_args()];
			this.in_slot = new int[fn.get_n_args()];
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (arg.get_type().get_tag() != GI.TypeTag.INTERFACE) {
					continue;
				}
				if (arg.get_type().get_interface().get_type() != GI.InfoType.CALLBACK) {
					continue;
				}
				if (arg.get_closure() >= 0) {
					this.skip_wire[arg.get_closure()] = true;
				}
				if (arg.get_destroy() >= 0) {
					this.skip_wire[arg.get_destroy()] = true;
				}
			}
			if ((fn.get_flags() & GI.FunctionInfoFlags.IS_CONSTRUCTOR) != 0) {
				return this.dispatch_new(fn);
			}
			return this.dispatch_function(fn);
		}
```

---

### 4. `libocrpc/Gi.vala` — `dispatch_function()` (full method)

**Why:** Namespace functions are not methods and have no lease; `n_in` starts at 0 and `convert` uses offset 0.

**Where:** entire `dispatch_function` method, top → bottom.

**Depends on:** §3 (namespace calls reach here).

**ℹ️** Early returns that stay **`true`** (always replied):
- no `live_handles`
- instance path: `lease_id == 0` / missing lease
- arg count mismatch / convert failure / invoke error / scalar failure

Namespace path skips the lease gates and never takes the old `!fn.is_method()` → `INVALID_PARAMS` branch.

#### Keep

```vala
		/**
```

#### Remove

```vala
		 * Invoke a typelib method on a leased object.
		 *
		 * Slot 0 is the instance. Remaining IN args use {@link convert}.
		 * The C return uses {@link scalar} into {@link Response.retval}.
		 * OUT / INOUT use {@link scalar} into {@link Response.args}.
```

#### Replace with — Cover instance and namespace callables

```vala
		 * Invoke a typelib callable (instance method or namespace function).
		 *
		 * When {@link GI.FunctionInfo.is_method}, slot 0 is the leased
		 * instance. Namespace functions use no lease and start IN at 0.
		 * Remaining IN args use {@link convert}. The C return uses
		 * {@link scalar} into {@link Response.retval}. OUT / INOUT use
		 * {@link scalar} into {@link Response.args}.
```

#### Keep

```vala
		 *
		 * @param fn non-constructor from {@link dispatch}
		 * @return true — this method always replies
		 */
		private bool dispatch_function(GI.FunctionInfo fn)
		{
			if (!this.request.connection.live_handles) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
```

#### Remove

```vala
			if (this.request.lease_id == 0) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			var id = (int) this.request.lease_id;
			if (!this.request.connection.leases.has_key(id)) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			if (!fn.is_method()) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			var n_in = 1;
```

#### Replace with — Gate lease on `instance`; `n_in` 0 for namespace fns

```vala
			var instance = fn.is_method();
			var id = 0;
			if (instance) {
				if (this.request.lease_id == 0) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
				id = (int) this.request.lease_id;
				if (!this.request.connection.leases.has_key(id)) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
			}
			var n_in = instance ? 1 : 0;
```

#### Keep

```vala
			var n_out = 0;
			var n_values = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				switch (arg.get_direction()) {
					case GI.Direction.IN:
						this.in_slot[i] = n_in;
						n_in++;
						if (this.skip_wire[i]) {
							break;
						}
						n_values++;
						break;

					case GI.Direction.OUT:
						n_out++;
						break;

					case GI.Direction.INOUT:
						this.in_slot[i] = n_in;
						n_in++;
						n_out++;
						if (this.skip_wire[i]) {
							break;
						}
						n_values++;
						break;
				}
			}
			if (n_values != this.request.args.size) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INVALID_PARAMS);
				return true;
			}
			this.in_args = new GI.Argument[n_in];
			this.out_args = new GI.Argument[n_out];
			this.boxed_keep.clear();
			this.glist_keep = {};
			this.gslist_keep = {};
```

#### Remove

```vala
			this.in_args[0].v_pointer = (void*) this.request.connection.leases.get(id);
```

#### Replace with — Skip `this` pointer when not a method

```vala
			if (instance) {
				this.in_args[0].v_pointer = (void*) this.request.connection.leases.get(id);
			}
```

#### Keep

```vala
			var out_i = 0;
			var vi = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (this.skip_wire[i]) {
					continue;
				}
				if (arg.get_direction() != GI.Direction.OUT) {
```

#### Remove

```vala
					if (!this.convert(arg, vi, 1)) {
						return true;
					}
```

#### Replace with — Offset 0 for namespace functions

```vala
					if (!this.convert(arg, vi, instance ? 1 : 0)) {
						return true;
					}
```

#### Keep

```vala
					vi++;
					continue;
				}
				if (!arg.is_caller_allocates() || arg.get_type().get_tag() != GI.TypeTag.INTERFACE) {
					out_i++;
					continue;
				}
				var kind = arg.get_type().get_interface().get_type();
				size_t n = 0;
				if (kind == GI.InfoType.STRUCT || kind == GI.InfoType.BOXED) {
					var si = (GI.StructInfo) arg.get_type().get_interface();
					if (!si.is_gtype_struct()) {
						n = si.get_size();
					}
				} else if (kind == GI.InfoType.UNION) {
					n = ((GI.UnionInfo) arg.get_type().get_interface()).get_size();
				}
				if (n == 0) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
				var buf = new uint8[n];
				var keep = new GLib.Bytes(buf);
				this.boxed_keep.add(keep);
				this.out_args[out_i].v_pointer = (void*) keep.get_data();
				out_i++;
			}
			var ret = GI.Argument();
			try {
				g_function_info_invoke(fn, this.in_args, this.out_args, out ret);
			} catch (GLib.Error e) {
				this.request.connection.reply_error(this.request,
					(int) RpcErrorCode.INTERNAL_ERROR, e);
				return true;
			}
			var response = new Response();
			var ret_type = fn.get_return_type();
			switch (ret_type.get_tag()) {
				case GI.TypeTag.VOID:
					break;

				case GI.TypeTag.GLIST:
				case GI.TypeTag.GSLIST:
					if (!this.scalar_list(ret_type, ret, response)) {
						return true;
					}
					break;

				case GI.TypeTag.GHASH:
					if (!this.scalar_hash(ret_type, ret, response)) {
						return true;
					}
					break;

				case GI.TypeTag.INTERFACE:
					var kind = ret_type.get_interface().get_type();
					if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
						var packed = new Gee.ArrayList<GLib.Value?>();
						if (!this.scalar(ret_type, ret, packed)) {
							return true;
						}
						response.retval = packed.get(0);
						break;
					}
					var created = (GLib.Object) ret.v_pointer;
					if (Bin.gtype_to_alias == null || !Bin.gtype_to_alias.has_key(created.get_type())) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return true;
					}
					this.request.connection.export(created);
					response.retval = OLLMrpc.val("o", created);
					break;

				default:
					var packed = new Gee.ArrayList<GLib.Value?>();
					if (!this.scalar(ret_type, ret, packed)) {
						return true;
					}
					response.retval = packed.get(0);
					break;
			}
			var oi = 0;
			for (var i = 0; i < fn.get_n_args(); i++) {
				var arg = fn.get_arg(i);
				if (arg.is_skip()) {
					continue;
				}
				if (arg.get_direction() == GI.Direction.IN) {
					continue;
				}
				if (!this.scalar(arg.get_type(), this.out_args[oi], response.args)) {
					return true;
				}
				oi++;
			}
			this.request.reply(response);
			return true;
		}
```

---

## Done when

- **🔷** `✔️` After `Gi.register("Clutter", "16")`, wire `Clutter.get_default_text_direction` routes through Gi (no hand `add_class("Clutter", …)`).
- **🔷** `✔️` `Clutter-Actor.*` unchanged (lease + `is_method` path).
- **🔷** `✔️` Nested gnome-shell-rpc past that CRITICAL (or a focused test) — consumer verify.
