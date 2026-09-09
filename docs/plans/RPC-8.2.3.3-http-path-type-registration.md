# 8.2.3.3 — HTTP path ↔ request/response type registration

**Status:** **DONE** — implemented + smoke `test-rpc-http-routes`

> **Do not update `docs/plans/RPC-1.0-summary.md` for this plan.**

**Parent:** [`RPC-8.2.3-http-server-rpc.md`](RPC-8.2.3-http-server-rpc.md)

**Pause gate:** Decide / implement this **before** [`RPC-8.2.3.2-http-bin-session.md`](RPC-8.2.3.2-http-bin-session.md). Streaming ([`8.2.3.1`](RPC-8.2.3.1-http-json-streaming.md)) can keep Phase 1 `/rpc` + body `method`.

**Related:** [`RPC-8.2.1`](RPC-8.2.1-libocrpc-auto-json-and-http-client.md); socket `Request.add_class` / `register` / `Bin.register`

**Layout:** `docs/guide-to-writing-plans.md` — **Checklist for plans**

---

## Purpose

- **🔷** Map **HTTP verb + full path** → short method + request/response GTypes + handler.
- **🔷** Register from the service `rpc_register()` (nested payload types + one bulk call).
- **🔷** `Http.routes` **also** runs `Request.add_class` (no separate `add_class` for the same methods).
- **🔷** Global verb → path `HashMap` lookup (no segment walk).
- **⏳** Smoke: Alarm **list** + **create** on exact paths (no `{id}` in first cut). → **✔️** `test-rpc-http-routes`
- **🚫** Bin session / TLS — **8.2.3.2** / later.

---

## Locked shape (from review)

- **🔷** Short method names only (`list`, not `RPC-Alarm.list`).
- **🔷** Routes listed inside `Service.rpc_register()`; nested `Alarm*.rpc_register()`.
- **🔷** Global registrar (any `HttpServer` uses it).
- **🔷** Bulk register; each HTTP tuple **leads with path** (one full route per line after wire name/type).
- **🔷** Resolve: exact `by_verb[verb][path]`, else last segment → same prefix if `variable`.
- **🔷** `Http.add(...)` for one route; `Http.routes(...)` bulk-calls `add` and **`Request.add_class`**.
- **🔷** Path param (v1): one registration — trailing `/{id}` → strip + `variable` (optional id → FFI ''s'', empty if absent). Not two methods on the same path.
- **🔷** `HttpServer.rpc_path` (default `"/rpc"`) — body-`method` POST endpoint.
- **💩** Keep body-`method` POST on `rpc_path` alongside path routes.
- **💩** Empty request type: `typeof(void)`.
- **💩** Success body: JSON `Response` with `retval` holding the typed object (same envelope as Phase 1).
- **💩** `Bin.register`: same alias + same `GType` = no-op; mismatch still errors.

---

## Alarm API (smoke)

| Verb | Path | Request type | Response type | Method | Sig |
|------|------|--------------|---------------|--------|-----|
| `GET` | `/v1/alarms/{id}` | `typeof(void)` | (list or one) | `get` | `"s"` |
| `POST` | `/v1/alarms` | `AlarmCreate` | `Alarm` | `create` | `"o"` |
| `DELETE` | `/v1/alarms/{id}` | `typeof(void)` | `typeof(void)` / empty | `remove` | `"s"` |

**✔️** `{id}` = optional trailing segment on that one method (empty ''s'' when absent).

### Boot (`Service.rpc_register`)

```vala
public static void rpc_register()
{
	Alarm.rpc_register();
	AlarmList.rpc_register();
	AlarmCreate.rpc_register();
	AlarmListQuery.rpc_register();

	OLLMrpc.Http.routes("RPC-Alarm", typeof(Service),
		"/v1/alarms/{id}", "GET", "get", "s", typeof(void), typeof(void),
		"/v1/alarms", "POST", "create", "o", typeof(AlarmCreate), typeof(Alarm),
		"/v1/alarms/{id}", "DELETE", "remove", "s", typeof(void), typeof(void)
	);
}
```

