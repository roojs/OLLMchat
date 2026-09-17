# RPC-1.9 — Method id lookups (options)

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Status:** **APPROVED** — **A** (register-time `dlsym`) then **B** (dispatch from the transport name-ref id; later FFI uses the bin slot cache).

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Prefix:** `RPC` (`libocrpc`) · see [`RPC-1.0-summary.md`](RPC-1.0-summary.md)

**Related:**

- **ℹ️** [`done/RPC-8.6-URGENT-rpc-bin-learn-method-names.md`](done/RPC-8.6-URGENT-rpc-bin-learn-method-names.md) — bin already sends `Request.method` as a uint16 name token after first use
- **ℹ️** [`docs/rpc-registration.md`](../rpc-registration.md) — `add_class` / `register` / FFI vs Gi
- **ℹ️** [`docs/bin-rpc-protocol.md`](../bin-rpc-protocol.md) — `NAME_REF_REG` / `NAME_REF` (v3.1)
- **ℹ️** `libocrpc/Ffi.vala` · `libocrpc/Request.vala` · `libocrpc/Gi.vala` · `libocrpc/Bin/Stream.vala`
- **ℹ️** [`RPC-1.10-vfunc-id-lookups.md`](RPC-1.10-vfunc-id-lookups.md) — vfunc numbered lookups (other direction)

**Slugs read for proposed Vala:** `temporary-variables`, `this-prefix`, `reducing-nesting`, `defensive-code-null-checks`, `method-names-new-methods`, `line-length-breaking`, `docblocks`, `underscore-prefix`, `property-initialization`, `gobject-construct-blocks`, `brace-placement`, `gee-hashmap-access`, `gee-arraylist-access`, `arraylist-for-strings`, `avoiding-nullable-types`, `debug-warning-statements`, `agent-compliance-gate` (+ `docs/code-documentation.md`)

---

## Purpose

- **🔷** Stop compiling a `GLib.Regex` and `dlsym`-ing the C symbol on every listed FFI call.
- **🔷** Do that work once in `Request.add_class` (startup / `rpc_register`).
- **🔷** `add_class` appends one `FfiSlot` to a lazy `Gee.ArrayList<FfiSlot>`. No C `Type[]` tables.
- **🔷** After that table exists, later bin FFI calls use the **transport name-ref id** (the uint16 from 8.6) → that slot. Not `"RPC-Folder.fetch_files"`.
- **🔷** If the token is already bound to an FFI slot, Ffi uses `slot` and does **not** hash `methods`. Miss stays `read_name_ref` (same as today).
- **🔷** No wire change. Client call sites stay `method = "RPC-File.read"`.
- **⏳** `🔷` C–F (constants, generator, handshake, two-level ids) stay later.
- **ℹ️** Vfunc numbered lookups are [`RPC-1.10-vfunc-id-lookups.md`](RPC-1.10-vfunc-id-lookups.md) — not a string-name cache in this file.
- **ℹ️** How hard **B** is, and the fences, are in **B** below.

---

## Current behaviour

- **🔷** Startup: each class `rpc_register()` calls `Request.add_class("RPC-Folder", typeof(Folder), "fetch_files", "siisSb", …)`.
- **🔷** That fills `Request.methods` — `HashMap<string, HashMap<string, string>>` (prefix → suffix → **arg signature**).
- **🔷** Boot also `Request.register("RPC-Folder", instance)` → `Request.handlers` string map.
- **🔷** Client constructs `new Request() { method = "RPC-Folder.fetch_files" }` (literal string every call site).
- **ℹ️** Bin encode (`Request.bin_write_prop` `method`): `write_name_ref` — first use introduces UTF-8 + uint16; later uses `TYPE_NAME_REF` + uint16 only ([8.6](done/RPC-8.6-URGENT-rpc-bin-learn-method-names.md)).
- **ℹ️** Bin decode: `read_name_ref` expands the uint16 **back to a string** and stores it on `Request.method`.
- **ℹ️** `Request.dispatch` splits that string on `.`, then `new Ffi(this).dispatch()`.
- **ℹ️** `Ffi.dispatch` splits again, hashes prefix + suffix in `Request.methods`, then builds a C symbol from the GType name and `g_module_symbol`s it **every call**.
- **ℹ️** Miss on FFI → `Gi.dispatch`. HTTP / NDJSON still use full method strings.

