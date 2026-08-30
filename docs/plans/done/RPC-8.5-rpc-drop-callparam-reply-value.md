# 8.5 — Drop `CallParam`; FFI handler dispatch; reply as `GLib.Value`

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Status:** parent — archived. Phase 1 (CallParam) **✅**; Phase 2 (FFI dispatch) **✅**; Phase 3 (reply `GLib.Value`) **✅** [`8.5.3`](RPC-8.5.3-DONE-rpc-response-value.md) / [`8.5.4`](RPC-8.5.4-DONE-rpc-retval-migrate.md).

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Builds on:** [`RPC-8.4-rpc-positional-values-and-ffi.md`](RPC-8.4-rpc-positional-values-and-ffi.md) — positional `GLib.Value` lists, `OLLMrpc.args` D-Bus signatures, and libffi via `Gi` already exist. 8.4 left `CallParam` and `call_*` signals in place on purpose.

**Related:** [`docs/bin-rpc-protocol.md`](../bin-rpc-protocol.md) §15 (`ANY[]`), root `Response.result` object arrays. Handler tables: [`docs/rpc-registration.md`](../rpc-registration.md). [`RPC-8.3.3-REJECTED-notification-gobject-payload.md`](RPC-8.3.3-REJECTED-notification-gobject-payload.md) — GObject `payload` on `Notification` was withdrawn; a `GLib.Value` is a different question.

---

## Purpose

- **🔷** Phase 1: migrate **every** `CallParam` consumer (handlers + callers) to **`Request.args`** / `OLLMrpc.args(...)`. Delete the bags only when nothing reads `request.param`.
- **🔷** `OLLMrpc.args("s", path)` (D-Bus signature + Vala `...`) only boxes. Lease / `export` / live wire stays on Request write (`StreamValue`).
- **🔷** Phase 2: FFI dispatch instead of `call_*`, phased: (1) registration API (2) dispatch uses it when the method is listed (3) migrate methods one at a time, first **`RPC-Daemon.hello` only**. Unlisted methods keep `call_*`. Listed methods are **instance** methods. `this` is the default registered object leased on that connection (`export` + existing `lease_ids`). Caller omits `lease_id`. No static / prefix.
- **🔷** Listed FFI lives in class `OLLMrpc.Ffi` (`libocrpc/Ffi.vala`), same shape as `Gi`: `new Ffi(this).dispatch()`. One `Libffi.Arg[]` of slots plus `pack`. Not a pile of typed arrays on `Request`.
- **🔷** Phase 3: add **`Response.retval`** (`GLib.Value`) beside **`result`**. Split: [`8.5.3`](RPC-8.5.3-DONE-rpc-response-value.md). Do not replace `result` in that cut.
- **⏳** Sub-plans: **8.5.1** = migrate inventory below + delete bags (✔️ in this file); **8.5.2** fences are in this file; **8.5.3** = [`RPC-8.5.3-DONE-rpc-response-value.md`](RPC-8.5.3-DONE-rpc-response-value.md).
- **ℹ️** Infrastructure already in tree: `OLLMrpc.args`, `Request.args` / `Response.args`. Phase 2 walk is ✔️. `call_*` dropped. `retval`: [`8.5.3`](RPC-8.5.3-DONE-rpc-response-value.md) / [`8.5.4`](RPC-8.5.4-DONE-rpc-retval-migrate.md).

**Suggested order:** migrate CallParam consumers (8.5.1) → delete bags / `Request.param` → register API (8.5.2.1) → dispatch-if-listed (8.5.2.2) → `hello` only (8.5.2.3) → remaining methods later → add `retval` (8.5.3). Can overlap remaining 8.4 FFI; 8.5.3 needs `StreamValue` live-handle / `OBJECT[]`.

---

## Already done (not the next step)

- **🔷** `✔️` `OLLMrpc.args` in `libocrpc/namespace.vala`. Smoke: `tests/rpc/values-test.vala`.
- **🔷** `✔️` Rename `Request.values` / `Response.values` → `args` (wire name too). `Gi.vala` already reads `args`.
- **ℹ️** `✔️` `CallParam` / `Request.param` / `param_types` removed (8.5.1).

---

## Phase 1 — migrate every `CallParam` consumer to `args`

Each method only sends what it uses (C / GIR style). Shared bags today send unused fields on every call.

**🔷** Both ends of a method move in the same cut (handler + callers). No dual-read of leftover `param`.

**🔷** After the inventory is empty: delete `CallParam` and subclasses, `Request.param`, `param_types`. Phase 1 Application still calls `Request.register(name, instance)`. Phase 2 keeps that call. Each class's `rpc_register()` lists methods via `Request.add_class`.

### Migration inventory — wire method → `args`

**Default (implement, do not ask):** fields the handler already reads, in that order; D-Bus letter from the Vala type (`s` / `i` / `b` / `u` / `x` / `t` / `as` / …). Empty bag → omit `args`. Drop unused bag fields. Straight conversions are **🔷**.

#### `RPC-Daemon`

- **🔷** `✔️` `RPC-Daemon.hello` — `args("is", protocol, client)` — `ollmfilesd/Daemon.vala`; callers `ollmapp/Window.vala`, `ollmchat-cli.vala`, examples, Client docs
- **🔷** `✔️` `RPC-Daemon.shutdown` — empty — `ollmfilesd/Daemon.vala`
- **🔷** `✔️` `RPC-Daemon.ready` — no `param` today (`StdioConnection`); leave empty / as-is

#### `RPC-ProjectManager`

- **🔷** `✔️` `RPC-ProjectManager.load_projects_from_db` — empty — `ollmfilesd/ProjectManager.vala`; `libocfiles` + examples
- **🔷** `✔️` `RPC-ProjectManager.create_project` — `args("s", path)` — `libocfiles` + `examples/oc-vector-index.vala`
- **🔷** `✔️` `RPC-ProjectManager.remove_project` — `args("s", path)` — `libocfiles`
- **🔷** `✔️` `RPC-ProjectManager.activate_project` — `args("sb", path, skip_scan)` — drop unused `project_summary_only`

#### `RPC-File`

- **🔷** `✔️` `RPC-File.read` / `exists` / `register` / `delete` — `args("s", path)` each — `libocfiles/File.vala`
- **🔷** `✔️` `RPC-File.fetch` — `args("ss", project_path, path)` — `libocfiles/Folder.vala`
- **🔷** `✔️` `RPC-File.write` — `args("ssssu", path, content, base_type, target, unix_mode)` — fields `write()` reads
- **🔷** `✔️` `RPC-File.apply_permissions` — `args("su", path, unix_mode)`
- **🔷** `✔️` `RPC-File.changed.check` — `args("sx", path, last_known_mtime)`

#### `RPC-FileHistory`

- **🔷** `✔️` `RPC-FileHistory.approve` / `revert` — `args("sx", path, id)` each — `libocfiles/FileHistory.vala`

#### `RPC-Folder`

