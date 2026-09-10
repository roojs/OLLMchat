# Gi: INOUT float passed as value → segfault (`st_theme_node_adjust_for_height`)

**Status:** ⏳ OPEN  
**Hit:** 2026-09-10  
**Package / area:** `libocrpc` — `Gi.vala` `dispatch_function` / `convert` (`GI.Direction.INOUT` scalars)  
**Consumer:** gnome-shell-rpc nested Wayland — `St-ThemeNode.adjust_for_height` after layout preferred hooks run  
**Consumer note:** layout mint now reaches JS preferred; this RPC is the first crash, not a stub bug

---

## Problem

🔷 **Expected:** Typelib invoke of `st_theme_node_adjust_for_height(node, inout float for_height)` with wire float `-1.0` (Clutter unspecified) updates the float and returns.

**Actual:** `mutter-rpc` SIGSEGV in `libst-16.so` `st_theme_node_adjust_for_height+0x48`. Fault address `0xbf800000` = IEEE bits of `-1.0f` used as a pointer. Client sees `socket closed` / pending RPC.

Affects **every** Gi INOUT scalar on the typelib path (float first hit; same pattern for double / ints), not only ThemeNode.

---

## Symptom (prove)

Client (`~/.cache/gnome-shell-rpc/org.gnome.ShellRpc.debug.log`):

```text
method=St-ThemeNode.adjust_for_height
… ~110ms …
Client.vala: socket closed … pending=1
```

Disassembly (`libst-16.so`): `%rsi` → `%r12`, then `movss (%r12), %xmm0`. St expects `float *`.

Consumer stub sends `"f"` and reads OUT float (`ref float`) — wire shape is correct.

---

## Root cause

`dispatch_function` setup:

1. **INOUT** increments `n_in` and `n_out`, counts a wire value.
2. Setup treats non-**OUT** as IN: `convert()` for `TypeTag.FLOAT` does:

   ```vala
   this.in_args[vi + offset].v_float = val.get_float();
   ```

3. Pure **OUT** gets a kept `uint8[sizeof(GI.Argument)]` cell and
   `out_args[i].v_pointer = cell`. **INOUT never gets that cell** and never
   sets `in_args` to a pointer.

GI/libffi need a **pointer** to storage for INOUT scalars (IN value in, OUT value out). Same cell should back `in_args` and `out_args`.

Post-invoke flatten currently only runs for pure OUT; INOUT readback into `Response.args` would also be wrong if the crash were avoided.

---

## Fix (libocrpc only — do not paper in consumers)

🔷 In `Gi.vala` `dispatch_function`:

1. On **INOUT** scalar: allocate a kept cell (like OUT), write the converted IN value into it, set `in_args[slot].v_pointer = cell` and `out_args[out_i].v_pointer = cell`.
2. After invoke, flatten INOUT scalar cells the same way as OUT before `scalar()` → `Response.args`.

Same for other scalar INOUT tags (double, int*, …), not only float.

---

## Prove

1. Rebuild consumer against fixed libocrpc.
2. Nested gnome-shell-rpc: `St-ThemeNode.adjust_for_height` gets `replied`; no SIGSEGV.
3. Optional unit: Gi invoke of any GIR INOUT float with known in/out values.