### Arg signature (what “D-Bus letters” means)

- **🔷** Not the method name. The **type of each extra FFI argument** after `(self, Request)`.
- **🔷** Same letters as `OLLMrpc.args`. One character per arg (except `S`, which is one `string[]` plus Vala’s hidden length).
- **ℹ️** `add_class("RPC-Folder", typeof(Folder), "fetch", "s", "fetch_files", "siisSb")`:
  - `fetch` → `"s"` — one string
  - `fetch_files` → `"siisSb"` — string, int, int, string, `string[]`+length, bool
- **ℹ️** Other in-tree examples: `""` (no extra args), `"is"` (`Daemon.hello`), `"ssissss"` (`Codebase.rpc_search`).
- **ℹ️** The docs call this D-Bus because the letters follow that alphabet (`s` string, `i` int, `b` bool, `t` uint64, `S` / `V` are our extras). It is still just a short signature string, like `siisSb`, not a second name table.

---

## Lookups per listed FFI call

Steady-state **bin** call (names already learned on this connection). First use of a method is worse (UTF-8 introduce + extra map inserts). HTTP / JSON skip the name-token path and keep the full string.

### Client (encode)

- **ℹ️** `write_gtype(Request)`: `gtype_to_alias` HashMap + `name_to_token` HashMap (type alias `"Request"`).
- **ℹ️** `bin_write` walks every GObject property (`id`, `method`, `args`, `lease-id`, …).
- **ℹ️** Each written property: `write_tag(prop_name)` → `name_to_token` HashMap (`"method"`, `"id"`, `"args"`, `"lease-id"` as seen).
- **ℹ️** Method value: `write_name_ref(this.method)` → `name_to_token` HashMap on the **full** `"RPC-Folder.fetch_files"` string.
- **ℹ️** Typical encode: **~5–7 string HashMap hits** (type alias + 3–5 property keys + 1 method name).
- **🔷** Caller still starts from a string. There is no client-side integer constant today.

### Server (decode)

- **ℹ️** `read_gtype`: array index into `client_names` / `server_names`, then `alias_to_gtype` HashMap.
- **ℹ️** Each property: `read_tag` is an array index (not a string hash) after first learn.
- **ℹ️** Each property: `GObjectClass.find_property(prop_name)` (GObject property quark / name table).
- **ℹ️** Method value: `read_name_ref` is an **array index → string**. The number is thrown away.
- **ℹ️** Typical decode: **1 type HashMap** + **~4 `find_property`** + **0 method HashMap** (the expensive part is re-creating the string).

### `Request.dispatch` + `Ffi.dispatch` (today)

- **ℹ️** Split `method` on `.` (string scan + two allocations).
- **ℹ️** `new Ffi(request)` (GObject construct).
- **ℹ️** Split **again** inside `Ffi.dispatch`.
- **ℹ️** `Request.methods.has_key(prefix)` then `.get(prefix).has_key(suffix)` then `.get(suffix)` — **3–4** nested string HashMap ops.
- **ℹ️** `Request.handlers.has_key` + `.get` — **2** more.
- **ℹ️** `Request.types.get(prefix)` — **1** more (GType for the C prefix).
- **ℹ️** Optional: `Request.live.has_key`, `connection.leases.has_key` / `.get`.
- **ℹ️** Then the work that **dwarfs** the maps (every call, not cached):
  - compile a `GLib.Regex` and camelCase-replace the GType name
  - `GLib.Module.open(null)` + `mod.symbol(c_name)` (`dlsym`)
  - `ffi_prep_cif` + `ffi_call`
- **🔷** Dispatch string HashMaps: **~6–9** per listed FFI call.
- **ℹ️** After **A** only: same maps + split; Regex / `dlsym` move to `add_class`. cif prep stays per call.
- **ℹ️** After **A+B** (later FFI on the same socket): decode still `read_name_ref`; Ffi does not split or hash `methods`. Token → slot → `rows.get(slot)`.