- **🔷** `✔️` `RPC-Folder.fetch` / `project_description` / `roots` — `args("s", path)` each
- **🔷** `✔️` `RPC-Folder.contains_folder` — `args("ss", project_path, path)`
- **🔷** `✔️` `RPC-Folder.fetch_files` — `args("siisSb", path, offset, limit, query, paths, metadata_only)` — `S` = `string[]` + Vala FFI length
- **🔷** `✔️` `RPC-Folder.fetch_pending_approvals` — `args("sx", path, since_id)` — `libocfiles/ReviewFiles.vala`

#### `RPC-Codebase`

- **🔷** `✔️` `RPC-Codebase.reset` / `stop` — empty
- **🔷** `✔️` `RPC-Codebase.file_info` — `args("s", file_path)` — Summarize + examples
- **🔷** `✔️` `RPC-Codebase.start` — `args("ss", path, only_file)` — examples; Window banner only needs `path` (pass `""` for `only_file` if unused)
- **🔷** `✔️` `RPC-Codebase.search` — `args("ssissss", path, query, max_results, language, element_type, category, format)` — order from `Codebase.search` reads
- **🔷** `✔️` `RPC-Codebase.debug_get` — `args("ss", path, ast_path)`

#### `RPC-Live-*` (libocrpc)

- **🔷** Lease id is **`Request.lease_id`**, not an `args` slot (same field GI already uses). Drop `RemoteParams` / `SubscribeParams` `object_id`.
- **🔷** `✔️` `RPC-Live-Remote.rpc_ref` / `rpc_unref` — `lease_id` only; empty `args`
- **🔷** `✔️` `RPC-Live-Subscribe.rpc_signal` / `unsubscribe` — `lease_id` + `args("s", name)`
- **🔷** `✔️` Boot those prefixes with `Request.register_live` (not `register`). FFI keeps the handler as `this`. See §2.4.
- **ℹ️** Handlers / tests: `Live/Remote.vala`, `Live/Subscribe.vala`, `live-handles-test`, `subscribe-test`

#### HTTP (not positional RPC)

- **🔷** Hub query is a plain **`GLib.Object`** in `args.get(0)` (`args("o", search)`). `send_http` walks its properties into `?k=v` the same way it walks `request.param` today — no `CallParam` base, no HashTable, no Variant dict.
- **🔷** `✔️` `OLLMhf.Param.Search` stays a typed GObject (drop `: CallParam`). Callers: `examples/oc-hf.vala`, `liboctools/HuggingFace/Request.vala`.
- **🚫** Keep `Request.param` “just for HTTP”
- **🚫** HTTP-only HashTable / `a{sv}` packing for this cut

#### Register / delete / docs (after inventory empty)

- **🔷** `✔️` `Request.register` — drop third `param_type` (`Application.vala`, Live boot, tests)
- **🔷** `⏳` Delete bags listed below; meson / valadoc; protocol doc §15 / Request wording — drop `param`, document `args` as the call args path
- **🔷** No `Daemon.protocol` / wire-version bump — codec unchanged (`ANY[]` already exists). Both ends just stop sending `param` and send `args` (coordinated same-commit like other 8.x cuts)

### Bags to delete (reference)

- **ℹ️** `libocrpc/CallParam.vala` — base
- **ℹ️** `libocrpc/Live/RemoteParams.vala` — `object_id`
- **ℹ️** `libocrpc/Live/SubscribeParams.vala` — `object_id`, `name`
- **ℹ️** `libocrpc/Live/namespace.vala` — Win32/Android stubs
- **ℹ️** `ollmfilesd/CallParam.vala` — `DaemonParams`, `ProjectParams`, `FileParams`, `FolderParams`, `VectorParams`
- **ℹ️** `libochf/Param/Search.vala` — Hub query GObject (drop `CallParam` base; keep the type)

### Handler / caller shape

- **ℹ️** Today: `var p = (FileParams) request.param;` then `p.path`
- **🔷** After Phase 1: `request.args.get(0).get_string()` (index per method list above)
- **ℹ️** Phase 1 still emits `call_*` with `Request`. Phase 2 adds FFI for **listed** methods only; the rest stay on `call_*` until walked. Only packing helper remains **`OLLMrpc.args`**.

---

## Phase 2 — FFI instance methods instead of `call_*` signals

- **🔷** `call_*` signals exist because dispatch could not call an arbitrary method. `Request.args` + D-Bus signatures now make that possible.
- **🔷** Roll out in three cuts. Do not convert every handler in one go. Do not start Phase 3 until the walk is done (or explicitly split).

### Contract (all three cuts)

- **🔷** Each handler class already has `rpc_register()`. That is where the method list lives. It calls `Request.add_class`.
- **🔷** `Request.register(name, instance)` stays as today. Writes `handlers`. Application and tests keep calling it.
- **🔷** `Request.add_class`: wire prefix, `GLib.Type`, then Vala `...` pairs of method name + D-Bus signature (same letters as `OLLMrpc.args`). That is the new FFI table. Not an overload of `register`.
- **🔷** Listed methods are **instance** methods. No static path. No prefix on the method name.
- **🔷** `this` comes from a lease. Default RPC objects are already instances (`this.daemon`, `this.project_manager`, …). Registration keeps that instance. The caller does **not** send `lease_id`.
- **🔷** Default instance → lease uses the existing maps: `Connection.export` writes `leases` (id → object) and `lease_ids` (object pointer → id). Dispatch then uses the standard lease path (`leases.get(id)`), same as `Gi.dispatch_function`.
- **🔷** `live_handles` is the **wire** flag (encode a live GObject, `RPC-Live-Remote.rpc_ref` / `rpc_unref`, subscribe). Reusing `export` / `leases` for default RPC `this` does not turn that flag on. Drop the `live_handles` guard on `export`.
- **🔷** `Request.register` prefixes: if `lease_id != 0`, that lease is `this` (GI-style method-on-object). If `lease_id == 0`, export the registered default.
- **🔷** `Request.register_live` prefixes (`RPC-Live-Remote`, `RPC-Live-Subscribe`): `this` stays the registered handler. `lease_id` is the target. Missing lease → `INVALID_PARAMS`. Do not steal `this`.
- **🔷** C ABI: object first, then `Request`, then the signature.
- **🔷** Empty extra args use `""` (method still receives `Request`).
- **🔷** Dots in the wire suffix become underscores in the C symbol (`changed.check` → `changed_check`).
- **🔷** C symbol is Vala's usual `namespace_class_method` (GType `OllMfilesdDaemon` + `hello` → `oll_mfilesd_daemon_hello`).
- **🔷** The registered signature does **not** start with `o` for `Request`.
- **🔷** No return value. Replies stay `request.reply(...)` / `reply_error`.
- **🔷** Class `OLLMrpc.Ffi` in `libocrpc/Ffi.vala`. `Request.dispatch` calls `new Ffi(this).dispatch()`, then `call_*`, then `Gi`.
- **🔷** `Ffi.pack` is an instance method (not static). `Gi` will extend `Ffi` and use it. Visibility is `internal` so `ocrpc.vapi` does not require `--pkg=libffi` (`protected`/`public` would leak `Libffi` into the vapi).
- **🔷** One `Libffi.Arg[]` of slots. `Cif.call` builds the libffi `avalues` addresses in C.
- **🔷** Vapi namespace is `Libffi`. Do not name it `Ffi` — that collides with the class.
- **🔷** Vapi hides the C mess: `Type` is `SimpleType` (`ffi_type*`) with consts (`Libffi.POINTER`, `Libffi.VOID`, …); `Arg.set_*`; `Cif.prep` / `Cif.call`. No `&Libffi.type_*`, no parallel `avalues` array in Vala.
- **🔷** `Ffi.vala` is in `ocrpc_core_src` (every platform). Not `gi_src`. Windows/Android still get this path without typelib.
- **ℹ️** This path is libffi on **our** C symbols. Not GI / typelib / `Gi.vala`. `windows/Gi.vala` is unrelated.
- **ℹ️** `Gi.convert` already packs into one `GI.Argument[]` union. The overlap is scalars (letter / TypeTag → slot). Do not rewrite `Gi.vala` in 8.5.2.
- **ℹ️** `rpc_register()` already calls `Bin.register` for the wire type. That stays. 2.3 adds `Request.add_class` there. Application already calls `Request.register(name, instance)`.