**ℹ️** Wire name + handler type stay on the `routes(` line. Each following
line is one route: `path`, `verb`, `method`, `sig`, `request_type`,
`response_type`.

---

## Code proposals

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libocrpc/Http/Route.vala` — leaf + global maps + `routes` / `add`

**Why:** Verb → full-path hash; `routes` drives `add_class` + HTTP rows.

**Where:** new files under `libocrpc/Http/`; wire in `libocrpc/meson.build`.

#### Add

**ℹ️** Docblocks are part of the deliverable (Valadoc; see
`docs/code-documentation.md`). Class + every public method needs overview,
`@param` / `@return`, and `{{{ … }}}` samples — not one-liners.

```vala
namespace OLLMrpc
{
	/**
	 * HTTP verb+path → RPC method and body GTypes.
	 *
	 * Services call {@link routes} (or {@link add}) from
	 * ''rpc_register()''. {@link Transport.HttpServer} looks up
	 * the route table and builds a {@link Request} for
	 * ''wire_name.method''. Socket FFI still uses
	 * {@link Request.add_class} / {@link Request.register}; path
	 * registration fills the same method maps.
	 *
	 * == Usage Examples ==
	 *
	 * === Bulk from a service ===
	 *
	 * {{{
	 * OLLMrpc.Http.routes("RPC-Alarm", typeof(Service),
	 *     "/v1/alarms", "GET", "list", "", typeof(AlarmListQuery), typeof(AlarmList),
	 *     "/v1/alarms", "POST", "create", "o", typeof(AlarmCreate), typeof(Alarm)
	 * );
	 * OLLMrpc.Request.register("RPC-Alarm", new Service());
	 * }}}
	 *
	 * === One extra path ===
	 *
	 * {{{
	 * OLLMrpc.Http.add("RPC-Alarm", typeof(Service),
	 *     "/v1/alarms/ping", "GET", "ping", typeof(void), typeof(void)
	 * );
	 * }}}
	 */
	namespace Http
	{
		/**
		 * One registered HTTP path under a verb.
		 *
		 * Filled by {@link add} / {@link routes}. Handlers use
		 * ''wire_name'' + ''.'' + ''method'' as {@link Request.method}.
		 */
		public class Route : GLib.Object
		{
			/**
			 * Short FFI method name (e.g. ''list''), not the wire
			 * prefix.
			 */
			public string method { get; set; default = ""; }

			/**
			 * Wire object prefix (e.g. ''RPC-Alarm''), same as
			 * {@link Request.add_class}.
			 */
			public string wire_name { get; set; default = ""; }

			/**
			 * Handler GType passed to {@link routes} / {@link add}.
			 */
			public GLib.Type handler { get; set; }

			/**
			 * JSON/bin body type for the request; ''typeof(void)''
			 * when there is no body.
			 */
			public GLib.Type request_type { get; set; }

			/**
			 * Type expected in {@link Response.retval} after
			 * dispatch.
			 */
			public GLib.Type response_type { get; set; }
		}

		/** Verb → exact path → {@link Route} (filled by {@link add}). */
		internal static Gee.HashMap<string, Gee.HashMap<string, Route>> by_verb;

		/**
		 * Register one HTTP route (exact path key under verb).
		 *
		 * Does ''not'' call {@link Request.add_class}. Use when the
		 * method/sig is already registered, or for a late/test-only
		 * path. Prefer {@link routes} from service ''rpc_register()''.
		 *
		 * == Example ==
		 *
		 * {{{
		 * OLLMrpc.Request.add_class("RPC-Alarm", typeof(Service), "ping", "");
		 * OLLMrpc.Http.add("RPC-Alarm", typeof(Service),
		 *     "/v1/alarms/ping", "GET", "ping", typeof(void), typeof(void)
		 * );
		 * }}}
		 *
		 * @param wire_name wire object prefix (e.g. RPC-Alarm)
		 * @param handler handler GType (same as add_class)
		 * @param path exact path key (e.g. /v1/alarms)
		 * @param verb HTTP verb (GET, POST, …)
		 * @param method_name short method (e.g. list)
		 * @param request_type body GType, or typeof(void)
		 * @param response_type retval GType
		 */
		public static void add(
			string wire_name,
			GLib.Type handler,
			string path,
			string verb,
			string method_name,
			GLib.Type request_type,
			GLib.Type response_type
		) {
			if (by_verb == null) {
				by_verb = new Gee.HashMap<string, Gee.HashMap<string, Route>>();
			}
			if (!by_verb.has_key(verb)) {
				by_verb.set(verb, new Gee.HashMap<string, Route>());
			}
			by_verb.get(verb).set(path, new Route() {
				method = method_name,
				wire_name = wire_name,
				handler = handler,
				request_type = request_type,
				response_type = response_type
			});
		}