### Gi path (typelib / gnome-shell-rpc)

- **ℹ️** Same encode/decode as above.
- **ℹ️** `Gi.dispatch`: split; `Gi.types.has_key` + `.get`; `GI.Repository.find_by_gtype`; `ObjectInfo.find_method(method_name)` (and parent walk).
- **ℹ️** Namespace functions: `namespaces.contains` (list scan) + `find_by_name(ns, method)`.
- **ℹ️** No `add_class` row. **A** does not change Gi.
- **ℹ️** Vfunc hot path (name → hook) is [`RPC-1.10-vfunc-id-lookups.md`](RPC-1.10-vfunc-id-lookups.md).

---

## What 8.6 already did — and did not

- **ℹ️** Wire payload after first use is already a uint16. We are not sending `"RPC-Folder.fetch_files"` UTF-8 on every later call.
- **🔷** The later waste is expand → string → hash → Regex / `dlsym`. **A** only moves Regex / `dlsym`. **B** stops the expand → hash for listed FFI.
- **ℹ️** Tokens are **per connection**, even/odd by who first sent the name. They are **not** process-wide method ids.
- **🚫** Do not treat today’s name-table token as a stable ABI constant unless we pre-seed the table in a fixed order on both ends.
- **🔷** That is why **B** cannot fill `token → fn` inside `add_class`. The id does not exist until this socket first sees the name.

---

## A — Dense slot at `add_class` (not another string HashMap)

- **🔷** Do **not** add `HashMap<string, HashMap<string, uint64>>`. That is more string hashing, not less.
- **🔷** Call signature stays a **string** (`"s"`, `"is"`, `"siisSb"`). Do not pack it into an integer.
- **🔷** Two Gee collections only (plus the existing `methods` map):
  - `Gee.ArrayList<FfiSlot> rows` — one object per listed method
  - `Gee.HashMap<string, FfiOwner> classes` — one object per `add_class` prefix
- **🔷** Do **not** add C arrays (`FfiSlot[]`, `Object[]`, `uint8[]`, `int[]`).
- **🔷** Do **not** add `selves`, `live_classes`, or `class_ids`. `FfiOwner` holds `handler` + `live`. `FfiSlot.cls` points at that object.
- **🔷** `FfiSlot` / `FfiOwner` are small GObjects so they sit in Gee lists. Named here so they may be added.
- **🔷** Call signature stays a **string** on `FfiSlot.sig`.
- **🔷** Do **not** add `string[] prefixes`.
- **🔷** One `GLib.Regex` + one `GLib.Module.open` per `add_class` call (once per class at `rpc_register`).
- **🔷** Lazy: `if (rows == null) { rows = new Gee.ArrayList<FfiSlot>(); … }`.
- **🔷** Existing `methods` map keeps the **first-learn / HTTP** string path only. Inner value is the index into `rows`.
- **🔷** `Ffi.dispatch` uses `rows.get(slot)`. No Regex / `dlsym`.
- **🔷** `row.fn == 0` means the symbol was not in the process.
- **🔷** No new methods. No wire / client API change.
- **ℹ️** Static fields stay **uninitialized**. First `add_class` / `register` assigns them (same pattern as `handlers`).
- **ℹ️** `add_class` already runs on the process that lists the methods (ollmfilesd handlers; live handlers in `libocrpc` when `OLLMrpc.rpc_register(true)`).
- **ℹ️** Only `Ffi.vala` reads `Request.methods` values today (signature string).
- **💩** Do not also cache `ffi_prep_cif` / `Libffi.Cif` in this cut.
- **💩** Do not `GLib.critical` per missing symbol inside `add_class`.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/Request.vala` — `FfiSlot` / `FfiOwner` + Gee tables

**Why:** One list of method rows. Class handler/live live on `FfiOwner`, not extra arrays.

**Where:** namespace in `Request.vala`, immediately above `public class Request`. Then class body after `methods`.

**Depends on:** none.

#### Add

Before `public class Request`. Two small GObjects.

```vala
	/**
	 * Handler singleton for one ''add_class'' prefix (e.g. RPC-Folder).
	 *
	 * {@link Request.register} sets {@link handler}.
	 * {@link Request.register_live} sets {@link live}.
	 */
	public class FfiOwner : GLib.Object
	{
		public GLib.Object handler { get; set; }
		public bool live { get; set; default = false; }
	}

	/**
	 * One listed FFI method: C pointer, call signature, and class.
	 *
	 * Appended by {@link Request.add_class}. {@link Request.slot} is the
	 * index in {@link Request.rows}. ''fn'' is ''0'' when the symbol
	 * was missing.
	 */
	public class FfiSlot : GLib.Object
	{
		public uint64 fn { get; set; default = 0; }
		public string sig { get; set; default = ""; }
		public FfiOwner cls { get; set; }
	}

