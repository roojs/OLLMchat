/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

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
