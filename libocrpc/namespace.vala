/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

/**
 * Bin RPC wire types in libocrpc — shared by client and ollmfilesd.
 *
 * Request arguments use a typed CallParam subclass on Request.param.
 * Register wire types with Bin.register before connect/call.
 *
 * == Minimal client call ==
 *
 * {{{
 * OLLMrpc.Daemon.rpc_register();
 * var rpc = new OLLMrpc.Client(data_dir, "ollmfilesd.pid", "ollmfilesd.sock");
 * yield rpc.connect(hello_request);
 * var resp = yield rpc.call(new OLLMrpc.Request() {
 *     method = "Daemon.hello",
 *     param = new OLLMfilesd.DaemonParams() { protocol = 1 }
 * });
 * }}}
 */
namespace OLLMrpc
{
}
