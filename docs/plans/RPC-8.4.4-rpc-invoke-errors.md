# 8.4.4 — Invoke errors to the client

> `docs/plans/RPC-1.0-summary.md` is **not** updated for this sub-plan until it is done and archived.

**Status:** **PROPOSED**

**Parent:** [`RPC-8.4-rpc-positional-values-and-ffi.md`](done/RPC-8.4-rpc-positional-values-and-ffi.md)

**Depends on:** [`8.4.3`](done/RPC-8.4.3-DONE-rpc-ffi-typelib-method.md) — `dispatch_function` / `dispatch_new` `fn.invoke` catch.

**Sibling leftover:** [`8.4.5`](done/RPC-8.4.5-DONE-rpc-ffi-leftovers.md) — boxed / GObject `INTERFACE` / invoke return. [`8.4.6-DONE`](done/RPC-8.4.6-DONE-rpc-ffi-leftovers.md) — scalar / array / list OUT. [`8.4.9`](done/RPC-8.4.9-rpc-ffi-glist-in.md) — list IN. Not this plan. Consumers: [`RPC-8.4.4.1-URGENT-rpc-consumer-audit.md`](RPC-8.4.4.1-URGENT-rpc-consumer-audit.md).

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

Edits are **Remove** / **Replace with** / **Add** from the tree.
Verify surrounding context before applying.

---

## Purpose

- **🔷** `⏳` When the real function throws, `Client.call` throws that same error.
  - Same type (`catch (GLib.FileError e)` still matches).
  - Same GError code (`FileError.NOENT`, not JSON-RPC `-32603`).
  - Same message.
- **🔷** `⏳` `Error.code` stays the JSON-RPC envelope (`INTERNAL_ERROR` when invoke failed).
  - GError code is a **separate** property (`gerror_code`). Mixing them is why catch fails today.
- **🔷** `⏳` Grow `reply_error` so the invoke `catch` can pass the thrown `GLib.Error`.
- **ℹ️** Consumers: **URGENT** [`RPC-8.4.4.1-URGENT-rpc-consumer-audit.md`](RPC-8.4.4.1-URGENT-rpc-consumer-audit.md). Full-tree compile waits on that plan’s **Phase 1** (throw). Caller catch/UI is **Phase 2**.

**Suggested order:** this plan (`libocrpc` + `tests/rpc`) → [`8.4.4.1`](RPC-8.4.4.1-URGENT-rpc-consumer-audit.md) Phase 1 → Phase 2.

---

## Wire, server, `Client.call`

### Error properties

A `GLib.Error` is three things. The wire `Error` already has `message`. It needs the other two, and must not reuse `code`.

- **🔷** `domain` — which *kind* of error it is.
  - GLib name for FileError vs IOError vs RpcErrorCode (string like `g-file-error-quark`).
  - That is what `catch (GLib.FileError e)` matches on.
  - Always set. Protocol errors use the `RpcErrorCode` quark (so `catch (RpcErrorCode e)` matches). Function throws use the C function's domain.
- **🔷** `gerror_code` — which *specific* error inside that kind (`NOENT`, `INVALID_PARAMS`, …).
  - Function throw: `e.code` from the thrown `GLib.Error`.
  - Protocol error: the JSON-RPC number (same numeric value as `Error.code`, different field).
  - **Not** stored in `Error.code` when a function threw (`Error.code` stays `INTERNAL_ERROR`).
- **🔷** `message` — `e.message` from the throw, not the JSON-RPC label `"Internal error"`.

No protocol version bump. Same-tree client and daemon ship together.

### 1. `libocrpc/Error.vala` — `domain` + `gerror_code`

**Why:** wire must carry the thrown GError identity next to JSON-RPC `code`.

**Where:** class doc, then properties after `message`.

**Depends on:** none.

#### Remove

```vala
	/**
	 * Wire error object (''code'', ''message'').
	 *
	 * Not {@link GLib.Error} — {@link GLib.Object} for bin encode/decode.
	 * {@link code} is the numeric error code (a {@link RpcErrorCode} value).
	 */
	public class Error : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public int code { get; set; }
		public string message { get; set; default = ""; }
```

#### Replace with

```vala
	/**
	 * Wire error object (''code'', ''message'', ''domain'', ''gerror_code'').
	 *
	 * Not {@link GLib.Error} — {@link GLib.Object} for bin encode/decode.
	 * {@link code} is the JSON-RPC number (a {@link RpcErrorCode} value).
	 * {@link domain} / {@link gerror_code} are the {@link GLib.Error} to throw
	 * on the client (function throw or {@link RpcErrorCode}).
	 */
	public class Error : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public int code { get; set; }
		public string message { get; set; default = ""; }
		/**
		 * GLib error domain quark string (e.g. ''g-file-error-quark'').
		 * Always set on replies from {@link RpcErrorCode.to_error}.
		 */
		public string domain { get; set; default = ""; }
		/**
		 * Thrown {@link GLib.Error} code (e.g. {@link GLib.FileError.NOENT}).
		 * Not {@link code}.
		 */
		public int gerror_code { get; set; default = 0; }
```

