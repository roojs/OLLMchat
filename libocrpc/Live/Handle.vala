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

namespace OLLMrpc.Live
{
	/**
	 * Live proxy that takes the wire lease as a construct property.
	 *
	 * {@link Bin.Stream.parse_object} calls {@link GLib.Object.new} with
	 * ''rpc-lid'' on the live path. Stub {@code construct} reads
	 * {@link rpc_lid} (non-zero → already leased; skip ''Ns-Type.new'').
	 *
	 * == Example ==
	 *
	 * {{{
	 * public class Actor : GLib.Object, OLLMrpc.Live.Handle {
	 *     public uint64 rpc_lid { get; set construct; default = 0; }
	 *     construct {
	 *         if (this.rpc_lid != 0) {
	 *             return;
	 *         }
	 *         // else create remote peer and set rpc_lid / qdata
	 *     }
	 * }
	 * }}}
	 */
	public interface Handle : GLib.Object
	{
		/**
		 * Wire lease handle for this proxy (0 = none / local create).
		 *
		 * GObject name ''rpc-lid''. Set by live decode via
		 * {@link GLib.Object.new}.
		 */
		public abstract uint64 rpc_lid { get; set construct; }
	}
}