		/**
		 * Register FFI methods and HTTP routes for one wire prefix.
		 *
		 * For each tuple calls {@link add} and
		 * {@link Request.add_class} (one method/sig pair). Put wire
		 * name and handler on the ''routes('' line; each following
		 * line is one route. Tuple order: path, verb, method, sig,
		 * request_type, response_type. Repeat until path is null.
		 * Sig letters match {@link Request.add_class}
		 * (''""'' = no extra args).
		 *
		 * == Example ==
		 *
		 * {{{
		 * OLLMrpc.Http.routes("RPC-Alarm", typeof(Service),
		 *     "/v1/alarms", "GET", "list", "", typeof(AlarmListQuery), typeof(AlarmList),
		 *     "/v1/alarms", "POST", "create", "o", typeof(AlarmCreate), typeof(Alarm)
		 * );
		 * }}}
		 *
		 * @param name wire object prefix (e.g. RPC-Alarm)
		 * @param type handler GType
		 * @param ... path, verb, method, sig, request_type,
		 *   response_type (repeat; end with null path)
		 */
		public static void routes(string name, GLib.Type type, ...)
		{
			var l = va_list();
			while (true) {
				var path = l.arg<string>();
				if (path == null) {
					break;
				}
				var verb = l.arg<string>();
				var method = l.arg<string>();
				var sig = l.arg<string>();
				var request_type = l.arg<GLib.Type>();
				var response_type = l.arg<GLib.Type>();
				add(name, type, path, verb, method, request_type, response_type);
				OLLMrpc.Request.add_class(name, type, method, sig);
			}
		}
	}
}
```

**🔷** `add` — one route (tests, late bind, or a single extra path).
**🔷** `routes` — service `rpc_register`: FFI pairs + many `add` calls.
**🔷** `by_verb` — `internal` map; `HttpServer.on_route` looks up in place (no `resolve` method).
**🚫** No `Request.add_class_from_pairs` — call existing `Request.add_class` per tuple.

### 2. `libocrpc/Request.vala` — unchanged

**ℹ️** No new API. `Http.routes` calls `Request.add_class(name, type, method, sig)` once per route.

### 3. `libocrpc/Bin/Stream.vala` — idempotent `register`

**Why:** Nested `rpc_register` may run more than once.

#### Remove

```vala
		if (alias_to_gtype.has_key(alias)) {
			throw new StreamError.REGISTRATION(
				"duplicate register of alias '%s'",
				alias
			);
		}

		alias_to_gtype.set(alias, gtype);
		gtype_to_alias.set(gtype, alias);
```

#### Replace with

```vala
		if (alias_to_gtype.has_key(alias)) {
			if (alias_to_gtype.get(alias) == gtype) {
				return;
			}
			throw new StreamError.REGISTRATION(
				"duplicate register of alias '%s'",
				alias
			);
		}
		alias_to_gtype.set(alias, gtype);
		gtype_to_alias.set(gtype, alias);
```

### 4. `libocrpc/Transport/HttpServer.vala` — path routes + `rpc_path`

**Why:** Resolve verb+path; build `Request` with `RPC-{name}.{method}`; decode body into `request_type` when not `typeof(void)`. Body-`method` POST uses configurable `rpc_path` (default `"/rpc"`), not a hardcoded string.

#### Add (property on `HttpServer`)

```vala
		/**
		 * Path for POST body-method RPC (Hello / stream).
		 *
		 * Default ''/rpc''. Typed {@link Http.routes} paths are separate.
		 */
		public string rpc_path { get; set; default = "/rpc"; }
