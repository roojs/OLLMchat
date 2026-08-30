# RPC-1.2 — GIR C return on `retval`, not `args`

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Status:** **✔️** **implemented** (agent done — not user-confirmed)

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`RPC-8.5.4-DONE-rpc-retval-migrate.md`](done/RPC-8.5.4-DONE-rpc-retval-migrate.md) — GObject / object-list returns already use `retval`. This cut moves the leftover **C return** (scalars, boxed, utf8 lists) off `args`.

**ℹ️** Consumer: gnome-shell-rpc `src/gi-stub-gen/Generator.vala` still unpacks a non-object return from `response.args.get(0)` and shifts OUT to `args[1]`. After this lands, that generator reads `retval` and OUT from `args[0]`.

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

---

## Purpose

- **🔷** `✔️` `Response.args` is OUT / INOUT only (GIR order).
- **🔷** `✔️` The GIR C return goes on `Response.retval` — same slot GObject already uses.
- **🔷** `✔️` Both ends in the same cut. No dual-write (return in `args` and `retval`).
- **🔷** `✔️` Keep using `Gi.scalar` for packing. No second letter switch.
- **ℹ️** `retval` already holds one GObject, a `Gee.ArrayList` of GObjects, or unset (`INVALID`).
- **ℹ️** Today Gi prepends the C return onto `args`, then appends OUT. That was before `retval` existed for non-objects.

---

## Shape

- **🔷** Void return → `retval` stays unset. `args` is OUT only.
- **🔷** Non-void return → assign `retval` (scalar / boxed / `string[]` / GObject / object list). Then OUT onto `args` starting at index 0.
- **🔷** Empty utf8 `string[]` is a real return on `retval` (boxed empty array). Not `INVALID`.
- **🔷** Null GObject list stays unset `retval` (already `val("o", list)`).
- **ℹ️** Clients that treated `args[0]` as the C return must read `retval`. First OUT moves from `args[1]` to `args[0]` when a return was present.

---

## Today

- **ℹ️** `Gi.dispatch_function`: GObject → `retval = val("o", created)`. Everything else `scalar(..., response.args)`. Then OUT `scalar(..., response.args)` after that.
- **ℹ️** utf8 / FILENAME GLIST / GSLIST → `response.args.add(as_val)` in `scalar_list`.
- **ℹ️** `tests/rpc/gi-test.vala` `Gio-Menu.get_n_items` reads `args.get(0).get_int()`.
- **ℹ️** `tests/rpc/values-test.vala` `RPC-Probe.blob` echoes `Request.args` onto `Response.args`. That is the args codec, not a GIR return.

---

## Phase 1 — Gi writer ✔️

- **🔷** `✔️` Non-object C return → `retval`. OUT loop unchanged (`scalar` into `response.args`).
- **🔷** `✔️` utf8 list return → `retval`. Object lists already use `retval`.

### 1. `libocrpc/Gi.vala` — `dispatch_function` C return onto `retval`

**Why:** `args` was the only place for a scalar return. `retval` is that place now.

**Where:** `dispatch_function`, the `switch (ret_type.get_tag())` after `var response = new Response()`. OUT loop after the switch stays.

**Depends on:** none.

**ℹ️** Reuse `scalar` into a one-element list, then `response.retval = packed.get(0)`. Do not add a second packer.

#### Remove — `INTERFACE` non-object arm (enum / flags / boxed)

```vala
					if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
						if (!this.scalar(ret_type, ret, response.args)) {
							return true;
						}
						break;
					}
```

#### Replace with

Pack into `retval`, not `args`.

```vala
					if (kind != GI.InfoType.OBJECT && kind != GI.InfoType.INTERFACE) {
						var packed = new Gee.ArrayList<GLib.Value?>();
						if (!this.scalar(ret_type, ret, packed)) {
							return true;
						}
						response.retval = packed.get(0);
						break;
					}
```

#### Remove — `default` arm

```vala
				default:
					if (!this.scalar(ret_type, ret, response.args)) {
						return true;
					}
					break;
```

#### Replace with

```vala
				default:
					var packed = new Gee.ArrayList<GLib.Value?>();
					if (!this.scalar(ret_type, ret, packed)) {
						return true;
					}
					response.retval = packed.get(0);
					break;
```

#### Remove — `dispatch_function` docblock (return / OUT sentence)

```vala
		 * Slot 0 is the instance. Remaining IN args use {@link convert}.
		 * Return and OUT args use {@link scalar} into {@link Response.args}.
		 * A returned GObject goes in {@link Response.retval} like ''new''.
```

#### Replace with

```vala
		 * Slot 0 is the instance. Remaining IN args use {@link convert}.
		 * The C return uses {@link scalar} into {@link Response.retval}.
		 * OUT / INOUT use {@link scalar} into {@link Response.args}.
```

#### Remove — `scalar` lead sentence

```vala
		 * Append one GI scalar to an args list.
```

#### Replace with

```vala
		 * Append one GI scalar to dest.
```

#### Remove — `scalar` dest `@param`

```vala
		 * @param dest {@link Response.args}
```

#### Replace with

```vala
		 * @param dest OUT list, or a one-element list copied onto retval
```

#### Remove — `scalar_array` dest `@param`

```vala
		 * @param dest {@link Response.args}
```

#### Replace with

```vala
		 * @param dest OUT list, or a one-element list copied onto retval
```

### 2. `libocrpc/Gi.vala` — `scalar_list` utf8 on `retval`

**Why:** A utf8 GList is the C return, not an OUT arg.

**Where:** `scalar_list`, UTF8 / FILENAME arm after building `as_val`.

**Depends on:** none.

#### Remove

```vala
					var as_val = GLib.Value(typeof(string[]));
					as_val.set_boxed(strv);
					response.args.add(as_val);
					return true;
```

