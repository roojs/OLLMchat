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
	private class CtorBag : GLib.Object
	{
		public Gee.ArrayList<string> names = new Gee.ArrayList<string>();
		public Gee.ArrayList<GLib.Value?> props = new Gee.ArrayList<GLib.Value?>();
	}

	/**
	 * Live proxy that takes the wire lease as a construct property.
	 *
	 * {@link Bin.Stream.parse_object} calls {@link GLib.Object.new} with
	 * ''rpc-lid'' on the live path. Stub ''construct'' reads
	 * {@link rpc_lid} (non-zero → already leased; skip ''Ns-Type.new'').
	 * Construct setters that run before that block stash values with
	 * {@link rpc_ctor_stash} and read them back with {@link rpc_ctor_get}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * public class Actor : GLib.Object, OLLMrpc.Live.Interface {
	 *     public uint64 rpc_lid { get; set construct; default = 0; }
	 *     construct {
	 *         if (this.rpc_lid != 0) {
	 *             return;
	 *         }
	 *         // else create remote peer and set rpc_lid
	 *     }
	 * }
	 * }}}
	 */
	public interface Interface : GLib.Object
	{
		/**
		 * Wire lease handle for this proxy (0 = none / local create).
		 *
		 * GObject name ''rpc-lid''. Set by live decode via
		 * {@link GLib.Object.new}.
		 */
		[GIR (visible = false)]
		public abstract uint64 rpc_lid { get; set construct; }

		/**
		 * Copy one construct property onto this instance.
		 *
		 * Call from a property ''construct'' setter. Does not RPC.
		 *
		 * @param name GIR property name
		 * @param value the construct value to keep until ''construct''
		 */
		[GIR (visible = false)]
		public void rpc_ctor_stash(string name, GLib.Value value)
		{
			var bag = this.get_data<CtorBag>("rpc-ctor");
			if (bag == null) {
				bag = new CtorBag();
				this.set_data("rpc-ctor", bag);
			}
			var copy = GLib.Value(value.type());
			value.copy(ref copy);
			bag.names.add(name);
			bag.props.add(copy);
		}

		/**
		 * Drop the construct stash. Safe when nothing was stored.
		 */
		[GIR (visible = false)]
		public void rpc_ctor_clear()
		{
			this.set_data("rpc-ctor", null);
		}

		/**
		 * Stashed construct value for one property.
		 *
		 * @param name GIR property name
		 * @return the stashed value, or null when this construction
		 *     did not set it
		 */
		[GIR (visible = false)]
		public GLib.Value? rpc_ctor_get(string name)
		{
			var bag = this.get_data<CtorBag>("rpc-ctor");
			if (bag == null) {
				return null;
			}
			for (var i = 0; i < bag.names.size; i++) {
				if (bag.names.get(i) != name) {
					continue;
				}
				return bag.props.get(i);
			}
			return null;
		}

		/**
		 * Whether this construction stashed at least one property.
		 *
		 * @return true when at least one construct property was stashed
		 */
		[GIR (visible = false)]
		public bool rpc_ctor_has()
		{
			var bag = this.get_data<CtorBag>("rpc-ctor");
			return bag != null && bag.names.size > 0;
		}
	}
}
