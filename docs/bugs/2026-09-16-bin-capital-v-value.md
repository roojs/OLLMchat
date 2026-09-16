# Bin / args: capital-`V` Value (type + data → `GLib.Value`)

**Status:** ✔️ applied + consumer migrated — `value-v-gate` PASS; await user verify  
**Hit:** 2026-09-16 — gnome-shell-rpc Transition / Interval / ease corridor  
**Component:** `libocrpc` — `Bin.StreamValue`, `args` / `val`, `Ffi.pack`, protocol § type bytes  
**Consumer gate:** `gnome-shell-rpc/tests/call-sync-repro/value-v-gate` (**PASS**)  
**Consumer context:** Transition/Interval set_* use `args("V")` → stock Gi (no `bsid`)

---

## Problem

🔷 Consumers need to move a **typed value** across the RPC (fundamentals now; boxed `Graphene.*` / colors later) and rebuild a compositor-local `GLib.Value` for stock APIs (`set_to_value`, `set_final_value`, `child_set_property`, …).

🔷 Today they pick among three bad or incomplete options:

1. **Kind casting** — wire `bsid` (bool + kind letter + int + double); Helper `switch (kind)` rebuilds the `GValue`. Duplicated on client (`to_wire`) and server (`from_wire`). Does not scale to boxed.
2. **`ay` memcpy of the `GValue` struct** — generator default for `GObject.Value`; cannot work across processes.
3. **Flattened wire row + Gi pin** — `StreamValue` already writes type byte + payload; Gi pins that row for GIR `GValue*` (`gvalue-in-gate` PASS). Fine for typelib invoke; **not** a first-class Helper / generator / args letter, so consumers still invent (1).

🔷 Expected: one OPC **capital-`V` Value** — wrap that sends **Type + Data** on the wire and decodes to a `GLib.Value` on the peer. Helpers take `GLib.Value`; generator packs `V`, not `ay` / not `bsid`.

🔷 Actual: `args` / `Ffi` have lowercase **`v` = `GLib.Variant`** only. No capital-`V`. Protocol has no named Value wrap beyond “whatever fundamental `StreamValue` emitted.”

---

## Evidence

ℹ️ `OLLMrpc.args` / `to_value` (`libocrpc/namespace.vala`): letters include `v` → Variant; **no `V`**. Unknown tag → `GLib.error`.

ℹ️ `Ffi.pack` (`libocrpc/Ffi.vala`): same letter set; no `V` → falls through to int32 default.

✔️ 2026-09-16 — Confirmed **capital-`V` maps to nothing** in this tree:
- No `case "V"` / `has_prefix("V")` under `libocrpc/`.
- Signature scanners special-case only `"f"` and `"S"` before `GLib.VariantType.string_scan` (D-Bus has no `V`; scan of `"V"` is invalid).
- Wire type bytes are GLib fundamentals / reserved tokens (`NAME_REF*`, `TOKEN_REG_TYPE`) — none are the letter `V`.

ℹ️ `Bin.StreamValue.write` already encodes **type byte + payload** for fundamentals / `GLib.Bytes` / objects. That *is* Type+Data for a flattened row — but:

- Helper signatures cannot say `"V"` (D-Bus `VariantType.string_scan("V")` fails; not special-cased like `"f"` / `"S"`).
- Consumers therefore invent kind switches (`Helper-Transition` `bsid`) instead of `bV` / `V`.
- Boxed held types that are not `GLib.Bytes` → `unsupported bin value type` (no GType+payload path).