```

#### Remove

```vala
		/** Wire object prefix → (method suffix → D-Bus signature). */
		public static Gee.HashMap<string, Gee.HashMap<string, string>> methods;
```

#### Replace with

Same map, inner value is the index into `rows`. Gee only — no C arrays.

```vala
		/** Wire object prefix → (method suffix → index in {@link rows}). */
		public static Gee.HashMap<string, Gee.HashMap<string, int>> methods;

		/**
		 * Listed FFI methods, index from {@link add_class}.
		 *
		 * Null until the first {@link add_class}.
		 */
		public static Gee.ArrayList<FfiSlot> rows;

		/**
		 * Wire prefix → {@link FfiOwner} (boot + {@link register}).
		 *
		 * Null until the first {@link add_class}.
		 */
		public static Gee.HashMap<string, FfiOwner> classes;
```

### 2. `libocrpc/Request.vala` — `add_class`: append a slot

**Why:** Regex + `dlsym` at register. Hot path is an array index.

**Where:** `add_class` — init block, then the method/signature loop.

**Depends on:** §1.

##### Part 1 — Init `methods` as `int` slots

#### Remove

```vala
			if (types == null) {
				types = new Gee.HashMap<string, GLib.Type>();
				methods = new Gee.HashMap<string, Gee.HashMap<string, string>>();
			}
			types.set(name, type);
			if (!methods.has_key(name)) {
				methods.set(name, new Gee.HashMap<string, string>());
			}
```

#### Replace with

Inner map is slot ids. Lazy-init Gee tables. One `FfiOwner` per prefix.

```vala
			if (types == null) {
				types = new Gee.HashMap<string, GLib.Type>();
				methods = new Gee.HashMap<string, Gee.HashMap<string, int>>();
				rows = new Gee.ArrayList<FfiSlot>();
				classes = new Gee.HashMap<string, FfiOwner>();
			}
			types.set(name, type);
			if (!methods.has_key(name)) {
				methods.set(name, new Gee.HashMap<string, int>());
			}
			if (!classes.has_key(name)) {
				classes.set(name, new FfiOwner());
			}
			var cls = classes.get(name);
```

##### Part 2 — Loop: `dlsym` and append

#### Remove

```vala
			var l = va_list();
			while (true) {
				var method = l.arg<string>();
				if (method == null) {
					break;
				}
				methods.get(name).set(method, l.arg<string>());
			}
```

#### Replace with

One Regex and one `Module.open` for this `add_class`. Store the call signature string as-is.

```vala
			var c_prefix = new GLib.Regex(
				"(?<=[a-z0-9])([A-Z])|(?<=[A-Z])([A-Z][a-z])"
			).replace(type.name(), -1, 0, "_\\1\\2").down();
			var mod = GLib.Module.open(null, GLib.ModuleFlags.LAZY);
			var l = va_list();
			while (true) {
				var method = l.arg<string>();
				if (method == null) {
					break;
				}
				var signature = l.arg<string>();
				var fn = (void*) null;
				if (mod != null) {
					mod.symbol(c_prefix + "_" + method.replace(".", "_"), out fn);
				}
				methods.get(name).set(method, rows.size);
				rows.add(new FfiSlot() {
					fn = (uint64) fn,
					sig = signature,
					cls = cls
				});
			}
