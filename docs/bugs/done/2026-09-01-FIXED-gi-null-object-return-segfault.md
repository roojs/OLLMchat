# FIXED: Gi.dispatch_function SIGSEGV on nullable OBJECT return

**Status:** ✅ FIXED — null OBJECT return leaves unset `retval` and `break`. User archived.

## Problem

🔷 Nested `mutter-rpc` / `gnome-shell-rpc` boot: compositor **SIGSEGV** (exit 139) on `Clutter.Actor.get_first_child` when the actor has no children. Socket closes; client sees the peer die.

🔷 Expected: GI dispatch replies with a null object retval for nullable OBJECT returns. Actual: crash inside `oll_mrpc_gi_dispatch_function`.

## Evidence

ℹ️ GDB: crash at `libocrpc/Gi.vala` ~512 in `dispatch_function` OBJECT return path.

ℹ️ `clutter_actor_get_first_child` returns **NULL** for an empty actor (legitimate). Mutter Clutter-16 GIR:

```xml
<return-value transfer-ownership="none" nullable="1">
```

ℹ️ Failing code:

```vala
var created = (GLib.Object) ret.v_pointer;
if (Bin.gtype_to_alias == null || !Bin.gtype_to_alias.has_key(created.get_type())) {
```

`created` is null → `get_type()` → SIGSEGV.

ℹ️ Same cast-then-`export` pattern in `dispatch_new` (~334) assumes non-null constructor returns (constructors are not this crash; noted for consistency only).

ℹ️ Consumer: gnome-shell-rpc ActorIter / `first_child` after lease-on-construct. Empty `UiActor` is a normal first walk.

## Root cause

✔️ `dispatch_function` treats every OBJECT / INTERFACE return as a live instance to export. It never handles `ret.v_pointer == null`, even when GIR marks the return `nullable="1"`. Null is a valid external FFI result, not a programming error in the caller.

🚫 Papering over this only in gnome-shell-rpc (skip calling `get_first_child`, fake children) hides the libocrpc contract bug for every other nullable object return.

## Proposed fix

🔷 In `dispatch_function` OBJECT/INTERFACE return branch (`Gi.vala` ~511): if `ret.v_pointer == null`, **break** without setting `response.retval` — leave the unset `GLib.Value` (`Type.INVALID`). Wire already omits that; client one-object decode treats it as no row. Same as null GLIST/GHASH (`scalar_list` / `scalar_hash` return without assigning).

🚫 `OLLMrpc.val("o", null)` — `to_value` `"o"` calls `obj.get_type()` and would SIGSEGV again.

🚫 Assigning `GLib.Value(GLib.Type.INVALID)` explicitly — redundant; `new Response()` already has unset `retval`.

#### Replace with

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

ℹ️ Optional follow-up (same file ~334): constructors should not return null on success; leave alone unless a case shows otherwise.

## Attempts / changelog

- ✔️ 2026-09-01 — Nested boot crash on `get_first_child`; GDB → `Gi.vala:512`; empty actor NULL return confirmed.
- 🚫 2026-09-01 — Agent started editing OLLMchat tree from gnome-shell-rpc session; user: file bug report only, do not patch other people's code.
- ✔️ 2026-09-01 — Applied null OBJECT return → leave unset `retval` and `break` in `dispatch_function` (`libocrpc/Gi.vala`).
- ✅ 2026-09-01 — User archived.
