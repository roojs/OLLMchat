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
	 * Convenience base for {@link Serializable} GObject types.
	 *
	 * Subclasses can {@code override} {@link bin_write_prop} / {@link bin_read_prop}
	 * for lists, blobs, and transient fields; {@link bin_pre} / {@link bin_post}
	 * for inbound object hooks; delegate to {@code base} for scalars and nested
	 * {@link Serializable} properties.
	 */
	public abstract class Object : GLib.Object, Serializable
	{
	}
}
