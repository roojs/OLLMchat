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

namespace OLLMrpc.Bin
{
	/**
	 * Binary wire codec failures (throw/catch).
	 *
	 * Not {@link GLib.Error} abort — use {@code throw new Error.*} from
	 * {@link Stream} and {@link Serializable} encode/decode paths.
	 */
	public errordomain Error
	{
		PROTOCOL,
		REGISTRATION,
		PROPERTY
	}
}
