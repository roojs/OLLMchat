# `Gi.convert_array` Variant gate vs native `as` / `string[]`

**Status:** ⏳ applied — `string[]` type check before the Variant gate

**Parent:** [`8.4.6-rpc-ffi-leftovers.md`](../plans/8.4.6-rpc-ffi-leftovers.md) §8.

**Reporter:** [`gnome-shell-rpc 0.5.2`](file:///home/alan/git/gnome-shell-rpc/docs/plans/0.5.2-close-gi-stub-gaps.md) Phase 5.

---

## Problem

🔷 GIR `UTF8[]` / `FILENAME[]` IN arrives as native `string[]` (`STRING|0x80`). The opening `typeof(GLib.Variant)` gate would `INVALID_PARAMS` that row.

## Evidence

ℹ️ `OLLMrpc.args("as")` and `StreamValue` write / read native `string[]`. Variant is numeric slabs only.

ℹ️ Opening gate (from `9f361ca4`) sat in front of every element tag, including UTF8 / FILENAME.

## Root cause

✔️ Variant gate is for numeric slabs. Native `string[]` must be recognized **before** that check, not by deleting the check.

## Fix

🔷 Check `val.type() == typeof(string[])` first. UTF8 / FILENAME aliases that row. Other tags fall through. Variant gate unchanged.

#### Add — before `if (val.type() != typeof(GLib.Variant))`

```vala
			var elem = arg.get_type().get_param_type(0);
			if (val.type() == typeof(string[])) {
				switch (elem.get_tag()) {
					case GI.TypeTag.UTF8:
					case GI.TypeTag.FILENAME:
						this.in_args[vi + offset].v_pointer = (void*) (string[]) val;
						return true;
					default:
						break;
				}
			}
```

🚫 gnome-shell-rpc: drop the Variant gate and special-case only UTF8 / FILENAME inside the switch.

## Next

🔷 ⏳ 8.4.6 §8 still owns native numeric arrays. gnome-shell-rpc Phase 5 still owns generator `ARRAY` → `string[]` emit.