### 2. `libocrpc/RpcErrorCode.vala` — `to_error` always fills domain

**Why:** client throws one `GLib.Error` from `domain` + `gerror_code`. No per-member switch. `new RpcErrorCode.INTERNAL_ERROR("")` is only to read the errordomain quark (Vala has no `RpcErrorCode.quark()`).

**Where:** `to_error`.

**Depends on:** §1.

#### Remove

```vala
		public static Error to_error(int code)
		{
			return new Error(code, ((RpcErrorCode) code).message);
		}
```

#### Replace with

```vala
		public static Error to_error(int code)
		{
			var err = new Error(code, ((RpcErrorCode) code).message);
			err.domain = (new RpcErrorCode.INTERNAL_ERROR("")).domain.to_string();
			err.gerror_code = code;
			return err;
		}
```

## Server

- **🔷** `⏳` Grow `reply_error` with an optional thrown `GLib.Error` (default `null`).
  - Vala cannot overload methods. Two-arg sites stay (`reply_error(request, code)`).
  - Invoke catch: `reply_error(request, INTERNAL_ERROR, e)` — always copy `e.message`, domain, `e.code`. No empty-string guards.
- **🔷** `⏳` `dispatch_new` / `dispatch_function` `catch (GLib.Error e)` around invoke passes `e`. Not `INTERNAL_ERROR` alone.

### 3. `libocrpc/Transport/Connection.vala` — grow `reply_error`

**Why:** invoke catch copies the thrown error as-is. Two-arg call sites stay.
Vala has no method overloads, so ''e'' is optional (`null` = protocol error).

**Where:** the existing `reply_error`.

**Depends on:** §1, §2.

#### Remove

```vala
		public void reply_error(
			OLLMrpc.Request request,
			int error_code
		)
		{
			this.reply(
				request,
				OLLMrpc.RpcErrorCode.to_response(error_code)
			);
		}
```

#### Replace with

```vala
		public void reply_error(
			OLLMrpc.Request request,
			int error_code,
			GLib.Error? e = null
		)
		{
			if (e == null) {
				this.reply(
					request,
					OLLMrpc.RpcErrorCode.to_response(error_code)
				);
				return;
			}
			var err = OLLMrpc.RpcErrorCode.to_error(error_code);
			err.message = e.message;
			err.domain = e.domain.to_string();
			err.gerror_code = e.code;
			this.reply(request, new Response() {
				error = err
			});
		}
```

### 4. `libocrpc/Gi.vala` — `dispatch_new` invoke catch

**Why:** constructor invoke throw reaches the client as the real error.

**Where:** `catch` after `g_function_info_invoke` in `dispatch_new`.

**Depends on:** §3.

#### Remove

```vala
			} catch (GLib.Error e) {
				this.request.connection.reply_error(
					this.request, (int) RpcErrorCode.INTERNAL_ERROR);
				return true;
			}
```

#### Replace with

```vala
			} catch (GLib.Error e) {
				this.request.connection.reply_error(this.request,
					(int) RpcErrorCode.INTERNAL_ERROR, e);
				return true;
			}
```

### 5. `libocrpc/Gi.vala` — `dispatch_function` invoke catch

**Why:** method invoke throw reaches the client as the real error.

**Where:** `catch` after `g_function_info_invoke` in `dispatch_function`.

**Depends on:** §3.

Same **Remove** / **Replace with** as §4 (the `catch` body is identical today).

## Client

- **🔷** `⏳` `Client.call` is `throws GLib.Error`.
- **🔷** `⏳` Throw **one** `GLib.Error` from the wire `domain` + `gerror_code` + `message`.
  - Same as calling the real function.
  - `catch (GLib.FileError e)` / `catch (RpcErrorCode e)` match on domain. No switch on JSON-RPC members.
- **🔷** `⏳` If `domain` is empty (hand-built `new Error(code, message)` in ollmfilesd), use the `RpcErrorCode` quark and `Error.code` as `gerror_code`. Still no switch.
- **🔷** `⏳` Transport failure (timeout, disconnect) throws the real I/O error, not a canned `Response`.
- **🔷** `⏳` Keep `failed(request, error)` then throw (UI still gets the signal).

### 6. `libocrpc/Client.vala` — `call`: throw

**Why:** the client behaves as if it called the real function.

**Where:** `call` doc, signature, transport `catch`, and `response.error` block.

**Depends on:** §1, §2.

##### Part 1 — Signature + doc

#### Remove

```vala
		 * @param request wire request; {@link Request.id} is set here
		 * @return wire response; check {@link Response.error}, or connect
		 *   to {@link failed} for user-visible handling
		 */
		public async Response call(Request request)
```

#### Replace with

```vala
		 * @param request wire request; {@link Request.id} is set here
		 * @return wire response on success
		 * @throws GLib.Error the error from the function or {@link RpcErrorCode};
		 *   the transport error on disconnect / timeout
		 */
		public async Response call(Request request) throws GLib.Error
```

