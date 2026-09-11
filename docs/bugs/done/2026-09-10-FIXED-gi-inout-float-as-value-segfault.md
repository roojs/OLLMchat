# Gi: INOUT float passed as value → segfault (`st_theme_node_adjust_for_height`)

**Status:** ✔️ applied — await consumer verify  
**Hit:** 2026-09-10  
**Component:** `libocrpc/Gi.vala` `dispatch_function` (`GI.Direction.INOUT` scalars)  
**Consumer:** gnome-shell-rpc — `St-ThemeNode.adjust_for_height`  

---

## Problem

INOUT scalars were written into `in_args` as values (`v_float`, etc.). libffi expects a **pointer** to storage. Server SIGSEGV (`0xbf800000` = `-1.0f` bits used as address).

---

## Fix (`libocrpc/Gi.vala`)

On INOUT scalar: allocate a kept cell, copy converted IN bits into it, set `in_args[slot].v_pointer` and `out_args[out_i].v_pointer` to the same cell. After invoke, flatten INOUT scalars like OUT into `Response.args`.

```vala
// setup (excerpt ~444–477)
if (arg.get_direction() == GI.Direction.INOUT) {
    …
    var cell = new uint8[sizeof(GI.Argument)];
    …
    GLib.Memory.copy(ptr, &this.in_args[slot], sizeof(GI.Argument));
    this.in_args[slot].v_pointer = ptr;
    this.out_args[out_i].v_pointer = ptr;
}

// post-invoke flatten (excerpt ~604–617)
} else if (arg.get_direction() == GI.Direction.INOUT) {
    switch (arg.get_type().get_tag()) {
        case GI.TypeTag.FLOAT:
        case GI.TypeTag.DOUBLE:
        …
            flatten = true;
```

---

## Prove

Nested gnome-shell-rpc: `St-ThemeNode.adjust_for_height` completes without SIGSEGV.