```

### 3. `libocrpc/Ffi.vala` — class doc + `dispatch`: `rows.get(slot).fn`

**Why:** Hot path must not rebuild the symbol name.

**Where:** class docblock sentence on symbol lookup; `dispatch` from the Regex through `mod.symbol`.

**Depends on:** §1, §2.

##### Part 1 — Class overview sentence

#### Remove

```vala
	 * {@link Request.dispatch} constructs {@link Ffi} with the inbound
	 * {@link Request} and calls {@link dispatch}. That method looks up
	 * the C symbol and calls it. Unlisted prefixes return false so
	 * {@link Request.dispatch} can try {@link Gi}.
```

#### Replace with

Pointer comes from the `add_class` slot, not a per-call `dlsym`.

```vala
	 * {@link Request.dispatch} constructs {@link Ffi} with the inbound
	 * {@link Request} and calls {@link dispatch}. That method calls
	 * {@link Request.rows}.get ({@link Request.slot}).fn. Unlisted
	 * prefixes return false so {@link Request.dispatch} can try
	 * {@link Gi}.
```

##### Part 2 — `dispatch` after handler / lease `self`

#### Remove

```vala
			var camel = new GLib.Regex(
				"(?<=[a-z0-9])([A-Z])|(?<=[A-Z])([A-Z][a-z])"
			);
			var symbol = camel.replace(
				Request.types.get(object_name).name(), -1, 0, "_\\1\\2"
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
```

#### Replace with

Array index. `0` is the same miss as today’s failed `symbol`.

```vala
			var fn = (void*) Request.rows.get(this.request.slot).fn;
			if (fn == null) {
				GLib.critical("RPC dispatch: no symbol for %s", this.request.method);
				return true;
			}
```

**ℹ️** String path in **B** §7 sets `this.request.slot` from `methods` before this block.

### 2b. `libocrpc/Request.vala` — `register` / `register_live`: fill `FfiOwner`

**Why:** `FfiSlot.cls` is the class object. No extra arrays.

**Where:** end of `register`; end of `register_live`.

**Depends on:** §1.

##### Part 1 — `register`

#### Remove

```vala
			handlers.set(name, target);
		}
```

#### Replace with

`add_class` already created `classes[name]`.

```vala
			handlers.set(name, target);
			if (classes != null && classes.has_key(name)) {
				classes.get(name).handler = target;
			}
		}
```

##### Part 2 — `register_live`

#### Remove

```vala
			live.set(name, true);
		}
```

#### Replace with

```vala
			live.set(name, true);
			if (classes != null && classes.has_key(name)) {
				classes.get(name).live = true;
			}
		}
```

**ℹ️** `handlers` / `live` string maps stay for anything that still uses them. FFI dispatch uses `row.cls.handler` / `row.cls.live`.

---

## B — Transport name-ref id → dense slot (skip the method string)

- **🔷** Bind the connection’s name-ref uint16 to the **A slot** (`int`).
- **🔷** One `Stream` map: `HashMap<uint16, int> ref_slots`. Integer → integer. No string keys.
- **🔷** Inbound `Request.slot` (`-1` = unbound). `Ffi` uses `rows.get(slot)`.
- **🔷** After `read_name_ref`, if `ref_slots` has that wire id, set `Request.slot`. Ffi then skips the `methods` hash.
- **🔷** If `ref_slots` does not have it, **stop**. Same as today: `Request.method` is the string. No split, no `methods` lookup, no bind in decode.
- **🔷** Gi / unbound / HTTP still go through the string. `Notification.method` always expands.
- **🔷** `Ffi.dispatch` already looks up `methods` on the string path (HTTP / first learn / tests). That sets `slot` and binds `ref_slots` for the next call.
- **🚫** Do not look up `methods` in `bin_read_prop` to invent a slot.
- **🚫** Do not reimplement `read_name_ref` (even/odd name tables) in `Request`.
- **ℹ️** How easy: **medium, not a spec bump.** `methods` string map is **only** the Ffi / HTTP fallback. After bind, Ffi does zero string HashMaps.
- **ℹ️** Cannot pre-bind at `add_class`: wire ids are even/odd and first-use order on **this** `Stream`.
- **ℹ️** Interned `client_names` / `server_names` is still an array index. “Do not decode” means **do not hash** `methods` for FFI.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 4. `libocrpc/Request.vala` — inbound `slot`

**Why:** One integer. **A** tables hold pointer + call sig + `class_id`.

**Where:** class body, after `lease_id`. Not a GObject property — `bin_write` must not see it.

**Depends on:** §1.

#### Add

Plain field. `-1` means “use `Request.method`”. `0` is a valid first slot.

```vala
		/**
		 * Inbound bin only: index into {@link rows} ({@link Gee.ArrayList.get}).
		 *
		 * ''-1'' means look up {@link methods} from {@link method}.
		 * Not on the wire.
		 */
		public int slot = -1;
