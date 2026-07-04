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
	 * GObject types that read/write on a {@link Stream} session.
	 *
	 * Default {@link bin_write_prop} / {@link bin_read_prop} on {@link Object}
	 * cover scalar fundamentals and nested {@link Serializable} object properties.
	 *
	 * Override for transient fields, {@code Gee.ArrayList} / list properties,
	 * {@code uint8[]} (wire as blob or typed array — see docs/bin-rpc-protocol.md),
	 * and any other non-scalar shape.
	 *
	 * Override {@link bin_pre} / {@link bin_post} for work before or after
	 * inbound property decode on this object.
	 */
	public interface Serializable : GLib.Object
	{
		public abstract void bin_write (Stream ctx) throws GLib.Error;

		/**
		 * Encode one GObject property onto the stream.
		 *
		 * @param ctx active bin session
		 * @param prop property metadata
		 */
		public abstract void bin_write_prop (
			Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error;

		public abstract void bin_read (Stream ctx) throws GLib.Error;

		/**
		 * Run before inbound properties are decoded into this object.
		 *
		 * @param ctx active bin session
		 */
		public abstract void bin_pre (Stream ctx) throws GLib.Error;

		/**
		 * Run after all inbound properties are decoded.
		 *
		 * @param ctx active bin session
		 */
		public abstract void bin_post (Stream ctx) throws GLib.Error;

		/**
		 * Decode one wire property into this object.
		 *
		 * @param ctx active bin session
		 * @param prop property metadata
		 * @param type_byte wire type byte ({@link GLib.Type} fundamental; bit 7 = array)
		 */
		public abstract void bin_read_prop (
			Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error;
	}
}
