# Unregistered runtime type does not fall back to a registered parent

**Status:** ✔️ applied. Consumer gate passed. Debug line on the auto-`register_alias` path.

Related: [`2026-10-06-declared-object-wire-type.md`](2026-10-06-declared-object-wire-type.md). That change uses a public type only when the caller already put it on the `GValue`. This bug is the pack that never does.

## Problem

The design is that an unregistered private subclass is written as the nearest registered parent, so callers do not register each private implementation class as it appears. An exact `gtype_to_alias` entry still wins, so `MetaStageX11` stays `Clutter-Stage`.

`OLLMrpc.val("o", obj)` builds `GLib.Value(obj.get_type())`. `Bin/StreamValue.vala` then uses that runtime type when it has no exact alias. A private class such as `MetaSurfaceActorWayland` is not registered, `val.type()` is that same private type, and there is no walk to `Clutter.Actor`. The write throws and the connection stops.

Nested Weston, 2026-10-07 08:40, pointer motion over a window. `~/.cache/gnome-shell-rpc/mutter-rpc.debug.log`:

```text
08:40:24.201693  pointer motion
08:40:24.202988  Connection.vala:88: connection write error:
                  Unregistered declared class type schema: MetaSurfaceActorWayland
```

The client then logs `Unexpected early end-of-stream`. Later calls are `not connected`. `Clutter-Stage.get_actor_at_pos` had already been answered. The write that closes the socket is the event filter, which packs the picked actor with `OLLMrpc.val("o", event_actor)`.

## FAIL gate

From the gnome-shell-rpc tree:

```bash
meson compile -C build runtime-parent-schema-gate
timeout 5 ./build/tests/call-sync-repro/runtime-parent-schema-gate
```

The server returns `OLLMrpc.val("o", new GateUnregistered())`. `GateUnregistered` extends registered `GatePublic` and is not registered itself. The client must receive a `GatePublic` lease. A second call returns `val("o")` of a type explicitly aliased to `Gate-Public`. That lease must still be `GatePublic`. A later ping must succeed on the same connection.

```text
connection write error: Unregistered declared class type schema: GateUnregistered
FAIL runtime-parent-schema-gate: Client: disconnected
      (unregistered runtime type disconnected)
```

## Proposed fix

🔷 A parent walk on the first miss is fine. Walking again on every later write is not. The first hit is recorded with `register_alias`, so the next write is an exact `gtype_to_alias` lookup.

💩 `register_alias` is the existing extra-GType hook. It writes `gtype_to_alias` only. `alias_to_gtype` stays the public type the client constructs. The wire string stays the parent's alias (`Clutter-Actor`, `Gate-Public`). No private class name is registered.

- 🔷 Exact runtime alias still wins. `MetaStageX11` / `GateAliasedPrivate` never walk.
- 🔷 Declared `GValue` type still wins when the runtime type has no exact alias and that declared type is already registered. That path is one hash lookup and does not call `register_alias`. Stamping the runtime leaf from the first declared type would freeze the first caller’s type.
- 🔷 Walk only when the type is missing from `gtype_to_alias` and `Gi.in_typelib` is false. Unix `in_typelib` is `find_by_gtype != null`. A public GI type that was never registered still throws. Stop at `GLib.Type.OBJECT`. On a hit, `register_alias` and break. Windows and Android `Gi.in_typelib` returns false.
- 🚫 No walk in `Gi.vala`. Returns and OUT values already pack the declared GIR type. After this write fills the alias, later `has_key(obj.get_type())` checks see it.
- 🚫 No change to `alias_to_gtype`.

### 1. `libocrpc/Bin/StreamValue.vala` — `write`: remember the parent alias

**Why:** `OLLMrpc.val("o", obj)` stamps the private runtime type. The first such write walks to the nearest registered parent and stores that alias. Pointer motion after that is a hash hit.

**Where:** `write`, live-handle branch, the `schema_type` lookup through `ctx.write_gtype(schema_type)`.

**Depends on:** none.

#### Remove

```vala
					var live = val.get_object();
					var schema_type = gtype_to_alias.has_key(live.get_type())
						? live.get_type()
						: val.type();
					if (schema_type == typeof(GLib.Object)
							|| !gtype_to_alias.has_key(schema_type)) {
						throw new StreamError.REGISTRATION("Unregistered declared class type schema: %s",
							schema_type.name());
					}
					ctx.write_gtype(schema_type);
```

#### Replace with

```vala
					var live = val.get_object();
					var schema_type = gtype_to_alias.has_key(live.get_type())
						? live.get_type()
						: val.type();
					if (!gtype_to_alias.has_key(schema_type) && !OLLMrpc.Gi.in_typelib(schema_type)) {
						var parent = schema_type.parent();
						while (parent != GLib.Type.INVALID
								&& parent != GLib.Type.OBJECT) {
							if (gtype_to_alias.has_key(parent)) {
								register_alias(gtype_to_alias.get(parent), schema_type);
								GLib.debug("auto registered %s as %s", schema_type.name(), gtype_to_alias.get(parent));
								break;
							}
							parent = parent.parent();
						}
					}
					if (schema_type == GLib.Type.OBJECT
							|| !gtype_to_alias.has_key(schema_type)) {
						throw new StreamError.REGISTRATION("Unregistered declared class type schema: %s",
							schema_type.name());
					}
					ctx.write_gtype(schema_type);
```

`live` stays the lease pointer. The first `MetaSurfaceActorWayland` write stores that GType as `Clutter-Actor`. `GateAliasedPrivate` is still `Gate-Public` because its own type is already in `gtype_to_alias`.

## Attempts / changelog

- 🔷 2026-10-07 — User: hunt once, then fill the alias. A parent walk on every request stays out.
- 🔷 2026-10-07 — User: `GLib.Type.OBJECT`, not `typeof(GLib.Object)`.
- ✔️ 2026-10-07 — Applied in `libocrpc/Bin/StreamValue.vala`. `ninja -C build libocrpc/libocrpc.so`.
- ✔️ 2026-10-07 — `LD_LIBRARY_PATH=OLLMchat/build/libocrpc` `runtime-parent-schema-gate` → `PASS runtime-parent-schema-gate: unregistered parent and exact alias preserved`, exit 0.
- 🔷 2026-10-07 — User: `GLib.debug` when this path calls `register_alias`. Auto-registration is not the normal registration path.

- 🔷 2026-10-07 — User: auto-`register_alias` only when `find_by_gtype` is null. A normal GI type stays a registration error.
- 🔷 2026-10-07 — User: `Gi.in_typelib` on both GI classes. Windows returns false. No `#if` in `StreamValue`.

## Next

- ✔️ 2026-10-07 — `Gi.in_typelib` is in the rebuilt library. Gate: `PASS runtime-parent-schema-gate: unregistered parent and exact alias preserved`, exit 0.