#### Replace with

```vala
					var as_val = GLib.Value(typeof(string[]));
					as_val.set_boxed(strv);
					response.retval = as_val;
					return true;
```

#### Remove — `scalar_list` docblock UTF8 sentence

```vala
		 * UTF8 / FILENAME → native ''string[]'' on {@link Response.args}.
		 * Registered GObject {@link GI.TypeTag.INTERFACE} → leased rows
		 * on {@link Response.retval}. Null list → empty string array or
		 * empty retval.
```

#### Replace with

```vala
		 * UTF8 / FILENAME → native ''string[]'' on {@link Response.retval}.
		 * Registered GObject {@link GI.TypeTag.INTERFACE} → leased rows
		 * on {@link Response.retval}. Null utf8 list → empty string array.
		 * Null object list → empty retval.
```

---

## Phase 2 — Gi reader ✔️

- **🔷** `✔️` `get_n_items` reads `retval`, not `args[0]`.

### 3. `tests/rpc/gi-test.vala` — `Gio-Menu.get_n_items`

**Why:** Writer in ### 1 must not ship while this test still reads `args`.

**Where:** after `get_n_items returned error`.

**Depends on:** ### 1.

#### Remove

```vala
			this.check(command_line, response.args.size == 1, "get_n_items returned no value");
			this.check(command_line, response.args.get(0).get_int() == 0, "empty menu is not 0");
```

#### Replace with

```vala
			this.check(command_line, response.retval.type() != GLib.Type.INVALID, "get_n_items returned no value");
			this.check(command_line, response.retval.get_int() == 0, "empty menu is not 0");
```

---

## Phase 3 — docs ✔️

- **🔷** `✔️` Envelope and protocol say C return is `retval`; `args` is OUT only.

### 4. `libocrpc/Response.vala` — class / `args` / `msg` docs

**Why:** Docs still tell people to put typelib scalars on `args`.

**Where:** class overview; `args` property; `msg` property.

**Depends on:** ### 1.

#### Remove — class overview (retval + args sentence)

```vala
	 * calls put a typed return in {@link retval} (omit on the wire
	 * when unset or an empty {@link Gee.ArrayList}) and optional
	 * scalars in {@link args} (same
	 * {@link Gee.ArrayList} of boxed {@link GLib.Value} as
	 * {@link Request.args}). File.read-style string payloads may use
```

#### Replace with

```vala
	 * calls put the C return in {@link retval} (omit on the wire
	 * when unset or an empty {@link Gee.ArrayList}). OUT / INOUT
	 * scalars go in {@link args} (same
	 * {@link Gee.ArrayList} of boxed {@link GLib.Value} as
	 * {@link Request.args}). File.read-style string payloads may use
```

#### Remove — `args` property (GObject sentence)

```vala
		 * Empty list is omitted on the bin socket. A returned GObject
		 * uses {@link retval}, not this list. Do not put scalars in
		 * {@link msg}.
```

#### Replace with

```vala
		 * Empty list is omitted on the bin socket. The C return uses
		 * {@link retval}, not this list. This list is OUT / INOUT only.
		 * Do not put scalars in {@link msg}.
```

#### Remove — `msg` property (typelib sentence)

```vala
		 * Typelib scalar returns use {@link args}, not this property.
```

#### Replace with

```vala
		 * Typelib scalar returns use {@link retval}, not this property.
```

### 5. `docs/bin-rpc-protocol.md` — §15 `retval` and `args`

**Why:** Spec still describes `retval` as GObject-only and leaves scalars on `args`.

**Where:** `### Root retval (`Response.retval`)` then `### Positional returns (`Response.args`)`.

**Depends on:** ### 1.

#### Remove — Root retval (GObject-only body)

```markdown
**One GObject** (method returns a single row): bare `OBJECT`. **N GObjects** (method returns a list): `typeof(Gee.ArrayList)` → object array `0xD0`, including when `size == 1`. Live-handle bodies follow `StreamValue` / `parse_object`.
```

#### Replace with

```markdown
The GIR C return lives here (scalar, boxed, utf8 `string[]`, one GObject, or object list). A number or string uses the same `StreamValue` encoding as `args` elements. Empty utf8 `string[]` is a boxed array, not omit. **One GObject**: bare `OBJECT`. **N GObjects**: `typeof(Gee.ArrayList)` → object array `0xD0`, including when `size == 1`. Live-handle bodies follow `StreamValue` / `parse_object`.
```

#### Remove — Positional returns

```markdown
**Omit** when **`args.size == 0`**. A returned GObject uses **`retval`**, not this list.
```

#### Replace with

```markdown
**Omit** when **`args.size == 0`**. The C return uses **`retval`**, not this list. This list is OUT / INOUT only.
```

---

## LLM notes

- **🚫** Dual-write the C return on `args` and `retval`.
- **🚫** New `scalar` helper / `scalar_value` — reuse `scalar` into a one-element list.
- **🚫** Protocol version bump. Same as 8.5.4: packing contract, both ends.
- **🚫** `msg` / `msg_encode` (File.read).
- **🚫** `tests/rpc/values-test.vala` `RPC-Probe.blob` — that echoes `Request.args`, not a GIR return.
- **🚫** FFI handlers that pack a lease id on `args` on purpose (gnome-shell-rpc Helper uint64).
- **🚫** `[Deprecated]` soak on `args[0]`-as-return.
- **💩** Extra gi-test that a method with OUT starts at `args[0]` after a non-void return.
- **ℹ️** gnome-shell-rpc follow-on: `Generator.emit_value_get` for the C return → `retval`; OUT `value_idx` starts at 0. Hand overrides that read `response.args.get(0)` as the GIR return follow the same cut.