ℹ️ Consumer archive:
[`gnome-shell-rpc/docs/bugs/done/2026-09-16-transition-interval-gvalue-wire.md`](file:///home/alan/git/gnome-shell-rpc/docs/bugs/done/2026-09-16-transition-interval-gvalue-wire.md)
— chose `bsid` relay; explicitly rejected “hold `GLib.Value` in `Request.args`” as a *generator* design without a named OPC Value type.

ℹ️ Gi GObject.Value pin remains valid for typelib `GValue*` IN/OUT (`done/2026-09-11-FIXED-gi-gvalue-property-args.md`). This bug does **not** reopen that. Capital-`V` is the **intentional** API for Helpers + generator packing.

---

## Root cause

✔️ Missing first-class **Value** on the RPC layer: signature letter + Ffi pack + documented wire shape (Type + Data → `GLib.Value`). Flattened `StreamValue` rows and Gi pin are not a substitute for that API, so gnome-shell-rpc grows per-site casting.

---

## Proposed fix

🔷 **Capital-`V`** letter (keep lowercase `v` = Variant).

🔷 **Tier-1 wire = flatten.** `args("V", held)` stores the held `GLib.Value` as the list row. `StreamValue` already writes that row as type byte + payload. No outer wrap type byte. `args("V", float_value)` and `args("f", 1.25)` are the same on the wire; they differ only at FFI (pointer to `GValue` vs unboxed float).

🚫 Nested reserved type byte for “Value wrapping float” in this cut.  
🚫 Changing `StreamValue.write` / `read` for fundamentals.  
🚫 Editing gnome-shell-rpc from this repo.  
🚫 New Shared switch class / `ay` memcpy / more kind letters / replacing Gi pin.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/namespace.vala` — `to_value`: pack `"V"` as a copied `GLib.Value`

**Why:** `args` / `val` must accept the letter before Ffi can dispatch it.

**Where:** `to_value` switch — after `case "v":` … `return v_val;`, before `default:`.

**Depends on:** none.

#### Add — after the `"v"` case, before `default:`

```vala
			case "V":
				var held = l.arg<GLib.Value>();
				var copy = GLib.Value(held.type());
				held.copy(ref copy);
				return copy;
```

### 2. `libocrpc/namespace.vala` — `val()`: scan `"V"` like `"f"` / `"S"`

**Why:** `GLib.VariantType.string_scan("V")` fails (not a D-Bus complete type).

**Where:** `val()` tag scan, immediately after the `"S"` branch.

**Depends on:** §1.

#### Remove

```vala
		} else if (rest.has_prefix("S")) {
			tag = "S";
			rest = rest.substring(1);
		} else {
```

#### Replace with

```vala
		} else if (rest.has_prefix("S")) {
			tag = "S";
			rest = rest.substring(1);
		} else if (rest.has_prefix("V")) {
			tag = "V";
			rest = rest.substring(1);
		} else {
```

### 3. `libocrpc/namespace.vala` — `args()`: scan `"V"` like `"f"` / `"S"`

**Why:** same scan as `val()` for concatenated signatures (`"bV"`).

**Where:** `args()` while-loop tag scan, immediately after the `"S"` branch.

**Depends on:** §1.

#### Remove

```vala
			} else if (rest.has_prefix("S")) {
				tag = "S";
				offset += 1;
			} else {
```

#### Replace with

```vala
			} else if (rest.has_prefix("S")) {
				tag = "S";
				offset += 1;
			} else if (rest.has_prefix("V")) {
				tag = "V";
				offset += 1;
			} else {
```

### 4. `libocrpc/namespace.vala` — `args()` docblock: name `"V"`

**Why:** letter list is the public contract.

**Where:** `args()` doc comment, the sentence that currently ends at `''v'' {@link GLib.Variant}.`

**Depends on:** §1–§3.

#### Remove

```vala
	 * ''as'' ''string[]'', ''S'' same value plus Vala array length
	 * at FFI call, ''ay'' {@link GLib.Bytes},
	 * ''v'' {@link GLib.Variant}.
```

#### Replace with

```vala
	 * ''as'' ''string[]'', ''S'' same value plus Vala array length
	 * at FFI call, ''ay'' {@link GLib.Bytes},
	 * ''v'' {@link GLib.Variant},
	 * ''V'' {@link GLib.Value} (Helper / generator; not D-Bus).
```

### 5. `libocrpc/Ffi.vala` — `pack`: `"V"` → pin `GValue*`

**Why:** Vala `GLib.Value` Helper params are C `GValue*`. Same pin as Gi `value_keep` (`Gi.vala` GObject.Value IN).

**Where:** `pack` switch — after `case "v":` … `break;`, before `default:`.

**Depends on:** §1.

#### Add — after the `"v"` case, before `default:`

```vala
				case "V":
					var v_i = pin.length;
					pin.resize(v_i + 1);
					pin[v_i] = GLib.Value(val.type());
					val.copy(ref pin[v_i]);
					slot.set_pointer(&pin[v_i]);
					atype = Libffi.POINTER;
					break;
```

### 6. `libocrpc/Ffi.vala` — `dispatch`: count `"V"` as one wire / one slot

**Why:** skip `string_scan` (invalid for `V`).

**Where:** first `while (offset < signature.length)` in `dispatch()`, immediately after the `"S"` count branch.

**Depends on:** §5.

#### Remove

```vala
				if (rest.has_prefix("S")) {
					offset += 1;
					n_wire += 1;
					n_slots += 2;
					continue;
				}
				var rest_ptr = (char*) rest;
```

#### Replace with

```vala
				if (rest.has_prefix("S")) {
					offset += 1;
					n_wire += 1;
					n_slots += 2;
					continue;
				}
				if (rest.has_prefix("V")) {
					offset += 1;
					n_wire += 1;
					n_slots += 1;
					continue;
				}
				var rest_ptr = (char*) rest;
```

### 7. `libocrpc/Ffi.vala` — `dispatch`: pack loop tag `"V"`

**Why:** second scan must emit tag `"V"` into `pack`.

**Where:** second `while (offset < signature.length)` in `dispatch()`, the `tag = ""` / `"f"` / `string_scan` block (after the `"S"` continue).

**Depends on:** §5–§6.

#### Remove

```vala
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
```

#### Replace with

```vala
				var tag = "";
				if (rest.has_prefix("f")) {
					tag = "f";
					offset += 1;
				} else if (rest.has_prefix("V")) {
					tag = "V";
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
```

### 8. `docs/bin-rpc-protocol.md` — positional args: letter `"V"` is flatten

**Why:** document that Helper `"V"` is not a new type byte.

**Where:** section **Positional args (`Request.args`)**, after “No per-value direction flag…”.

**Depends on:** §1.

#### Add — new paragraph after “No protocol version bump.” in that subsection

```markdown
Helper / `OLLMrpc.args` letter **`V`** (capital) packs a held `GLib.Value` into that list. The wire row is the same flattened `StreamValue` encoding as any other `args` element (type byte + payload). There is no outer wrap type byte. Lowercase `v` remains the in-memory `GLib.Variant` args letter (Variant is not a type byte — §17).
```

### 9. `tests/rpc/values-test.vala` — `args("V")` / `val("V")` pack smoke

**Why:** prove the letter copies type + payload without a socket.

**Where:** `TestRpcValues.run_rpc_test`, immediately after the `"args float"` check.

**Depends on:** §1–§4.

#### Add — after `this.check(..., "args float");`

```vala
			var held_f = GLib.Value(typeof(float));
			held_f.set_float((float) 1.25);
			var packed_V = OLLMrpc.args("V", held_f);
			this.check(command_line, packed_V.size == 1, "args V size");
			this.check(command_line, packed_V.get(0).type() == typeof(float), "args V type");
			this.check(command_line, packed_V.get(0).get_float() == (float) 1.25, "args V float");
			var retval_V = OLLMrpc.val("V", held_f);
			this.check(command_line, retval_V.get_float() == (float) 1.25, "val V float");
```

### 10. `tests/rpc/ffi-v-test.vala` — Live Helper `"bV"`

**Why:** in-tree mirror of consumer `value-v-gate` (`set_relay_value` shape). Types here are NOT shipped in libocrpc (same as `ffi-as-test.vala`).

**Where:** new file.

**Depends on:** §1–§7.

#### Add — create `tests/rpc/ffi-v-test.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Ffi ''V'' GLib.Value pin — types NOT shipped in libocrpc.
 */

namespace RpcDummy
{
	public class ValueEcho : GLib.Object
	{
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Value", typeof(ValueEcho),
				"hello", "",
				"set_relay_value", "bV"
			);
		}

		public void hello(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response());
		}

		public void set_relay_value(OLLMrpc.Request request, bool is_to, GLib.Value value)
		{
			if (!is_to) {
				request.reply(new OLLMrpc.Response() {
					msg = "want is_to"
				});
				return;
			}
			if (value.type() != typeof(float)) {
				request.reply(new OLLMrpc.Response() {
					msg = "want float"
				});
				return;
			}
			if (value.get_float() != (float) 1.25) {
				request.reply(new OLLMrpc.Response() {
					msg = "want 1.25"
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}
	}
}

namespace OLLMrpcTests
{
	class TestRpcFfiV : RpcTestAppBase
	{
		public TestRpcFfiV()
		{
			base("com.roojs.ollmchat.test-rpc-ffi-v");
		}

		protected override string get_app_name()
		{
			return "test-rpc-ffi-v";
		}

		protected override void run_rpc_test(ApplicationCommandLine command_line) throws Error
		{
			RpcDummy.ValueEcho.rpc_register();
			OLLMrpc.Request.register("RPC-Value", new RpcDummy.ValueEcho());
			var dir = GLib.DirUtils.make_tmp("ocrpc-ffi-v-XXXXXX");
			var sock = GLib.Path.build_filename(dir, "rpc.sock");
			var listen = new OLLMrpc.Transport.SocketListen(sock);
			this.check(command_line, listen.start(), "listen start failed");
			var rpc = new OLLMrpc.Client("", "", sock);
			var connected = false;
			var loop = new GLib.MainLoop();
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Value.hello"
			}, null, (obj, res) => {
				connected = rpc.connect.end(res);
				loop.quit();
			});
			loop.run();
			this.check(command_line, connected, "client connect failed");
			var held = GLib.Value(typeof(float));
			held.set_float((float) 1.25);
			var req = new OLLMrpc.Request() {
				method = "RPC-Value.set_relay_value",
				args = OLLMrpc.args("bV", true, held)
			};
			OLLMrpc.Response? response = null;
			var call_loop = new GLib.MainLoop();
			rpc.call.begin(req, (obj, res) => {
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					this.check(command_line, false, e.message);
				}
				call_loop.quit();
			});
			call_loop.run();
			this.check(command_line, response.error == null, "set_relay_value returned error");
			this.check(command_line, response.msg == "ok",
				"set_relay_value want ok got %s".printf(response.msg));
			listen.stop();
			GLib.FileUtils.unlink(sock);
			GLib.DirUtils.remove(dir);
		}
	}
}

