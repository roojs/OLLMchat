# RPC registration and dispatch

How a `Request.method` string reaches a Vala instance method. The byte layout of objects is [`bin-rpc-protocol.md`](bin-rpc-protocol.md). That file’s `rpc_register()` / `Bin.register` path is **type aliases only**. This file is the **handler** path.

---

## Two tables

A class `rpc_register()` often fills both:

1. **Wire types** — `OLLMrpc.Bin.register("Folder", typeof(Folder))`  
   Alias string on the socket → local GType.
2. **Methods** — `Request.add_class(...)`  
   Suffix + signature letters for FFI. Does not pick the instance.

The instance is a third call, at server boot:

```vala
Folder.rpc_register();
Request.register("RPC-Folder", this.folder);
```

`Application` already calls `Request.register(name, instance)`. It does not list methods.

---

## `add_class`

Pairs of method suffix + letters, then `null`. Letters match `OLLMrpc.args`, except `S`.

```vala
Request.add_class(
    "RPC-Folder", typeof(Folder),
    "fetch", "s",
    "fetch_files", "siisSb",
    null
);
```

Wire method is `RPC-Folder.fetch_files`. The C symbol is GType + `_` + suffix (`changed.check` → `changed_check`). `Ffi` looks that symbol up in the process (`g_module_open(NULL)`), so handlers in the main executable must be exported (ollmfilesd does; in-tree RPC tests that list dummy methods set Meson `export_dynamic`).

| Letter | One `Request.args` value | C args after `(self, Request)` |
| --- | --- | --- |
| `""` | none (method may still read `request.args`) | none |
| `s` | string | `gchar*` |
| `i` | int | `gint` |
| `as` | `string[]` | `gchar**` only |
| `S` | `string[]` | `gchar**` + `gint` length |

`S` is not a packet type. `StreamValue` still writes a counted `string[]`. `S` only tells FFI to pass the extra length valac puts on a `string[]` parameter.

---

## Live prefixes

`Request.register` + non-zero `lease_id` means that lease is `this` (GI-style method-on-object).

Live ref / subscribe keep the **handler** as `this`. `lease_id` is the target object. Boot those with `register_live`:

```vala
Live.Remote.rpc_register();
Request.register_live("RPC-Live-Remote", new Live.Remote());
Live.Callback.rpc_register();
Request.register_live("RPC-Live-Callback", new Live.Callback());
```

---

## Dispatch order

`Request.dispatch`:

1. `Ffi` if the prefix.suffix is in `add_class`
2. else `Gi` typelib