```

### 5. `libocrpc/Bin/Stream.vala` — per-connection token → slot

**Why:** The transport id lives on this `Stream`. Bind once per name per socket.

**Where:** class body, after `name_to_token`.

**Depends on:** §1.

#### Add

After the `name_to_token` field. Integer keys and values only.

```vala
		/**
		 * Name-ref wire id → index in {@link OLLMrpc.Request.rows}
		 * ({@link Gee.ArrayList.get}).
		 *
		 * Filled when {@link OLLMrpc.Ffi.dispatch} first resolves a
		 * listed method on this stream. Missing means expand the
		 * string (same as today).
		 */
		internal Gee.HashMap<uint16, int> ref_slots { get; set;
			default = new Gee.HashMap<uint16, int>(); }
```

### 6. `libocrpc/Request.vala` — `bin_read_prop` `method`: set `slot` when bound

**Why:** Same decode as today. If this stream already bound the token, set `slot` so Ffi skips `methods`.

**Where:** `bin_read_prop` `case "method"`.

**Depends on:** §4, §5.

#### Remove

```vala
			case "method":
				this.method = ctx.read_name_ref(type_byte);
					return;
```

#### Replace with

Always `read_name_ref`. Then `slot` only if `ref_slots` already has the wire id. No `methods` lookup.

```vala
			case "method":
				this.method = ctx.read_name_ref(type_byte);
				if (!ctx.name_to_token.has_key(this.method)) {
					return;
				}
				var wire = ctx.name_to_token.get(this.method);
				if (ctx.ref_slots.has_key(wire)) {
					this.slot = ctx.ref_slots.get(wire);
				}
				return;
```

### 7. `libocrpc/Request.vala` — `dispatch` + `libocrpc/Ffi.vala` — `dispatch`: prefer `slot`

**Why:** Bound inbound request must not require `method.length > 0`.

**Where:** start of `Request.dispatch`; start of `Ffi.dispatch` object/method split.

**Depends on:** §4, §6.

##### Part 1 — `Request.dispatch` empty-method guard

#### Remove

```vala
			if (this.method.length == 0) {
				GLib.critical("RPC dispatch: method not set");
				return false;
			}

			var dot = this.method.index_of_char('.');
			if (dot < 1 || dot == this.method.length - 1) {
				GLib.critical("RPC dispatch: method must be RPC-Object.method, got '%s'",
					this.method);
				return false;
			}

			if (new Ffi(this).dispatch()) {
				return true;
			}
```

#### Replace with

`slot >= 0` is listed FFI from the token. String path only when decode did not bind.

```vala
			if (this.slot >= 0) {
				return new Ffi(this).dispatch();
			}
			if (this.method.length == 0) {
				GLib.critical("RPC dispatch: method not set");
				return false;
			}

			var dot = this.method.index_of_char('.');
			if (dot < 1 || dot == this.method.length - 1) {
				GLib.critical("RPC dispatch: method must be RPC-Object.method, got '%s'",
					this.method);
				return false;
			}

			if (new Ffi(this).dispatch()) {
				return true;
			}