Intro: edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

### 2.1 — Registration only

- **🔷** `✔️` Leave `Request.register(name, instance)` as today. Add `Request.add_class(name, type, ...)` and the method table.
- **🔷** Every `call_*` stays. No handler bodies move yet. No dispatch change yet.
- **🔷** Do not edit `Application.vala`. It already calls `Request.register(name, instance)`.
- **ℹ️** Per-class `rpc_register()` does not have to list methods in this cut.
- **ℹ️** Varargs are method/signature pairs.

### 1. `libocrpc/Request.vala` — `add_class`; `register` unchanged

**Why:** Old boot keeps `register(name, instance)`. New FFI table is `add_class`.

**Where:** static fields after `handlers`; new `add_class` after `register`.

**Depends on:** none.

#### Remove

```vala
		/** Wire object prefix → handler singleton (server dispatch). */
		public static Gee.HashMap<string, GLib.Object> handlers;
```

#### Replace with

```vala
		/** Wire object prefix → handler singleton (server dispatch). */
		public static Gee.HashMap<string, GLib.Object> handlers;

		/** Wire object prefix → Vala GType (C symbol). */
		public static Gee.HashMap<string, GLib.Type> types;

		/** Wire object prefix → (method suffix → D-Bus signature). */
		public static Gee.HashMap<string, Gee.HashMap<string, string>> methods;
```

#### Add — after `register`, before `find_property`. Method table for FFI dispatch. `register` stays the instance path.

```vala
		/**
		 * List FFI instance methods for a wire prefix.
		 *
		 * Pair method suffix with a D-Bus signature (same letters as
		 * {@link args}). The live singleton is still {@link register}.
		 *
		 * == Example ==
		 *
		 * {{{
		 * OLLMrpc.Request.add_class(
		 *     "RPC-Daemon", typeof(Daemon), "hello", "is"
		 * );
		 * OLLMrpc.Request.register("RPC-Daemon", this.daemon);
		 * }}}
		 *
		 * @param name wire object prefix (e.g. RPC-Folder)
		 * @param type handler GType (C prefix)
		 * @param ... method, signature pairs
		 */
		public static void add_class(
			string name,
			GLib.Type type,
			...
		) {
			if (types == null) {
				types = new Gee.HashMap<string, GLib.Type>();
				methods = new Gee.HashMap<string, Gee.HashMap<string, string>>();
			}
			types.set(name, type);
			if (!methods.has_key(name)) {
				methods.set(name, new Gee.HashMap<string, string>());
			}
			var l = va_list();
			while (true) {
				var method = l.arg<string>();
				if (method == null) {
					break;
				}
				methods.get(name).set(method, l.arg<string>());
			}
		}
```

### 2.2 — Dispatch picks up a listed method

- **🔷** `✔️` `Request.dispatch`: `new Ffi(this).dispatch()`. Then `call_*`. Then `Gi`.
- **🔷** `Ffi.dispatch` returns true when the method is listed (called or already failed). Unlisted returns false so `call_*` still runs.
- **🔷** Unpack with the registered signature. Count must match `request.args.size`.
- **🔷** `lease_id == 0`: `export` the `handlers` default, then `leases.get(id)`. Non-zero `lease_id`: that row.
- **🔷** If the method is **not** listed, emit `call_*` as today. Then `Gi` fallback as today.
- **🔷** `pack` unpacks the same letters as `OLLMrpc.args`.
	- `switch` on the tag (same shape as `OLLMrpc.args`)
	- `s` / `g` string; `as` / `ay` boxed; default is `i` (`h` same C int)
	- `f` is scanned like `args` (not a GVariant letter)
- **🚫** Long `if` / `if` / `if` chain in `pack` — use `switch`
- **🔷** One `Libffi.Arg[]`. Not one array per C type.
- **🔷** Vapi methods hide `&type_*` / union fields / `avalues`.
- **🚫** `Request.invoke`.
- **🚫** Ten parallel typed arrays (`ivals`, `yvals`, …).
- **🚫** Raw `slot.v_*` / `&Libffi.type_*` / hand-built `void*[] avalues` in `Ffi.vala`.
- **💩** Later: `Gi` extends `Ffi`; scalars use `this.pack`. Not this cut.
- **🚫** `static` `pack` — instance method so subclasses inherit it.

### 5. `libocrpc/libffi-arg.h` — union slot + vapi helpers

**Why:** one union for slots. C inlines back the vapi methods so Vala never touches field names or `avalues`.

**Where:** new file next to `libffi.vapi`.

**Depends on:** none.

#### Add — new file `libocrpc/libffi-arg.h`