int main(string[] args)
{
	var app = new OLLMrpcTests.TestRpcFfiV();
	return app.run(args);
}
```

### 11. `tests/meson.build` — build `test-rpc-ffi-v`

**Why:** same executable pattern as `test-rpc-ffi-as`.

**Where:** immediately after the `test('test-rpc-ffi-as', …)` block.

**Depends on:** §10.

#### Add — after `test('test-rpc-ffi-as', … timeout: 10,)`

```meson
test_rpc_ffi_v = executable('test-rpc-ffi-v',
  'rpc/ffi-v-test.vala',
  dependencies: rpc_test_deps + [
    rpc_test_app_dep,
    dependency('gio-unix-2.0'),
  ],
  link_with: rpc_test_link_with,
  build_rpath: rpc_test_build_rpath,
  export_dynamic: true,
  vala_args: rpc_test_vala_args,
)
test('test-rpc-ffi-v',
  test_rpc_ffi_v,
  suite: 'rpc',
  timeout: 10,
)
```

### Consumer (after PASS — not this apply)

🚫 Do **not** edit gnome-shell-rpc from OLLMchat. After `value-v-gate` PASS:

- Replace `Helper-Transition` `bsid` + `to_wire` / `from_wire` with `"bV"` + `GLib.Value`.
- Generator: `GObject.Value` IN → pack `V`, never `ay` memcpy.

---

## Gate (FAIL → PASS)

```bash
meson compile -C build value-v-gate
timeout 5 ./build/tests/call-sync-repro/value-v-gate
```

**FAIL today:** no capital-`V` args/Ffi support (gate exits 1 with this bug path).

**PASS when:** `OLLMrpc.args("bV", true, held)` round-trips through a Live Helper `set_relay_value` with signature `"bV"`, peer sees `is_to` + `value.type()` + payload; no kind string.

In-tree: `meson compile -C build test-rpc-ffi-v test-rpc-values` then those tests.

---

## Attempts / changelog

- ✔️ 2026-09-16 — gnome-shell-rpc: dropped `bsid` / `to_wire` / `from_wire`;
  Transition/Interval set_* use `args("V")` → stock Gi; deleted
  Helper-Transition relay; Helper-Interval keeps create only.
  `value-v-gate` **PASS**.

- ⏳ 2026-09-16 — Confirmed `"V"` unused; flatten + Remove/Replace/Add fences in this log.
- ✔️ 2026-09-16 — Applied fences: `namespace.vala` / `Ffi.vala` / protocol note / `values-test` V smoke / `ffi-v-test` + meson. `meson test test-rpc-ffi-v` OK. V pack checks in `values-test` pass before a pre-existing `args strv length` stderr (TestAppBase still exits 0).

---

## Next

🔷 `⏳` Consumer `value-v-gate` PASS + drop `bsid` (not this repo).  
⏳ User verify on device / promote ✅.
