# RPC stdio / script dispatch regression

**Status:** OPEN

## Problem

T0 RPC tests fail after removing **`Request.dispatch_line()`** and calling **`dispatch()`** without **`params_node`**.

## Root cause

**`Request.deserialize_property("params")`** intentionally stores a placeholder **`CallParam`**. Typed deserialize belongs in **`dispatch(params_node)`** when the call site passes **`obj.get_member("params")`**.

Calling **`dispatch()`** with no node leaves **`param`** empty → **`Daemon.rpc_hello`** cast crashes.

## Rejected fixes (do not re-propose)

- Changing **`deserialize_property("params")`** (rejected twice)
- **`wire_params_node`**
- **`gobject_from_data`** + **`dispatch()`** without params node
- **`Request.dispatch_line()`** static
- **`Connection`** API / read-loop changes

## Accepted fix

Inline at call site (**`StdioConnection.run_script`** for T0). **`gobject_from_data(Request, line)`** in try/catch first; **`Parser`** only to reach **`params`**; no root/null checks after successful deserialize:

```vala
OLLMrpc.Request? request = null;
try {
	request = Json.gobject_from_data(
		typeof(OLLMrpc.Request),
		line,
		-1
	) as OLLMrpc.Request;
} catch (GLib.Error e) {
	GLib.warning("parse error: %s", e.message);
	continue;
}

var parser = new Json.Parser();
parser.load_from_data(line, -1);

request.connection = this;
request.dispatch(
	parser.get_root().get_object().get_member("params")
);
```

**`Request.vala`**: no changes.

Plan: [`docs/plans/2.10.4.11-rpc-stdio-harness-fix.md`](../plans/2.10.4.11-rpc-stdio-harness-fix.md).
