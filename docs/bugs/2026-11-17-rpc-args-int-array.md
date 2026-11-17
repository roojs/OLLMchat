# RPC args: pack `int[]` as `ai` and `int64[]` as `ax`

**Status:** ⏳ opened — `ai` and `ax` shipped in `6d8fbcff` and crash. `int[]` has no GLib type, and `args` never receives the length.

**Pointer:** `docs/bug-fix-process.md`, [`docs/bin-rpc-protocol.md`](../bin-rpc-protocol.md), [`libocrpc/namespace.vala`](../../libocrpc/namespace.vala), [`libocrpc/android/namespace.vala`](../../libocrpc/android/namespace.vala), [`libocrpc/Ffi.vala`](../../libocrpc/Ffi.vala), [`libocrpc/Bin/StreamValue.vala`](../../libocrpc/Bin/StreamValue.vala), [`tests/rpc/values-test.vala`](../../tests/rpc/values-test.vala)

---

## Problem

- 🔷 `OLLMrpc.args` should take an `int[]` when the signature letter is `ai`, the same way `as` takes a `string[]`.
- 🔷 `OLLMrpc.args` should take an `int64[]` when the signature letter is `ax`, in the same change. `x` is already the scalar `int64` letter.
- 🔷 A caller that is sending agent ids should pass that array. Building a `GLib.Variant` of type `ai` by hand is the packing the helper exists to hide.
- 🔷 **Actual:** `to_value` has `as` and rejects `ai` and `ax` as unknown types. Argus builds the variant itself and passes it as `v`.

```vala
var builder = new GLib.VariantBuilder(new GLib.VariantType("ai"));
foreach (var id in agent_ids) {
	builder.add_value(new GLib.Variant.int32(id));
}
args = OLLMrpc.args("ovb", task, builder.end(), false);
```

- 🔷 **Expected:**

```vala
int[] ids = { 3, 9 };
args = OLLMrpc.args("oaib", task, ids, false);

int64[] history_ids = { (int64) 3, (int64) 9 };
args = OLLMrpc.args("ax", history_ids);
```

---

## Evidence

- ✔️ `libocrpc/namespace.vala` `to_value` packs `as` / `S` from a `string[]` and `x` from an `int64`. The `default` arm is `GLib.error("unknown D-Bus type %s", tag)`. `VariantType.string_scan` accepts `ai` and `ax` as one complete type each, then `to_value` hits that default.
- ✔️ Android compiles `libocrpc/android/namespace.vala` instead of `namespace.vala`. Its `to_value` has the same `as` / `x` arms and the same default. The cursor is `(*cursor).arg<…>()` rather than `l.arg<…>()`.
- ✔️ `tests/rpc/values-test.vala` already checks `OLLMrpc.args("as", names)` round-trips a `string[]`. There is no `ai` or `ax` check.
- ✔️ The wire already has both numeric-array bodies. `Bin/StreamValue.vala` writes a `GLib.Variant` of type `ai` with `write_numeric_array` (`GLib.Type.INT`) and type `ax` the same way (`GLib.Type.INT64`). `read_array` builds those variants back with `Variant.new_fixed_array` (`"i"` and `"x"`). It does not return a boxed `int[]` or `int64[]`.
- ✔️ Dispatch does not have an `ai` or `ax` arm. `Ffi.vala` passes a `string[]` for `as` as one pointer. Letter `S` is the one that also passes the array length, because a Vala array parameter is pointer plus length. The slot-count walk treats every `string_scan` type as one FFI slot. `ai` / `ax` have to be counted as two slots there, or the later walk writes past `slots`.
- ✔️ Argus call sites that build the variant, and the server methods that demand it, are `int` ids (`ai`), not `int64`:
  - `argusrm/controller/store/Distributable.vala` `submit` — `Task.submit` as `ovb`.
  - `argusrm/controller/store/TaskTarget.vala` `run_script` and `run_command` — same `ovb` packing.
  - `argusrm/server/SQT/Task.vala` `submit` (`ovb`) and `target` (`iv`). Both take a `GLib.Variant` and reject it unless `is_of_type("ai")`.

---

## Root cause

- ✔️ `ai` and `ax` were left as a `Variant` the caller constructs. `args` never grew either letter, so every int array goes through `VariantBuilder` and signature `v`. The `int64[]` letter is the same gap; the wire body for `ax` is already there.

---

## Proposed fix

