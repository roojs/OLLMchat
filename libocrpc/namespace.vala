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
 * JSON-RPC wire types in {@code libocrpc} — shared by client and {@code ollmfilesd}.
 */
namespace OLLMrpc
{
	internal class NamespaceDoc {}

	/** Wire name → GType for {@link Response.result} deserialize on the client. */
	public static Gee.HashMap<string, Type> types;

	/** Record a wire result type (see each class {@link rpc_register}). */
	public static void register(string name, Type t)
	{
		if (types == null) {
			types = new Gee.HashMap<string, Type>();
		}
		types.set(name, t);
	}
}