```c
#pragma once
#include <ffi.h>
#include <glib.h>

typedef union {
	gint v_int32;
	guint8 v_uint8;
	gint16 v_int16;
	guint16 v_uint16;
	guint v_uint32;
	gint64 v_int64;
	guint64 v_uint64;
	gfloat v_float;
	gdouble v_double;
	gpointer v_pointer;
} OLLMrpcFfiArg;

static inline void ollmrpc_ffi_arg_set_int32(OLLMrpcFfiArg *a, gint v)
{
	a->v_int32 = v;
}

static inline void ollmrpc_ffi_arg_set_uint8(OLLMrpcFfiArg *a, guint8 v)
{
	a->v_uint8 = v;
}

static inline void ollmrpc_ffi_arg_set_int16(OLLMrpcFfiArg *a, gint16 v)
{
	a->v_int16 = v;
}

static inline void ollmrpc_ffi_arg_set_uint16(OLLMrpcFfiArg *a, guint16 v)
{
	a->v_uint16 = v;
}

static inline void ollmrpc_ffi_arg_set_uint32(OLLMrpcFfiArg *a, guint v)
{
	a->v_uint32 = v;
}

static inline void ollmrpc_ffi_arg_set_int64(OLLMrpcFfiArg *a, gint64 v)
{
	a->v_int64 = v;
}

static inline void ollmrpc_ffi_arg_set_uint64(OLLMrpcFfiArg *a, guint64 v)
{
	a->v_uint64 = v;
}

static inline void ollmrpc_ffi_arg_set_float(OLLMrpcFfiArg *a, gfloat v)
{
	a->v_float = v;
}

static inline void ollmrpc_ffi_arg_set_double(OLLMrpcFfiArg *a, gdouble v)
{
	a->v_double = v;
}

static inline void ollmrpc_ffi_arg_set_pointer(OLLMrpcFfiArg *a, gpointer v)
{
	a->v_pointer = v;
}

#define OLLMRPC_FFI_TYPE_VOID (&ffi_type_void)
#define OLLMRPC_FFI_TYPE_POINTER (&ffi_type_pointer)
#define OLLMRPC_FFI_TYPE_UINT8 (&ffi_type_uint8)
#define OLLMRPC_FFI_TYPE_SINT16 (&ffi_type_sint16)
#define OLLMRPC_FFI_TYPE_UINT16 (&ffi_type_uint16)
#define OLLMRPC_FFI_TYPE_SINT32 (&ffi_type_sint32)
#define OLLMRPC_FFI_TYPE_UINT32 (&ffi_type_uint32)
#define OLLMRPC_FFI_TYPE_SINT64 (&ffi_type_sint64)
#define OLLMRPC_FFI_TYPE_UINT64 (&ffi_type_uint64)
#define OLLMRPC_FFI_TYPE_FLOAT (&ffi_type_float)
#define OLLMRPC_FFI_TYPE_DOUBLE (&ffi_type_double)

static inline int ollmrpc_ffi_prep_void(ffi_cif *cif, unsigned int nargs, ffi_type **atypes)
{
	return ffi_prep_cif(cif, FFI_DEFAULT_ABI, nargs, &ffi_type_void, atypes);
}

static inline void ollmrpc_ffi_call_void(ffi_cif *cif, void *fn, OLLMrpcFfiArg *slots, unsigned int n)
{
	void **avalues = g_newa(void *, n);
	unsigned int i;
	for (i = 0; i < n; i++) {
		avalues[i] = &slots[i];
	}
	ffi_call(cif, fn, NULL, avalues);
}
```

### 5.1. `libocrpc/libffi.vapi` — libffi C types + methods

**Why:** Ubuntu/valac ship no `libffi.vapi`. In-tree binding (**🔷**). Namespace `Libffi`. Methods hide `&ffi_type_*`, union fields, and `avalues` (same idea as the public apmasell `libffi.vapi`).

**Where:** new file next to `Request.vala`.

**Depends on:** §5.

#### Add — new file `libocrpc/libffi.vapi` — libffi binding for `OLLMrpc.Ffi`

```vala
[CCode (cheader_filename = "ffi.h,libffi-arg.h")]
namespace Libffi {
	[CCode (cname = "ffi_type*", cprefix = "ffi_type_", has_type_id = false)]
	[SimpleType]
	public struct Type {
	}

	[CCode (cname = "OLLMRPC_FFI_TYPE_VOID")]
	public const Type VOID;

	[CCode (cname = "OLLMRPC_FFI_TYPE_POINTER")]
	public const Type POINTER;

	[CCode (cname = "OLLMRPC_FFI_TYPE_UINT8")]
	public const Type UINT8;

	[CCode (cname = "OLLMRPC_FFI_TYPE_SINT16")]
	public const Type SINT16;

	[CCode (cname = "OLLMRPC_FFI_TYPE_UINT16")]
	public const Type UINT16;

	[CCode (cname = "OLLMRPC_FFI_TYPE_SINT32")]
	public const Type SINT32;

	[CCode (cname = "OLLMRPC_FFI_TYPE_UINT32")]
	public const Type UINT32;

	[CCode (cname = "OLLMRPC_FFI_TYPE_SINT64")]
	public const Type SINT64;

	[CCode (cname = "OLLMRPC_FFI_TYPE_UINT64")]
	public const Type UINT64;

	[CCode (cname = "OLLMRPC_FFI_TYPE_FLOAT")]
	public const Type FLOAT;

	[CCode (cname = "OLLMRPC_FFI_TYPE_DOUBLE")]
	public const Type DOUBLE;

	[CCode (cname = "OLLMrpcFfiArg", has_type_id = false)]
	public struct Arg {
		[CCode (cname = "ollmrpc_ffi_arg_set_int32")]
		public void set_int32(int v);

		[CCode (cname = "ollmrpc_ffi_arg_set_uint8")]
		public void set_uint8(uint8 v);

		[CCode (cname = "ollmrpc_ffi_arg_set_int16")]
		public void set_int16(int16 v);

		[CCode (cname = "ollmrpc_ffi_arg_set_uint16")]
		public void set_uint16(uint16 v);

		[CCode (cname = "ollmrpc_ffi_arg_set_uint32")]
		public void set_uint32(uint v);

		[CCode (cname = "ollmrpc_ffi_arg_set_int64")]
		public void set_int64(int64 v);

		[CCode (cname = "ollmrpc_ffi_arg_set_uint64")]
		public void set_uint64(uint64 v);

		[CCode (cname = "ollmrpc_ffi_arg_set_float")]
		public void set_float(float v);

		[CCode (cname = "ollmrpc_ffi_arg_set_double")]
		public void set_double(double v);

		[CCode (cname = "ollmrpc_ffi_arg_set_pointer")]
		public void set_pointer(void* v);
	}

	[CCode (cname = "ffi_cif", has_type_id = false, destroy_function = "")]
	public struct Cif {
		/**
		 * ''ffi_prep_cif'' for a void return and the default ABI.
		 *
		 * @return 0 on success (''FFI_OK'')
		 */
		[CCode (cname = "ollmrpc_ffi_prep_void")]
		public static int prep(
			out Cif cif,
			[CCode (array_length_type = "unsigned int", array_length_pos = 1.5)] Type[] atypes
		);

		/**
		 * ''ffi_call'' with no return slot. Builds ''avalues'' from ''slots''.
		 */
		[CCode (cname = "ollmrpc_ffi_call_void")]
		public void call(
			void* fn,
			[CCode (array_length_type = "unsigned int", array_length_pos = 2.9)] Arg[] slots
		);
	}
}
```

### 6. `libocrpc/meson.build` — `libffi` + `gmodule-2.0` + local vapi + `Ffi.vala`