- 🔷 `args("ai", ids)` packs an `int[]`. `args("ax", wides)` packs an `int64[]`.
- 💩 The bytes on the wire stay the numeric-array encoding that a `Variant` `ai` or `ax` already uses. An old caller that still sends `v` and a new caller that sends `ai` or `ax` produce the same body.
- 💩 A Vala method parameter `int[]` or `int64[]` is pointer plus length, same as `S` for `string[]`. Each letter is one wire value and two FFI slots. `read_array` can keep returning the `Variant`; the dispatch arm copies the ints out of it. Signature `v` stays for variants that are not one of these arrays.
- 💩 Each signature walk special-cases its own two-letter prefix **before** `string_scan`, the way `S` is special-cased before it. `string_scan` would consume `ai` or `ax` as one complete type and the count walk would allocate one slot.
- 🔷 The FFI arms stay separate. `ai` and `ax` do not share a branch or a `wide` flag.
- 🚫 Argus stays on `VariantBuilder` and signature `v`. That tree is not this change.

#### Add — `libocrpc/namespace.vala`, `to_value`, next to the `as` arm

```vala
case "ai":
	var ai_val = GLib.Value(typeof(int[]));
	ai_val.set_boxed(l.arg<int[]>());
	return ai_val;

case "ax":
	var ax_val = GLib.Value(typeof(int64[]));
	ax_val.set_boxed(l.arg<int64[]>());
	return ax_val;
```

#### Add — `libocrpc/android/namespace.vala`, `to_value`, next to the `as` arm

Same arms. Android pulls the varargs cursor through `*cursor`.

```vala
case "ai":
	var ai_val = GLib.Value(typeof(int[]));
	ai_val.set_boxed((*cursor).arg<int[]>());
	return ai_val;

case "ax":
	var ax_val = GLib.Value(typeof(int64[]));
	ax_val.set_boxed((*cursor).arg<int64[]>());
	return ax_val;
```

#### Add — `libocrpc/Bin/StreamValue.vala`, the writer, before the `GLib.Variant` arm

An `int[]` or `int64[]` value uses the writer the matching variant already uses.

```vala
if (val.type() == typeof(int[])) {
	int[] nums = (int[]) val;
	StreamValue.write_numeric_array(ctx, GLib.Type.INT,
		nums.length, nums, sizeof(int));
	return;
}
if (val.type() == typeof(int64[])) {
	int64[] wides = (int64[]) val;
	StreamValue.write_numeric_array(ctx, GLib.Type.INT64,
		wides.length, wides, sizeof(int64));
	return;
}
```

#### Add — `libocrpc/Ffi.vala`, the slot-count walk, next to the `S` arm

One wire value, two FFI slots. `as` and `ay` stay on `string_scan` (one slot).

```vala
if (rest.has_prefix("ai")) {
	offset += 2;
	n_wire += 1;
	n_slots += 2;
	continue;
}
```

#### Add — `libocrpc/Ffi.vala`, the slot-count walk, after the `ai` arm

```vala
if (rest.has_prefix("ax")) {
	offset += 2;
	n_wire += 1;
	n_slots += 2;
	continue;
}
```

#### Add — `libocrpc/Ffi.vala`, the signature walk, next to the `S` arm

One wire value, then the pointer and the length. `dup_variant` matches the call `StreamValue` already uses for a variant value.

```vala
if (rest.has_prefix("ai")) {
	var ai_val = this.request.args.get(ai);
	int[] nums = {};
	if (ai_val.type() == typeof(int[])) {
		nums = (int[]) ai_val.get_boxed();
	}
	if (ai_val.type() == typeof(GLib.Variant)) {
		var variant = ai_val.dup_variant();
		nums = new int[variant.n_children()];
		for (var n = (size_t) 0; n < variant.n_children(); n++) {
			nums[n] = variant.get_child_value(n).get_int32();
		}
	}
	var pin_i = pin.length;
	pin.resize(pin_i + 1);
	pin[pin_i] = GLib.Value(typeof(int[]));
	pin[pin_i].set_boxed(nums);
	slots[2 + si].set_pointer(pin[pin_i].get_boxed());
	atypes[2 + si] = Libffi.POINTER;
	slots[2 + si + 1].set_int32(nums.length);
	atypes[2 + si + 1] = Libffi.SINT32;
	offset += 2;
	si += 2;
	ai += 1;
	continue;
}
```

#### Add — `libocrpc/Ffi.vala`, the signature walk, after the `ai` arm

```vala
if (rest.has_prefix("ax")) {
	var ax_val = this.request.args.get(ai);
	int64[] wides = {};
	if (ax_val.type() == typeof(int64[])) {
		wides = (int64[]) ax_val.get_boxed();
	}
	if (ax_val.type() == typeof(GLib.Variant)) {
		var variant = ax_val.dup_variant();
		wides = new int64[variant.n_children()];
		for (var n = (size_t) 0; n < variant.n_children(); n++) {
			wides[n] = variant.get_child_value(n).get_int64();
		}
	}
	var pin_i = pin.length;
	pin.resize(pin_i + 1);
	pin[pin_i] = GLib.Value(typeof(int64[]));
	pin[pin_i].set_boxed(wides);
	slots[2 + si].set_pointer(pin[pin_i].get_boxed());
	atypes[2 + si] = Libffi.POINTER;
	slots[2 + si + 1].set_int32(wides.length);
	atypes[2 + si + 1] = Libffi.SINT32;
	offset += 2;
	si += 2;
	ai += 1;
	continue;
}
```