##### Part 2 — Transport catch

#### Remove

```vala
			} catch (GLib.Error e) {
				var transport_error = new Error(
					(int) RpcErrorCode.INTERNAL_ERROR,
					e.message
				);
				this.failed(request, transport_error);
				return new Response() {
					id = request.id,
					error = transport_error
				};
			}
```

#### Replace with

```vala
			} catch (GLib.Error e) {
				var transport_error = new Error(
					(int) RpcErrorCode.INTERNAL_ERROR,
					e.message
				);
				transport_error.domain = e.domain.to_string();
				transport_error.gerror_code = e.code;
				this.failed(request, transport_error);
				throw e;
			}
```

##### Part 3 — Reply error throws

#### Remove

```vala
			if (response.error != null) {
				GLib.warning(
					"%s id=%d: %s",
					request.method,
					request.id,
					response.error.message
				);
				this.failed(request, response.error);
			}
			return response;
```

#### Replace with

```vala
			if (response.error == null) {
				return response;
			}
			GLib.warning("%s id=%d: %s",
				request.method, request.id, response.error.message);
			this.failed(request, response.error);
			var quark = GLib.Quark.from_string(response.error.domain);
			var code = response.error.gerror_code;
			if (response.error.domain == "") {
				quark = new RpcErrorCode.INTERNAL_ERROR("").domain;
				code = response.error.code;
			}
			throw new GLib.Error.literal(quark, code, response.error.message);
```

### 7. Docs that say `if (resp.error != null)`

**Why:** `call` throws; those examples would not compile.

**Where:** the `{{{ … }}}` samples in `libocrpc/Response.vala` (class doc), `libocrpc/Request.vala` (class doc). Success-only samples (`libocrpc/namespace.vala`, `libocrpc/Client.vala`) can stay as `var resp = yield rpc.call(...)`. Samples that check `resp.error` become a `throws` caller (error propagates). Do not show `catch (GLib.Error e)` that ignores the error.

**Depends on:** §6.

## Tests

### 8. Tests — `call.begin` / `call.end`

The ready callback cannot throw. Wrap `call.end`. On throw, **fail the test** — do not continue as success.

**Depends on:** §6.

#### Remove

```vala
			}, (obj, res) => {
				response = rpc.call.end(res);
				call_loop.quit();
			});
```

#### Replace with

```vala
			}, (obj, res) => {
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					this.check(command_line, false, e.message);
				}
				call_loop.quit();
			});
```

**🔷** `⏳` Same wrap at every `rpc.call.end` in `tests/rpc/gi-test.vala` and `tests/rpc/values-test.vala`.

---

## Smoke

- **🔷** `⏳` `tests/rpc/gi-test.vala`: after `Gio-Menu.get_n_items`, `Gio-File.new_for_path` on a missing path then `Gio-File.read`.
  - `call.end` throws.
  - Caught error is a file/I/O error (`catch (GLib.IOError)` / `GLib.FileError`), not the string `"Internal error"`.
  - `gerror_code` is the real not-found code, not `-32603`.
- **🔷** `⏳` Plain `INVALID_PARAMS` (bad `lease_id`) throws `RpcErrorCode.INVALID_PARAMS` (`catch (RpcErrorCode)`). `gerror_code` is `-32602`.

---

## LLM notes

- **🚫** Fence this in [`8.4.2`](done/RPC-8.4.2-DONE-rpc-ffi-typelib-invoke.md) / [`8.4.3`](done/RPC-8.4.3-DONE-rpc-ffi-typelib-method.md). Those keep the lightweight catch until this plan lands.
- **🚫** Put `fn.invoke` return pointer / boxed `INTERFACE` here — that is [`8.4.5`](done/RPC-8.4.5-DONE-rpc-ffi-leftovers.md). Remaining convert tags are [`8.4.6-DONE`](done/RPC-8.4.6-DONE-rpc-ffi-leftovers.md).
- **🚫** Put GError codes in `Error.code` — that field is JSON-RPC (`RpcErrorCode`).
- **🚫** New helper (`ensure_error`, `to_glib_error`) — throw inline in `call()`.
- **🚫** Two `reply_error` methods with the same name — Vala cannot overload. Optional `GLib.Error? e = null` on the existing method.
- **🚫** Switch on `RpcErrorCode` members to throw. Use `GLib.Error.literal(domain, gerror_code, message)`.
- **🚫** Change ollmfilesd `*Params` handlers. They already build `Error` with a message when they want one. Empty `domain` on those replies uses the `RpcErrorCode` quark in `call()`.
- **🚫** Bump bin protocol version.
- **🚫** Collapse client throws to `IOError.FAILED(message)` — that is the bug.
- **🚫** Audit or edit libocfiles / liboctools / liboccoder wrappers or their callers. That is [`RPC-8.4.4.1`](RPC-8.4.4.1-URGENT-rpc-consumer-audit.md).
- **ℹ️** gnome-shell-rpc `Session.call` can stop wrapping `IOError.FAILED` once it uses this `Client.call`. Not this repo.