```

##### Part 2 — `Ffi.dispatch` listed-method + signature

#### Remove

```vala
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
```

#### Replace with

`slot >= 0` already chosen. Else the same `methods` lookup Ffi does today (HTTP / first learn / tests). That **sets** `slot`. The `ref_slots.set` below is the per-connection **bin slot cache**: next `TYPE_NAME_REF` on this stream hits §6 and Ffi skips this lookup.

```vala
			if (this.request.slot < 0) {
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
				this.request.slot = Request.methods.get(object_name)
					.get(method_name);
				// Bin slot cache: next NAME_REF on this stream skips
				// the methods lookup (Request.bin_read_prop sets slot).
				if (this.request.connection.bin != null
					&& this.request.connection.bin.name_to_token.has_key(
						this.request.method
					)) {
					this.request.connection.bin.ref_slots.set(
						this.request.connection.bin.name_to_token.get(
							this.request.method
						),
						this.request.slot
					);
				}
			}
			var row = Request.rows.get(this.request.slot);
			var signature = row.sig;
			var self = row.cls.handler;
```

**ℹ️** Keep the existing `while (offset < signature.length)` walks. `handlers.get` / `live.has_key` become `row.cls.handler` / `row.cls.live`. Symbol block is §3 (`row.fn`).

**ℹ️** `object_name` stays `""` on the bound path. `read_name_ref` still set `Request.method`, so `GLib.critical` lines that print it keep working.

---

## Later options (not this cut)

### C — Hand-written method constants

- **⏳** `🔷` Client sends `const uint16` / enum. Server dense table.
- **ℹ️** ~40 listed FFI methods. Gi / gnome-shell-rpc is not a closed set.

### D — Precompiler / generated table

- **⏳** `🔷` Generate ids + `FfiEntry[]` from `add_class` lists.

### E — Handshake catalog (server assigns ids)

- **⏳** `💩` After connect / hello: server sends listed methods with dense ids.

### F — Two-level object id + method id

- **⏳** `💩` Wire two uint16s. `objects[5].methods[3]`. Spec bump.

### G — moved

- **ℹ️** Wrong lead (cache another string map). Walkthrough + numbered wire path: [`RPC-1.10-vfunc-id-lookups.md`](RPC-1.10-vfunc-id-lookups.md).

---

## Open points

- **🔷** **A** (`FfiSlot` / `FfiOwner`, Gee `rows` + `classes`) and **B** (`ref_slots` bin slot cache, `Request.slot`) approved.
- **⏳** `💩` Also cache cif prep in a later pass?
- **⏳** `🔷` After A+B: C/D/E for a client integer, or stop?
- **ℹ️** Vfuncs: [`RPC-1.10-vfunc-id-lookups.md`](RPC-1.10-vfunc-id-lookups.md).

---

## Suggested order

1. **⏳** Approve **A** + **B** (this proposal).
2. **⏳** Apply **A** §1–§3, then **B** §4–§7.
3. **⏳** `meson test -C build --suite rpc` — `test-rpc-bin` (second encode still compact), FFI tests, one Gi call (string path still works).
4. **⏳** Later C–F.
5. **ℹ️** Vfuncs: [`RPC-1.10-vfunc-id-lookups.md`](RPC-1.10-vfunc-id-lookups.md).

---

## LLM notes

- **🔷** **A** + **B** approved — apply §1–§7.
- **🚫** No new methods. Named types: `FfiSlot`, `FfiOwner`. Named fields: `rows`, `classes`, `slot`, `ref_slots`.
- **🚫** Do not name the prefix object `FfiClass` — that is GObject’s class struct for `{@link Ffi}` (`_OLLMrpcFfiClass`).
- **🚫** Do **not** add C arrays, `selves`, `live_classes`, `class_ids`, `meta`, or `string[] prefixes`.
- **🚫** Do **not** pack the call signature into an integer.
- **🚫** Do not change the bin byte layout. Do not skip-string inside `Notification.bin_read_prop`.
- **🚫** Do not look up `methods` or reimplement `read_name_ref` in `bin_read_prop`.
- **ℹ️** Vfunc numbered path is [`RPC-1.10-vfunc-id-lookups.md`](RPC-1.10-vfunc-id-lookups.md).
- **ℹ️** `Call.Base` / Ollama HTTP is a different stack.
