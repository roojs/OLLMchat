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
 * JSON-RPC wire types shared by {@link OLLMfiles.RpcClient} and {@code ollmfilesd}.
 */
namespace OLLMfiles.Rpc
{
	internal class NamespaceDoc {}

	/** {@link Type.name} → GType for {@link Response.result} deserialize on the client. */
	public static Gee.HashMap<string, Type> types;

	/** Record a wire result type (see each type's {@link rpc_register}). */
	public static void register(Type t)
	{
		if (types == null) {
			types = new Gee.HashMap<string, Type>();
		}
		types.set(t.name(), t);
	}
}