**Why:** `Libffi` and `GLib.Module.open(null)` (symbol in this process). `Ffi.vala` is core, not `gi_src`. Header must be on the C include path.

**Where:** `ocrpc_deps` / `ocrpc_vapi_pkgs` / `ocrpc_vapi_gen_pkgs`; `vala_args` vapidir; `ocrpc_core_src`; `ocrpc_base_lib`.

**Depends on:** §5, §5.1.

#### Add — after `valac.find_library('posix'),` in `ocrpc_deps`

```meson
  dependency('libffi'),
  dependency('gmodule-2.0'),
```

#### Add — after `'--pkg=posix',` in `ocrpc_vapi_pkgs`

```meson
  '--pkg=libffi',
  '--pkg=gmodule-2.0',
```

#### Add — after `'--pkg', 'posix',` in `ocrpc_vapi_gen_pkgs`

```meson
  '--pkg', 'libffi',
  '--pkg', 'gmodule-2.0',
```

#### Add — in `ocrpc_base_lib` `vala_args`, before `'--vapidir', '/usr/share/vala/vapi'`

```meson
    '--vapidir', meson.current_source_dir(),
```

#### Add — in `ocrpc-vapi` `command`, after `'--vapidir', meson.current_build_dir()`, before `'--vapidir', '/usr/share/vala/vapi'`. Same local vapi dir as the library so `--pkg=libffi` finds `libffi.vapi`.

```meson
    '--vapidir', meson.current_source_dir(),
```

#### Add — in `ocrpc_core_src` `files([...])`, after `'Request.vala',`. `Ffi.vala` is compiled on every platform.

```meson
  'Ffi.vala',
```

#### Add — on `ocrpc_base_lib = library('ocrpc',`, after `sources: ocrpc_src,`. Generated C includes `libffi-arg.h`.

```meson
  include_directories: include_directories('.'),
```

### 6.1. `docs/meson.build` — valadoc input for `Ffi.vala`

**Why:** new public class.

**Where:** libocrpc sources list, after `Gi.vala`.

**Depends on:** §8.

#### Add — after `'../libocrpc/Gi.vala',`

```meson
    '../libocrpc/Ffi.vala',
```

### 7. `libocrpc/Transport/Connection.vala` — `export`: drop `live_handles` guard

**Why:** lease table is reused for default RPC `this`. Flag stays the wire feature.

**Where:** first lines of `export`.

**Depends on:** none.

#### Remove

```vala
		public uint64 export(GLib.Object gobject)
		{
			if (!this.live_handles) {
				GLib.error("export requires live_handles");
			}
			var ptr = (uint64) (void*) gobject;
```

#### Replace with

```vala
		public uint64 export(GLib.Object gobject)
		{
			var ptr = (uint64) (void*) gobject;
```

### 8. `libocrpc/Ffi.vala` — listed-method FFI (`dispatch` + `pack`)

**Why:** listed methods skip `call_*`. One union array plus `pack`, not ten typed arrays on `Request`. `Gi` can call `pack` later.

**Where:** new file. Add to `ocrpc_core_src` (§6).

**Depends on:** §1, §5, §5.1, §6, §7.

