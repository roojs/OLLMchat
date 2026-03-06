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
 * along with this library; if not, see <https://www.gnu.org/licenses/>.
 */

namespace OLLMmcp.Client
{
	/**
	 * Abstract MCP client: one connection to one MCP server.
	 *
	 * Subclasses implement transport (stdio subprocess or HTTP). connect() establishes
	 * the channel and optionally runs the MCP initialize handshake; tools() and
	 * call() send JSON-RPC and return results.
	 */
	public abstract class Base : Object
	{
		public abstract async void connect() throws Error;
		/** Close the MCP connection (subprocess/HTTP). Named to avoid hiding GLib.Object.disconnect. */
		public abstract new void disconnect();
		public abstract async Gee.ArrayList<OLLMmcp.Factory> tools() throws Error;
		public abstract async string call(string name, Json.Object arguments) throws Error;
	}
}
