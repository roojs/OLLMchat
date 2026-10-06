# libocrpc discards the declared GObject wire type

**Status:** ⏳ open. Consumer FAIL gate: `gnome-shell-rpc/tests/call-sync-repro/declared-object-type-gate.vala`.

## Problem

A live GObject can have a registered public declared GType while its runtime object is a private subclass. libocrpc discards the declared GI/GValue type and serializes `object.get_type()`, so it treats the private implementation type as the wire schema and stops the connection.

The live consumer failure is `Clutter.Stage.get_actor_at_pos()`. Its GIR return type is `Clutter.Actor`, but picking an application surface produces a runtime `MetaSurfaceActorWayland`.

```text
18:24:19.571803  recv id=44697 method=Clutter-Stage.get_actor_at_pos
18:24:19.578952  connection write error:
                  Unregistered class type schema: MetaSurfaceActorWayland
18:24:19.616044  Client.vala:723: Unexpected early end-of-stream
```

The correct wire class is the declared public `Clutter.Actor`. The RPC layer must not know, register, audit, or hunt for Mutter's private implementation classes.

## FAIL gate

`gnome-shell-rpc/tests/call-sync-repro/declared-object-type-gate.vala` registers `GatePublic`, creates an unregistered `GatePrivate : GatePublic`, places that object in `GLib.Value(typeof(GatePublic))`, exports it, and returns it.

```text
connection write error: Unregistered class type schema: GatePrivate
Unexpected early end-of-stream
FAIL declared-object-type-gate: Client: disconnected
      (declared GatePublic was discarded)
```

The gate builds and exits 1 against the installed libocrpc. PASS requires the client to receive a leased `GatePublic` proxy and complete a later ping on the same connection.

```bash
meson compile -C build declared-object-type-gate
timeout 5 ./build/tests/call-sync-repro/declared-object-type-gate
```

## Root cause

`libocrpc/Gi.vala` already obtains the declared `GI.TypeInfo`, but object returns are reduced to generic `OLLMrpc.val("o", created)`. Typed signal and property `GValue`s retain their declared type, but `libocrpc/Bin/StreamValue.vala` replaces it with `object.get_type()`.

## Code proposal

Sections 1, 3, and 4 are in the tree. Object lists are not part of this change.

- A handler that already built `GLib.Value(typeof(GatePublic))` (the FAIL gate, a signal parameter, or `notify` via `pspec.value_type`) reaches `StreamValue.write`. That method calls `write_gtype(object.get_type())`, which throws `Unregistered class type schema: GatePrivate` and stops the connection.
- `Clutter.Stage.get_actor_at_pos` goes through `Gi.dispatch_function`. That method rejects `created.get_type()` (`MetaSurfaceActorWayland`) with `INVALID_PARAMS` (`-32602`) before it writes. `OLLMrpc.val("o", created)` would also stamp the `GValue` with the private type, so a `StreamValue`-only change leaves this call on the error-reply path.

The wire class has to be the type the caller already declared. The lease id stays the runtime instance.

- 🚫 No superclass walk, no `is_a` search, no `MetaSurfaceActorWayland` alias.
- 🚫 No edit to signal or property packing. Those `GValue`s already use the signal parameter type or `pspec.value_type`. `StreamValue` is what discards them.
- 🚫 No change to `dispatch_new`. A constructor's instance type is the public class that was invoked.
- 🚫 No change to IN lease checks. An inbound proxy's `get_type()` is already the registered wire class.
- 🚫 No change to the read path. `parse_object` already does `GLib.Object.new` on the type byte this write sends. `StreamValue.read` then wraps that proxy.
- 🚫 A `GValue` whose type is plain `GLib.Object` is not a wire schema. Manual `val("o", obj)` still means "use `obj.get_type()`", and that type must already be registered.
- 🚫 No `gtype_to_alias == null` test. `Bin.register` creates that map on the first alias. `write_reg_gtype` already calls `has_key` on it. A null map is a missing `register`, and `has_key` fails there.
- 🚫 No `set_data` / `get_data` side channel for a list element type.

### 1. `libocrpc/Bin/StreamValue.vala` — `write`: live object schema

**Why:** The gate, signals, and properties already put the public type on the `GValue`. The lease lookup keeps using the instance pointer.

**Where:** `write`, live-handle branch of `val.type().is_a(GLib.Type.OBJECT)`, the `write_gtype(live.get_type())` call. The `Serializable` test above it stays on `get_type()` so a property dump still follows the concrete class.

**Depends on:** none.

#### Remove

```vala
					var live = val.get_object();
					ctx.write_gtype(live.get_type());
```

#### Replace with

```vala
					var live = val.get_object();
					if (val.type() == typeof(GLib.Object)
							|| !gtype_to_alias.has_key(val.type())) {
						throw new StreamError.REGISTRATION("Unregistered declared class type schema: %s",
							val.type().name());
					}
					ctx.write_gtype(val.type());
```