#### Add — new file `libocrpc/Ffi.vala`

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
	 * Call listed RPC instance methods via libffi.
	 *
	 * {@link Request.add_class} records the method table.
	 * {@link Request.dispatch} constructs {@link Ffi} with the inbound
	 * {@link Request} and calls {@link dispatch}. That method looks up
	 * the C symbol and calls it. Unlisted prefixes return false so
	 * {@link Request.dispatch} can emit ''call_*'' then try {@link Gi}.
	 * Compiled on every platform (not ''gi_src'').
	 *
	 * {@link pack} writes one {@link Libffi.Arg} from a D-Bus letter
	 * and a {@link GLib.Value}. {@link Gi} already packs typelib calls
	 * into a union array; a later cut can call {@link pack} for
	 * scalars.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Request.add_class(
	 *     "RPC-Daemon", typeof(Daemon), "hello", "is"
	 * );
	 * var ffi = new OLLMrpc.Ffi(req);
	 * ffi.dispatch();
	 * }}}
	 */
	public class Ffi : GLib.Object
	{
		/**
		 * Inbound call this instance applies. Owner of method / args /
		 * connection — not copied onto {@link Ffi}.
		 */
		public Request request { get; construct; }

		public Ffi(Request request)
		{
			GLib.Object(request: request);
		}

		/**
		 * Fill one libffi slot from a D-Bus letter and a
		 * {@link GLib.Value}.
		 *
		 * Same letters as ''OLLMrpc.args''. {@link Gi} can call this for
		 * scalars later; this cut does not rewrite {@link Gi}.
		 *
		 * @param tag D-Bus letter or ''as'' / ''ay''
		 * @param val boxed argument
		 * @param slot union written for libffi
		 * @param atype matching {@link Libffi.Type} const
		 */
		internal void pack(
			string tag,
			GLib.Value val,
			ref Libffi.Arg slot,
			out Libffi.Type atype
		) {
			switch (tag) {
				case "s":
				case "g":
					slot.set_pointer((void*) val.get_string());
					atype = Libffi.POINTER;
					break;

				case "b":
					slot.set_int32(val.get_boolean() ? 1 : 0);
					atype = Libffi.SINT32;
					break;

				case "y":
					slot.set_uint8(val.get_uchar());
					atype = Libffi.UINT8;
					break;

				case "n":
					slot.set_int16((int16) val.get_int());
					atype = Libffi.SINT16;
					break;

				case "q":
					slot.set_uint16((uint16) val.get_uint());
					atype = Libffi.UINT16;
					break;

				case "u":
					slot.set_uint32(val.get_uint());
					atype = Libffi.UINT32;
					break;

				case "x":
					slot.set_int64(val.get_int64());
					atype = Libffi.SINT64;
					break;

				case "t":
					slot.set_uint64(val.get_uint64());
					atype = Libffi.UINT64;
					break;

				case "f":
					slot.set_float(val.get_float());
					atype = Libffi.FLOAT;
					break;

				case "d":
					slot.set_double(val.get_double());
					atype = Libffi.DOUBLE;
					break;

				case "o":
					slot.set_pointer((void*) val.get_object());
					atype = Libffi.POINTER;
					break;

				case "as":
				case "ay":
					slot.set_pointer(val.get_boxed());
					atype = Libffi.POINTER;
					break;

				case "v":
					slot.set_pointer(val.peek_pointer());
					atype = Libffi.POINTER;
					break;

				default:
					slot.set_int32(val.get_int());
					atype = Libffi.SINT32;
					break;
			}
		}

		/**
		 * FFI-call a listed instance method.
		 *
		 * @return true when this method is listed
		 */
		public bool dispatch()
		{
			if (Request.methods == null) {
				return false;
			}
			var dot = this.request.method.index_of_char('.');
			var object_name = this.request.method[0:dot];
			var method_name = this.request.method.substring(dot + 1);
			if (!Request.methods.has_key(object_name)
				|| !Request.methods.get(object_name).has_key(method_name)) {
				return false;
			}
			var signature = Request.methods.get(object_name).get(method_name);
			var n_extra = 0;
			var offset = 0;
			while (offset < signature.length) {
				var rest = signature.substring(offset);
				if (rest.has_prefix("f")) {
					offset += 1;
					n_extra += 1;
					continue;
				}
				var rest_ptr = (char*) rest;
				var next = (char*) null;
				if (!GLib.VariantType.string_scan(rest, null, out next)
					|| next == rest_ptr) {
					GLib.error("invalid D-Bus type signature %s", signature);
				}
				offset += (int) ((uint8*) next - (uint8*) rest_ptr);
				n_extra += 1;
			}
			if (n_extra != this.request.args.size) {
				GLib.critical("RPC dispatch: %s args size %d want %d",
					this.request.method, this.request.args.size, n_extra);
				return true;
			}
			if (Request.handlers == null
				|| !Request.handlers.has_key(object_name)) {
				GLib.critical("RPC dispatch: no handler instance for %s",
					this.request.method);
				return true;
			}
			var self = Request.handlers.get(object_name);
			if (this.request.lease_id == 0) {
				var id = (int) this.request.connection.export(self);
				self = this.request.connection.leases.get(id);
			}
			if (this.request.lease_id != 0) {
				var id = (int) this.request.lease_id;
				if (!this.request.connection.leases.has_key(id)) {
					this.request.connection.reply_error(
						this.request, (int) RpcErrorCode.INVALID_PARAMS);
					return true;
				}
				self = this.request.connection.leases.get(id);
			}
			var camel = new GLib.Regex("(?<=[a-z])([A-Z])");
			var symbol = camel.replace(
				Request.types.get(object_name).name(), -1, 0, "_\\1"
			).down() + "_" + method_name.replace(".", "_");
			var mod = GLib.Module.open(null, GLib.ModuleFlags.LAZY);
			if (mod == null) {
				GLib.critical("RPC dispatch: Module.open failed for %s",
					this.request.method);
				return true;
			}
			var fn = (void*) null;
			if (!mod.symbol(symbol, out fn)) {
				GLib.critical("RPC dispatch: no symbol %s for %s",
					symbol, this.request.method);
				return true;
			}
			var nargs = 2 + n_extra;
			var atypes = new Libffi.Type[nargs];
			var slots = new Libffi.Arg[nargs];
			slots[0].set_pointer((void*) self);
			slots[1].set_pointer((void*) this.request);
			atypes[0] = Libffi.POINTER;
			atypes[1] = Libffi.POINTER;
			offset = 0;
			var ai = 0;
			while (offset < signature.length) {
				var rest = signature.substring(offset);
				var tag = "";
				if (rest.has_prefix("f")) {
					tag = "f";
					offset += 1;
				} else {
					var rest_ptr = (char*) rest;
					var next = (char*) null;
					if (!GLib.VariantType.string_scan(rest, null, out next)
						|| next == rest_ptr) {
						GLib.error("invalid D-Bus type signature %s", signature);
					}
					var n = (long) ((uint8*) next - (uint8*) rest_ptr);
					tag = rest.substring(0, n);
					offset += (int) n;
				}
				this.pack(tag, this.request.args.get(ai), ref slots[2 + ai], out atypes[2 + ai]);
				ai += 1;
			}
			var cif = Libffi.Cif();
			if (Libffi.Cif.prep(out cif, atypes) != 0) {
				GLib.critical("RPC dispatch: ffi_prep_cif failed for %s",
					this.request.method);
				return true;
			}
			cif.call(fn, slots);
			return true;
		}
	}
}
```

### 9. `libocrpc/Request.vala` — `dispatch` calls `Ffi`

**Why:** listed methods skip `call_*`. Same call shape as `new Gi(this).dispatch()`.

**Where:** `dispatch`, before the `handlers` `if`.

**Depends on:** §8.

#### Add — before `if (handlers != null && handlers.has_key(object_name))`. `true` means listed (called or already failed); do not fall through to `call_*`.

```vala
			if (new Ffi(this).dispatch()) {
				return true;
			}

```

### 2.3 — First method: `RPC-Daemon.hello` only

- **🔷** `✔️` List `"hello", "is"` from `Daemon.rpc_register()`. Instance method. Move the `call_hello` body onto it. Drop `call_hello` and its `construct` connect.
- **🔷** Do not edit `Application.vala`. The instance is already `Request.register("RPC-Daemon", this.daemon)`.
- **🔷** Caller still omits `lease_id`.
- **🔷** Leave `call_shutdown` and every other handler on signals.

### 10. `ollmfilesd/Daemon.vala` — `rpc_register` + `hello`; drop `call_hello`

**Why:** first listed method. `this` is the leased default `Daemon`.

**Where:** `rpc_register`, signal, `construct`.

**Depends on:** §1, §8, §9.

#### Remove

```vala
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Daemon", typeof(Daemon));
		}
```

#### Replace with

```vala
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Daemon", typeof(Daemon));
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(Daemon), "hello", "is"
			);
		}
```

#### Remove

```vala
		public signal void call_hello(OLLMrpc.Request request);
		public signal void call_shutdown(OLLMrpc.Request request);
```

#### Replace with

```vala
		public signal void call_shutdown(OLLMrpc.Request request);

		public void hello(OLLMrpc.Request request, int protocol, string client)
		{
			if (protocol > 0) {
				this.protocol = protocol;
			}
			var result = new Gee.ArrayList<GLib.Object>();
			result.add(this);
			request.reply(new OLLMrpc.Response() {
				result = result
			});
		}
