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

/**
 * Binary RPC client and wire types shared by apps and ollmfilesd.
 *
 * The OLLMrpc namespace is the client library for talking to ollmfilesd over a
 * Unix socket (or stdio/TCP), and for calling HTTPS JSON APIs with the same
 * {@link Request} / {@link Response} shape. {@link Client} owns the channel.
 * {@link Request} carries ''method'', a typed {@link CallParam} on ''param'',
 * and optional ''result_type''. {@link Bin} serializes {@link Bin.Serializable}
 * GObjects on the wire. {@link Transport} is the daemon listen/connection side.
 *
 * == Architecture Benefits ==
 *
 *  * Typed params: CallParam subclasses, not ad-hoc JSON bags
 *  * One client: Unix socket for ollmfilesd, HTTPS URL for Hub-style APIs
 *  * Bin codec: compact wire with JIT property keys ({@link Bin.Stream})
 *  * Shared types: same Request/Response on client and daemon
 *
 * == Usage Examples ==
 *
 * === ollmfilesd (Unix socket) ===
 *
 * {{{
 * OLLMrpc.Daemon.rpc_register();
 * OLLMfilesd.DaemonParams.rpc_register();
 * var rpc = new OLLMrpc.Client(
 *     GLib.Path.build_filename(
 *         GLib.Environment.get_user_data_dir(), "ollmchat"),
 *     "ollmfilesd.pid",
 *     "ollmfilesd.sock"
 * );
 * if (!yield rpc.connect(new OLLMrpc.Request() {
 *     method = "Daemon.hello",
 *     param = new OLLMfilesd.DaemonParams() {
 *         protocol = 1,
 *         client = "my-app"
 *     }
 * })) {
 *     GLib.error("%s", rpc.connect_error);
 * }
 * var resp = yield rpc.call(new OLLMrpc.Request() {
 *     method = "ProjectManager.load_projects_from_db",
 *     param = new OLLMfilesd.ProjectParams()
 * });
 * }}}
 *
 * === HTTPS JSON (e.g. Hugging Face Hub) ===
 *
 * {{{
 * OLLMhf.rpc_register();
 * var rpc = new OLLMrpc.Client("", "", "https://huggingface.co");
 * yield rpc.connect(new OLLMrpc.Request());
 * var resp = yield rpc.call(new OLLMrpc.Request() {
 *     method = "/api/models",
 *     param = new OLLMhf.Param.Search() {
 *         search = "llama",
 *         filter = "gguf",
 *         limit = 10
 *     },
 *     result_type = typeof(OLLMhf.ModelArray)
 * });
 * }}}
 *
 * == Best Practices ==
 *
 *  1. Registration: call each wire type's ''rpc_register()'' before connect
 *  2. Params: use a CallParam subclass on Request.param, not raw maps
 *  3. Results: set result_type when the HTTP path should decode to a GType
 *  4. Errors: check Response.error after every call
 *  5. Bin round-trips: see {@link Bin} and docs/bin-rpc-protocol.md
 */
namespace OLLMrpc
{
	/**
	 * Namespace documentation marker.
	 * This file contains namespace-level documentation for OLLMrpc.
	 */
	internal class NamespaceDoc {}
}