- 💩 `offset += 2` is that letter's own prefix check, not `string_scan`. `f` / `S` / `V` stay single letters checked first so they are not swallowed here. `ai` does not match `as` or `ay`.
- 🚫 Do not fold the `ai` and `ax` FFI arms into one branch.
- 🚫 Do not edit Argus. `Task.submit` and `Task.target` keep `v` until that project changes them.
- 🚫 Do not add `au` / `at` / `af` / `ad` in this change. The ask is `int[]` and `int64[]`.

---

## Attempts / changelog

- ℹ️ 2026-11-17: read `to_value`, `Ffi.pack`, and `StreamValue` write/read. No library change in this log.
- ℹ️ 2026-11-17: scope grew to `ax` (`int64[]`) in the same change. Android `to_value` and the FFI slot-count walk are in the proposal. Still no library change.
- ℹ️ 2026-11-17: FFI `ai` and `ax` are separate arms again. The shared `wide` branch is out.
- ℹ️ 2026-11-17: Argus is left unchanged. The letters land in `libocrpc` only.

## Next

- 🚫 The adds above are already in `6d8fbcff`. They are the crash. Do not apply them again.

## Shipped code crashes

- ✔️ `typeof(int[])` is `G_TYPE_INVALID` (`0`). Vala warns: arrays have no `GLib.Type`, except `string[]`. `/tmp/argus-ai-probe` printed `int[] type 0`.
- ✔️ `to_value` for `ai` compiles to `g_value_init(..., G_TYPE_INVALID)`, `va_arg(l, gint*)`, `g_value_set_boxed`. The caller is `oll_mrpc_args("ai", pointer, NULL)`. The length variable is not an argument. Assigning `l.arg<int[]>()` to an `int[]` does not compile: `invalid array_length for given dimension`.
- ✔️ Casting that boxed value back to `int[]` sets the length to `-1`. `_vala_array_dup2` then returns `NULL`. `tests/rpc/values-test.vala` checks `got_ids.length == 2`.
- ✔️ `build/tests/test-rpc-values` prints `type id '0' is invalid`, then `cannot initialize GValue with type '(null)'`, then fails `args strv length` and returns before the `ai` checks.
- ✔️ Dispatch pins the same way. `Ffi.vala` does `GLib.Value(typeof(int[]))`, `set_boxed`, `get_boxed`. `get_boxed` fails, so the Vala method is called with a null data pointer. `g_value_set_boxed` and `g_value_get_boxed` are the criticals in the journal.
- ✔️ Argus `Task.submit` (`oaib`) died there. `argusrm-server` SEGV in `argus_server_sqt_task_submit` at the `foreach` over `agent_ids` (`server/SQT/Task.vala`). The controller toast is `Could not queue task: Client: disconnected`.
- ℹ️ `string[]` is fine. It is `G_TYPE_STRV`, and the writer uses `g_strv_length`.
- ℹ️ `Gi2.vala` already carries a numeric array as a `GLib.Variant` of type `ai` and keeps the bytes in a `GLib.Bytes` slab (`boxed_keep`) for the call. That path does not use `typeof(int[])`.
- 💩 A fix has to store something that has a GType and a length. A variant of type `ai`, pinned the way `Gi2.vala` pins it, matches the wire body `StreamValue` already writes. `args("ai", ids)` cannot do that by itself: the length never arrives. A typed parameter is the only place Vala passes the length. This note does not change `libocrpc`.

## A bad argument must not kill the process

- 🔷 The process that died was the server. `argusrm-server` SEGV twice in `task_submit`. The controller stayed up. It logged the same `type id 0` / `g_value_set_boxed` critical while packing, then `Connection refused` after the server was gone, and toasted `Client: disconnected`.
- 🔷 The controller's `ai` value was already invalid, because `to_value` uses the same `G_TYPE_INVALID` init. That is bad output from the library, not a hostile client.
- 🔷 The server still must not crash on it. `Ffi.vala` calls the method after `get_boxed` has failed and the pointer slot is null. `typeof(int[])` is `0`, so an unset value also matches the `int[]` branch. A bad `ai` or `ax` has to be an RPC error reply. It must not be a SEGV in the method.
- ✔️ `ai` and `ax` each take the array pointer and then the length. The value stored is one `GLib.Variant` (`ai` or `ax`). Dispatch replies `INVALID_PARAMS` and returns when that value is missing or the wrong type, before `cif.call`.