```

#### Remove

```vala
			this.call_hello.connect((request) => {
				if (request.args.get(0).get_int() > 0) {
					this.protocol = request.args.get(0).get_int();
				}
				var result = new Gee.ArrayList<GLib.Object>();
				result.add(this);
				request.reply(new OLLMrpc.Response() {
					result = result
				});
			});
			this.call_shutdown.connect((request) => {
```

#### Replace with

```vala
			this.call_shutdown.connect((request) => {
```

### Later call sites (not 2.3)

- **🔷** `✔️` Mechanical hello-pattern lifts (wire suffix = instance method = `add_class` key; drop `call_*` for that suffix only):
  - `Daemon.shutdown` (`""`)
  - `File.read` / `exists` / `fetch` / `apply_permissions` / `register` / `changed.check`
  - `Folder.fetch` / `contains_folder` / `fetch_pending_approvals`
  - `Codebase.file_info` / `reset` / `start` / `stop`
  - `ProjectManager.remove_project` (`"s"`) — existing method now `(Request, string path)`
- **🔷** `✔️` Clash/async: `rpc_*` instance method + caller wire name:
  - `ProjectManager.rpc_load_projects_from_db` / `rpc_create_project` / `rpc_activate_project`
  - `File.rpc_write` / `rpc_delete`
  - `Folder.rpc_project_description` / `rpc_roots`
  - `Codebase.rpc_search` / `rpc_debug_get`
  - `FileHistory.rpc_approve` / `rpc_revert`
- **🔷** `✔️` Client relay methods keep the `rpc_*` name (do not strip it to `write` / `delete` / …). `libocfiles` matches the wire suffix.
- **🔷** Dummy handlers in `tests/rpc/*` stay on `call_*` until listed.
- **🔷** `✔️` Remaining in §2.4: none. `S` packs Vala's hidden `string[]` length. Do not teach the library `_sync`.

### 2.4 — Walk complete

- **🔷** `✔️` `Folder.fetch_files` — `add_class` `"siisSb"`. `S` is one wire `string[]` and two C args (`gchar**` + `gint paths_length1`). Wire encoding is still counted `string[]` (`StreamValue`).
- **🔷** `✔️` `Request.register_live` — Live prefixes keep the handler as `this`; `lease_id` is the target.
- **🔷** `✔️` Live FFI (`rpc_*` where clash / keyword):
  - `Live.Remote.rpc_ref` / `rpc_unref` — `""` — wire `RPC-Live-Remote.rpc_ref` / `rpc_unref`
  - `Live.Subscribe.rpc_signal` — `"s"` — wire `RPC-Live-Subscribe.rpc_signal`
  - `Live.Subscribe.unsubscribe` — `"s"` — wire unchanged

**🔷** Callers / tests change the wire suffix when the listed name is `rpc_*`.

- **🚫** Extra `o` / capital `O` in `args` for the live object.
- **🚫** Infer “live” from GType vs leased GType, or from the `RPC-Live-` string.

#### `register_live`

Intro: edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

### 11. `libocrpc/Request.vala` — `live` map + `register_live`

**Why:** Live prefixes must be flagged at boot so FFI keeps the handler as `this`.

**Where:** static fields after `methods`; new method after `register`.

**Depends on:** none.

#### Add — after `methods`, before `id`. Prefixes that keep the handler as `this`.

```vala
		/** Wire prefixes registered with {@link register_live}. */
		public static Gee.HashMap<string, bool> live;
```

#### Add — after `register`, before `add_class`. Same `handlers` row plus the live mark.

```vala
		/**
		 * Register a live-handle handler.
		 *
		 * Same as {@link register}, and FFI keeps this singleton as
		 * ''this'' when {@link lease_id} is set. The id is the target
		 * (ref / unref / subscribe), not the calling object.
		 *
		 * == Example ==
		 *
		 * {{{
		 * OLLMrpc.Request.register_live("RPC-Live-Remote", new OLLMrpc.Live.Remote());
		 * }}}
		 *
		 * @param name wire object prefix (e.g. RPC-Live-Remote)
		 * @param target handler singleton
		 */
		public static void register_live(string name, GLib.Object target)
		{
			register(name, target);
			if (live == null) {
				live = new Gee.HashMap<string, bool>();
			}
			live.set(name, true);
		}
```

### 12. `libocrpc/Ffi.vala` — `dispatch`: live prefix keeps handler `this`

**Why:** Non-zero `lease_id` must not replace `self` for `register_live` prefixes.

**Where:** `dispatch`, the `lease_id != 0` block after the missing-lease error.

**Depends on:** ### 11.

#### Remove

```vala
				self = this.request.connection.leases.get(id);
```

#### Replace with

```vala
				if (Request.live == null || !Request.live.has_key(object_name)) {
					self = this.request.connection.leases.get(id);
				}
```

**ℹ️** Still `INVALID_PARAMS` when the lease id is missing. Skip only the `self` swap.

### 13. Tests + Live examples — `register_live`

**Why:** Boot Live handlers through the new table. `handlers.set` stays inside `register`.

**Where:** `tests/rpc/live-handles-test.vala`, `tests/rpc/subscribe-test.vala`; doc samples in `Live/Remote.vala` / `Live/Subscribe.vala`.

**Depends on:** ### 11.

#### Remove — `live-handles-test.vala` `run_rpc_test`

```vala
			OLLMrpc.Request.register(
				"RPC-Live-Remote",
				new OLLMrpc.Live.Remote()
			);
```

#### Replace with

```vala
			OLLMrpc.Request.register_live("RPC-Live-Remote", new OLLMrpc.Live.Remote());
```

#### Remove — `subscribe-test.vala` `run_rpc_test`

```vala
			OLLMrpc.Request.register(
				"RPC-Live-Remote",
				new OLLMrpc.Live.Remote()
			);
			OLLMrpc.Request.register(
				"RPC-Live-Subscribe",
				new OLLMrpc.Live.Subscribe()
			);
```

#### Replace with

```vala
			OLLMrpc.Request.register_live("RPC-Live-Remote", new OLLMrpc.Live.Remote());
			OLLMrpc.Request.register_live("RPC-Live-Subscribe", new OLLMrpc.Live.Subscribe());
```

#### Remove — `Live/Remote.vala` class example

```vala
		 * OLLMrpc.Request.register(
		 *     "RPC-Live-Remote", new OLLMrpc.Live.Remote());
```

#### Replace with

```vala
		 * OLLMrpc.Request.register_live("RPC-Live-Remote", new OLLMrpc.Live.Remote());
```

#### Remove — `Live/Subscribe.vala` class example

```vala
		 * OLLMrpc.Request.register(
		 *     "RPC-Live-Subscribe", new OLLMrpc.Live.Subscribe());
```

#### Replace with

```vala
		 * OLLMrpc.Request.register_live("RPC-Live-Subscribe", new OLLMrpc.Live.Subscribe());
```

**ℹ️** Also retarget the prose “Handler wiring is {@link Request.register}” on those two classes to `register_live`.

#### Async C labels (Vala `.begin` / `.end`)

**ℹ️** This valac does **not** emit `_begin` / `_end`. `.begin` is the method C name with `GAsyncReadyCallback` + `gpointer` tacked on. `.end` is `_finish`. Internal: `_co`, `_ready` (not FFI). `static` = not in the dynamic symbol table (`Module.symbol` misses it).

**🔷** `✔️` `fetch_files` uses the same wrap as `rpc_write`: listed sync FFI entry `.begin`s `fetch_files_reply`. Do not FFI-call the private async.

- **ℹ️** Today’s `Ffi.dispatch` looks up the **start** name (`…_write`, not `…_write_finish`). Calling it without callback/`user_data` is the wrong ABI.
- **ℹ️** `private async` compiles `static` — FFI cannot find `File.write` / `search` / `debug_get` / `fetch_files_reply` until they are non-private.
- **ℹ️** `load_projects_from_db` start takes no `Request` and does not `reply`; the lambda replies after `.end`. FFI-calling start alone would drop the reply.
- **ℹ️** `activate_project` still wants a `Folder*`, not wire `path`. `revert` runs on the **row** `self`, not the `for_rpc` singleton.
- **🚫** `_sync` suffix, `cnames` map, or dispatch trying `symbol` then `symbol + "_sync"`. The library maps the `add_class` string as the wire suffix.
- **🚫** Rename or overload an existing **in-process** method (not RPC-only) so FFI can reuse the name.
- **🚫** Change `Application.vala` for this walk.

---

## Phase 3 — `Response.retval`

**ℹ️** Split to [`RPC-8.5.3-DONE-rpc-response-value.md`](RPC-8.5.3-DONE-rpc-response-value.md). Add `retval`; keep `result`. Do not duplicate the contract here.

---

## `call_*` leftover (Phase 2)

- **🔷** `✔️` Production handlers have no `call_*` left (`ollmfilesd` has none).
- **🔷** `✔️` Dummy tests list FFI: `tests/rpc/values-test.vala`, `gi-test.vala`, `proxies-test.vala`.
- **🔷** `✔️` Win32/Android `Live/namespace.vala` stubs match Unix method names (empty bodies).
- **🔷** `✔️` `Request.dispatch` is `Ffi` then `Gi` — no `call_*` branch.

---

## Phase summary

- **🔷** `✔️` Packing helper + `args` rename (already in tree).
- **🔷** `✔️` **8.5.1** — migration inventory above (handlers + callers per method), then delete bags / `param` / `param_types`.
- **🔷** `✔️` **8.5.2** — (1) method table (2) `OLLMrpc.Ffi.dispatch` if listed, else `call_*` (3) `RPC-Daemon.hello` first; remaining methods later.
- **🔷** `✅` **8.5.3** — [`RPC-8.5.3-DONE-rpc-response-value.md`](RPC-8.5.3-DONE-rpc-response-value.md) — add `retval`; keep `result`.
- **🔷** `✅` **8.5.4** — [`RPC-8.5.4-DONE-rpc-retval-migrate.md`](RPC-8.5.4-DONE-rpc-retval-migrate.md) — migrate callers; drop `result`.
- **🔷** `✔️` Drop `call_*` after dummy tests list FFI (see leftover above).
- **ℹ️** Sub-plan files get **Remove** / **Replace with** / **Add** fences when this parent is confirmed. Phase 2 hunks are in this file.

---

## LLM notes

- **🚫** Dual-stack `param` + `args` “for compatibility” after a method is migrated.
- **🚫** Extra helpers around `args.get(i)`. Only **`OLLMrpc.args`**.
- **🚫** Extra helpers around FFI / signature walk / C-name. Only **`Ffi.dispatch`** and **`Ffi.pack`**.
- **🚫** Map `_sync` in `add_class` / `Ffi` / dispatch. Wire suffix string is the C method name (dots → underscores). Caller changes its call if names differ.
- **🚫** `Request.invoke`. Listed FFI is class `OLLMrpc.Ffi`.
- **🚫** One array per C type (`ivals`, `yvals`, …). One `Libffi.Arg[]`.
- **🚫** Name the vapi namespace `Ffi`. That collides with the class. Use `Libffi`.
- **🚫** Put `Ffi.vala` in `gi_src` / behind unix GI. Core sources, every platform.
- **🚫** Rewrite `Gi.vala` / `Gi.convert` in 8.5.2. `pack` is the reuse point (`Gi` extends `Ffi`); wire it later.
- **🚫** Make `pack` `static` — instance method for `Gi` to inherit.
- **🚫** Limit `pack` unpack to `hello`’s `i` / `s`. Same letters as `OLLMrpc.args`.
- **🚫** Long `if` chain in `pack` — `switch` on the tag, like `OLLMrpc.args`.
- **🚫** One-argument-per-line wraps on calls — keep the call / format string on one line; if wrapping, group remaining args (`line-length-breaking`).
- **🚫** Edit `ollmfilesd/Application.vala` for Phase 2. It already calls `Request.register(name, instance)`.
- **🚫** `handlers.set` / assign `handlers` from Application, tests, or Live examples. `Request.register` writes `handlers`.
- **🚫** Lease / `export` / `Serializable` checks inside `OLLMrpc.args`.
- **🚫** Revive `Notification.payload` as `GLib.Object` ([`8.3.3`](RPC-8.3.3-REJECTED-notification-gobject-payload.md)).
- **🚫** Start 8.5.2.2 before the registration table exists, or 8.5.2.3 before dispatch-if-listed works.
- **🚫** Start 8.5.2 before the CallParam consumer inventory is cleared, unless the user says otherwise.
- **🚫** Start 8.5.3 (reply `GLib.Value`) before FFI dispatch lands, unless the user says otherwise.
- **🚫** Convert every handler in 8.5.2.3 — first method is `RPC-Daemon.hello` only.
- **🚫** Drop `call_*` or the instance `handlers` map while dummy tests still emit `call_*`.
- **🚫** Keep `call_*` on a method after that method is on the FFI table (no dual path per method).
- **🚫** Put `Request` / `o` in the registered signature — dispatch prepends it.
- **🚫** Marshall a return value — `void` + `request.reply` only.
- **🚫** Static handler methods / a prefix on the registered name to mark instance vs static. Listed methods are instance methods.
- **🚫** Route these handlers through `Gi` / typelib `FunctionInfo.invoke` — that path stays for Gio-Menu and friends.
- **🚫** Change `Request.register`'s signature. Old boot and tests keep `register(name, instance)`.
- **🚫** Overload `register`. The new table is `add_class`. Live boot is `register_live`, not a `register` overload.
- **🚫** Infer live prefixes from GType vs leased GType, or from the `RPC-Live-` string. `register_live` writes the table.
- **🚫** Capital `O` / extra `o` in `args` for the live object. Id stays `Request.lease_id`.
- **🚫** Invent `Application.get_default()` / a second object → id map. Default instance is `handlers`. Lease is `Connection.export` → existing `leases` / `lease_ids`.
- **🚫** Make the caller send `lease_id` for default RPC objects (`RPC-Daemon.hello`). `lease_id == 0` means the registered default on this connection.
- **🚫** A process-wide lease table. Leases stay per-connection (`export` on the connection that received the call).
- **🚫** Turn `live_handles` on for ollmfilesd so `export` works. Drop the guard on `export`. The flag stays for wire live-handle encode / `RPC-Live-Remote` / subscribe.
- **🚫** Flag every straight field→`args` mapping for review. Implement **🔷** signatures from the inventory; stop only on a real mismatch with handler reads.
- **🚫** Put live lease ids in `args` — use **`Request.lease_id`**.
- **🚫** HashTable / Variant dict for HTTP query — plain GObject in `args.get(0)`, property walk.
- **🚫** Bump `Daemon.protocol` / bin protocol version for this cut — payload shape only (`param` → `args`); codec already has `ANY[]`.
- **🚫** Update `docs/plans/RPC-1.0-summary.md` until a sub-plan is done and archived.
- **🚫** Markdown tables in this plan — use the nested inventory bullets.