`live` is still the pointer hashed into `lease_ids`. `GatePrivate` stored as `GatePublic` writes `Gate-Public` and the existing lease id.

### 2. Object lists — rejected

🚫 Hanging the element `GType` on the `Gee.ArrayList` with `set_data` is not approved. `scalar_list`, `scalar_hash`, and the array branch of `StreamValue.write` stay on `list.get(0).get_type()`.

### 3. `libocrpc/Gi.vala` — `dispatch_function`: one object return

**Why:** `has_key(created.get_type())` is the `-32602` on `get_actor_at_pos`. `val("o", created)` then throws away `fn.get_return_type()`. Pack a `GValue` of the GIR type and put the private instance in it. §1 writes that `GValue` type.

**Where:** `dispatch_function`, `GI.TypeTag.INTERFACE` return, object / interface arm.

**Depends on:** §1.

#### Remove

```vala
					var created = (GLib.Object) ret.v_pointer;
					if (created == null) {
						break;
					}
					if (Bin.gtype_to_alias == null || !Bin.gtype_to_alias.has_key(created.get_type())) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return true;
					}
					this.request.connection.export(created);
					response.retval = OLLMrpc.val("o", created);
					break;
```

#### Replace with

```vala
					var created = (GLib.Object) ret.v_pointer;
					if (created == null) {
						break;
					}
					var schema_type = ((GI.RegisteredTypeInfo) ret_type.get_interface()).get_g_type();
					if (schema_type == typeof(GLib.Object)
							|| !Bin.gtype_to_alias.has_key(schema_type)) {
						this.request.connection.reply_error(
							this.request, (int) RpcErrorCode.INVALID_PARAMS);
						return true;
					}
					this.request.connection.export(created);
					var packed = GLib.Value(schema_type);
					packed.set_object(created);
					response.retval = packed;
					break;
```

A GIR return declared as plain `GObject` stays `INVALID_PARAMS`. There is no search upward for a registered parent.

### 4. `libocrpc/Gi.vala` — `scalar`: one object OUT

**Why:** Object and interface OUT values fall through to the struct-size path, see size 0, and reply `INVALID_PARAMS`. After `dispatch_function` flattens a non-caller-allocates OUT, `arg.v_pointer` is the instance. Pack it the same way as a return. Caller-allocates object OUT still fails earlier, while the OUT slot is being allocated.

**Where:** `scalar`, start of `GI.TypeTag.INTERFACE`, before the enum arm.

**Depends on:** §1.

#### Remove

```vala
				case GI.TypeTag.INTERFACE:
					var kind = type.get_interface().get_type();
					if (kind == GI.InfoType.ENUM) {
```

#### Replace with

```vala
				case GI.TypeTag.INTERFACE:
					var kind = type.get_interface().get_type();
					if (kind == GI.InfoType.OBJECT || kind == GI.InfoType.INTERFACE) {
						if (arg.v_pointer == null) {
							var z = GLib.Value(typeof(GLib.Object));
							z.set_object(null);
							dest.add(z);
							return true;
						}
						var schema_type = ((GI.RegisteredTypeInfo) type.get_interface()).get_g_type();
						if (schema_type == typeof(GLib.Object)
								|| !Bin.gtype_to_alias.has_key(schema_type)) {
							this.request.connection.reply_error(
								this.request, (int) RpcErrorCode.INVALID_PARAMS);
							return false;
						}
						var obj = (GLib.Object) arg.v_pointer;
						this.request.connection.export(obj);
						var packed = GLib.Value(schema_type);
						packed.set_object(obj);
						dest.add(packed);
						return true;
					}
					if (kind == GI.InfoType.ENUM) {
```

A null OUT object is uint64 lease `0`, same as a null object already written by `StreamValue`.

## Attempts / changelog

- ✔️ 2026-10-06 — Applied the proposal without a `gtype_to_alias == null` test. `ninja -C build libocrpc/libocrpc.so`.
- ✔️ 2026-10-06 — Reverted the `ollmrpc-schema` `set_data` path. Object lists and hashes again use each element's runtime type. Single-object returns, OUT values, and `StreamValue.write` for one live object stay.
- ✔️ Gate against that library: `LD_LIBRARY_PATH=…/OLLMchat/build/libocrpc timeout 5 ./build/tests/call-sync-repro/declared-object-type-gate` → `PASS declared-object-type-gate: private leaf crossed as GatePublic`, exit 0.

## Exit

- `declared-object-type-gate` passes.
- The returned proxy is `GatePublic`, with the server lease still referring to `GatePrivate`.
- A later ping succeeds on the same connection.
- `MetaSurfaceActorWayland` needs no alias and does not appear in libocrpc.
