# RPC error code / wire Error compile failure

**Status:** FIXED (2026-06-06) — `meson compile -C build ocrpc` succeeds

**Started:** 2026-06-06

**Process:** `docs/bug-fix-process.md` · **Plan format:** `docs/guide-to-writing-plans.md`

**Related:** `docs/plans/2.10.4.1-ollmfilesd-rpc-api.md` · `docs/plans/2.10.4.3-DONE-daemon-and-rpcclient.md`

---

## Purpose

- 🔷 Fix `libocrpc` compile: `RpcClient` `new Error(RpcErrorCode.INTERNAL_ERROR, …)` fails on Vala 0.56.18
- 🔷 Keep three types separate:
  - `GLib.Error` / `GLib.IOError` — transport only
  - `RpcErrorCode` — server throw/catch errordomain
  - `OLLMrpc.Error` — JSON-RPC wire object (`GObject` for `Json.Serializable` only)
- 🔷 Wire `Error` and `to_error` / `to_response` take `int` (JSON-RPC code)
- 🔷 Document in Vala `/** */` blocks that `int code` is an {@link RpcErrorCode} value (e.g. `RpcErrorCode.INTERNAL_ERROR`), not an arbitrary integer
- 🔷 Inside `to_error`, cast back inline: `((RpcErrorCode) code).message`
- 🔷 Server catch passes `(int) e` to `to_response`
- 🔷 `RpcClient` call sites unchanged — they already pass explicit message strings
- ✅ `throw (RpcErrorCode) RpcErrorCode.*` — documented on errordomain; no throw call sites in tree yet
- 🚫 No expanded `to_error(message, method, …)` API
- 🚫 No routing `RpcClient` through `to_error`
- 🚫 No git-wide revert of other `libocrpc` / `ollmfilesd` work

---

## Problem

```bash
meson compile -C build ocrpc
```