```

#### Replace with (handler registration in `start`)

```vala
			this.soup.add_handler(this.rpc_path, this.on_rpc);
			this.soup.add_handler(null, this.on_route);
```

#### Add

```vala
		private void on_route(
			Soup.Server server,
			Soup.ServerMessage msg,
			string path,
			GLib.HashTable<string, string>? query
		) {
			if (path == this.rpc_path) {
				return;
			}
			if (OLLMrpc.Http.by_verb == null
				|| !OLLMrpc.Http.by_verb.has_key(msg.get_method())) {
				msg.set_status(404, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY, "not found".data);
				return;
			}
			var paths = OLLMrpc.Http.by_verb.get(msg.get_method());
			if (!paths.has_key(path)) {
				msg.set_status(404, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY, "not found".data);
				return;
			}
			var route = paths.get(path);
			var reply = new HttpReply(this.soup, msg) {
				live_handles = this.live_handles
			};
			var request = new Request() {
				method = route.wire_name + "." + route.method,
				connection = reply
			};
			if (route.request_type != typeof(void)) {
				var bytes = msg.get_request_body().flatten();
				// decode JSON object → route.request_type via Bin.Json AUTO
				// into request.args (object arg) — mirror Http client reverse
				// of json_to_bin; GET may use empty body + query reflection ⏳
			}
			if (!request.dispatch()) {
				msg.set_status(404, null);
				msg.set_response("text/plain", Soup.MemoryUse.COPY,
					("no handler for '" + request.method + "'").data);
			}
		}
```

**💩** Query → `AlarmListQuery` reflection for GET — fill when implementing; POST body decode is required for `create`.

**ℹ️** Soup `add_handler(null, …)` is the default handler; skip `on_route` when `path == this.rpc_path` so it does not steal the body-method endpoint.
### 5. `libocrpc/meson.build` — compile `Http/Route.vala`

#### Add

```meson
  'Http/Route.vala',
```

(next to other `libocrpc` sources)

### 6. `tests/rpc/http-routes-test.vala` — Alarm list/create smoke

**Why:** Prove path registration without depending on bin session.

#### Add (outline)

- Register Alarm types + `Http.routes` + `Request.register`.
- Start `HttpServer(0)`.
- `POST http://127.0.0.1:port/v1/alarms` with `AlarmCreate` JSON → expect `Alarm` in `Response.retval`.
- `GET http://127.0.0.1:port/v1/alarms` → expect `AlarmList`.
- Keep existing `http-server-test` `/rpc` Hello World green.

Wire executable in `tests/meson.build` like `test-rpc-http-server`.

---

## Suggested order

1. **✔️** §1 `Http.add` / `Http.routes`
2. **✔️** §3 idempotent `Bin.register`
3. **✔️** §4 `HttpServer.rpc_path` + `on_route` + POST body decode
4. **✔️** §5–§6 meson + exact-path smoke
5. **✔️** One `{id}` path param → first FFI ''s''
6. **💩** `⏳` GET query → request ''o'' (optional; list works with sig `""` today)
7. **🚫** Bin session / multi path-args (later)

---

## Backlog

- **🔷** `✔️` Exact-path + `{id}` smoke (`test-rpc-http-routes`).
- **💩** `⏳` GET query reflection into `request_type` / pass as ''o'' when listed (optional).
- **💩** `⏳` More than one path capture (sig `"ss…"` / `"sso"` …) — later.
- **🚫** Full segment-tree router.
- **🚫** Per-server route tables.
- **🚫** Bin session (see **8.2.3.2**).

---

## LLM notes

- **ℹ️** Alarm demo types live in the **test** (or a tiny example), not shipped as product API in `libocrpc`.
- **ℹ️** Example formatting: `routes("Wire", typeof(T),` then one path-first route per line.