```
../libocrpc/RpcClient.vala:198.6-198.32: error: Argument 1: Cannot convert from `int' to `unowned OLLMrpc.RpcErrorCode'
../libocrpc/RpcClient.vala:225.6-225.32: error: Argument 1: Cannot convert from `int' to `unowned OLLMrpc.RpcErrorCode'
../libocrpc/RpcClient.vala:283.7-283.33: error: Argument 1: Cannot convert from `int' to `unowned OLLMrpc.RpcErrorCode'
```

Vala 0.56 types errordomain constants as `int` at call sites. Wire `Error` ctor and `to_error` currently take `RpcErrorCode`.

---

## Concrete code proposals

Hunks are **Remove** / **Replace with** from the tree. Verify context before applying.

- 1 — `libocrpc/Error.vala` — class doc + `Error` ctor
- 2 — `libocrpc/RpcErrorCode.vala` — errordomain doc + `to_error` / `to_response`
- 3 — `libocrpc/Connection.vala` — `reply_error`

No edits to `libocrpc/RpcClient.vala` — existing `new Error(RpcErrorCode.INTERNAL_ERROR, …)` compiles once ctor takes `int`.

---

### 1. `libocrpc/Error.vala` — class doc + `Error` ctor

**Why:** wire `code` is `int` on JSON-RPC; ctor param documents it is an {@link RpcErrorCode} number.

**Where:** `Error` class summary and `public Error(...)` constructor.

#### Remove

```vala
	/** JSON-RPC 2.0 error object on the wire (`code`, `message`). */
	public class Error : GLib.Object, Json.Serializable
	{
		public int code { get; set; }
		public string message { get; set; default = ""; }

		/**
		 * @param method optional RPC method (reserved; logging is on {@link RpcClient})
		 * @param request_id optional request id (reserved)
		 */
		public static void rpc_register()
		{
			register("Error", typeof(Error));
		}

		public Error(
			RpcErrorCode code,
			string message,
			string method = "",
			int request_id = 0
		) {
			Object(code: (int) code, message: message);
		}
```

#### Replace with

```vala
	/**
	 * JSON-RPC 2.0 error object on the wire (`code`, `message`).
	 *
	 * Not {@link GLib.Error} — {@link GLib.Object} only for {@link Json.Serializable}.
	 * {@link code} is the numeric JSON-RPC error code (a {@link RpcErrorCode} value).
	 */
	public class Error : GLib.Object, Json.Serializable
	{
		public int code { get; set; }
		public string message { get; set; default = ""; }

		/**
		 * @param method optional RPC method (reserved; logging is on {@link RpcClient})
		 * @param request_id optional request id (reserved)
		 */
		public static void rpc_register()
		{
			register("Error", typeof(Error));
		}

		/**
		 * @param code JSON-RPC error number — pass {@link RpcErrorCode} constants
		 *   (e.g. {@link RpcErrorCode.INTERNAL_ERROR})
		 * @param message wire error message
		 * @param method optional RPC method (reserved; logging is on {@link RpcClient})
		 * @param request_id optional request id (reserved)
		 */
		public Error(
			int code,
			string message,
			string method = "",
			int request_id = 0
		) {
			Object(code: code, message: message);
		}
```

---

### 2. `libocrpc/RpcErrorCode.vala` — errordomain doc + `to_error` / `to_response`

**Why:** accept `int` at call sites; inline cast back for domain default message; document `code` param.

**Where:** `errordomain RpcErrorCode` summary and static methods.

#### Remove

```vala
	/**
	 * JSON-RPC 2.0 standard and application error codes (throw/catch).
	 *
	 * Static methods only — instance methods on the caught error are not
	 * supported in Vala 0.56 yet.
	 */
	public errordomain RpcErrorCode
	{
		PARSE_ERROR = -32700,
		INVALID_REQUEST = -32600,
		METHOD_NOT_FOUND = -32601,
		INVALID_PARAMS = -32602,
		INTERNAL_ERROR = -32603,
		NOT_IMPLEMENTED = -32000;

		public static Error to_error(RpcErrorCode e)
		{
			return new Error(e, e.message);
		}

		public static Response to_response(RpcErrorCode e)
		{
			return new Response() {
				error = to_error(e)
			};
		}
	}
```

#### Replace with

```vala
	/**
	 * JSON-RPC 2.0 standard and application error codes (throw/catch).
	 *
	 * Server control flow only — not the wire {@link Error} object.
	 * Constants (e.g. {@link INTERNAL_ERROR}) are {@link RpcErrorCode} values;
	 * pass them to {@link to_error} / {@link to_response} / wire {@link Error}
	 * as `int` (Vala 0.56 types errordomain members as `int` at call sites).
	 *
	 * Static methods only — instance methods on the caught error are not
	 * supported in Vala 0.56 yet.
	 */
	public errordomain RpcErrorCode
	{
		PARSE_ERROR = -32700,
		INVALID_REQUEST = -32600,
		METHOD_NOT_FOUND = -32601,
		INVALID_PARAMS = -32602,
		INTERNAL_ERROR = -32603,
		NOT_IMPLEMENTED = -32000;

		/**
		 * Build wire {@link Error} from an RPC error number.
		 * @param code JSON-RPC error number — {@link RpcErrorCode} constant
		 *   (e.g. {@link INVALID_PARAMS})
		 */
		public static Error to_error(int code)
		{
			return new Error(code, ((RpcErrorCode) code).message);
		}

		/**
		 * @param code JSON-RPC error number — {@link RpcErrorCode} constant
		 */
		public static Response to_response(int code)
		{
			return new Response() {
				error = to_error(code)
			};
		}
	}
```

---

### 3. `libocrpc/Connection.vala` — `reply_error`

**Why:** match `to_response(int)`; document `error_code` param.

**Where:** `reply_error` on `Connection`.

#### Remove

```vala
		public void reply_error(Request request, RpcErrorCode error_code)
		{
			this.reply(request, RpcErrorCode.to_response(error_code));
		}
```

#### Replace with

```vala
		/**
		 * Reply with a JSON-RPC error response.
		 * @param error_code RPC error number — {@link RpcErrorCode} constant
		 *   (e.g. {@link RpcErrorCode.INVALID_PARAMS})
		 */
		public void reply_error(Request request, int error_code)
		{
			this.reply(request, RpcErrorCode.to_response(error_code));
		}
```

---

## Call-site patterns (no file edits in this proposal unless already present)

**Server catch**

```vala
} catch (RpcErrorCode e) {
    request.reply(RpcErrorCode.to_response((int) e));
}
```

**Server constant**

```vala
request.session.reply_error(request, RpcErrorCode.INVALID_PARAMS);
```

**Client transport (`libocrpc/RpcClient.vala` — unchanged)**

```vala
var error = new Error(
    RpcErrorCode.INTERNAL_ERROR,
    "not connected",
    request.method,
    request.id
);
return new Response() { id = request.id, error = error };
```

```vala
} catch (GLib.Error e) {
    var error = new Error(
        RpcErrorCode.INTERNAL_ERROR,
        "write: " + e.message,
        request.method,
        request.id
    );
    return new Response() { id = request.id, error = error };
}
```

`GLib.Error` supplies message text only. `OLLMrpc.Error` goes on the wire.

---

## Throw pattern (documented in `RpcErrorCode.vala`)

```vala
throw (RpcErrorCode) RpcErrorCode.INVALID_PARAMS;
```

Bare `throw RpcErrorCode.INVALID_PARAMS` fails on Vala 0.56 (`'int' is not an error type`).
