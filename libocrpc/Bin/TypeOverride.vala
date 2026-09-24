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
	 * Pack and unpack one argument type on the signal wire.
	 *
	 * The registry is keyed by {@link override_type}. A missing type uses the
	 * bin value unchanged.
	 */
	public abstract class TypeOverride : GLib.Object
	{
		/**
		 * GType this override replaces on the wire.
		 *
		 * Lookup uses this, not the signal name.
		 */
		public abstract GLib.Type override_type { get; }

		/**
		 * Write src as wire fields.
		 *
		 * @param src the signal argument
		 * @return fields in wire order
		 */
		public abstract Gee.ArrayList<GLib.Value?> pack(GLib.Value src);

		/**
		 * Build the argument from wire fields.
		 *
		 * @param fields the notification arguments
		 * @param index first field for this argument
		 * @param consumed how many fields this argument used
		 * @return the argument value
		 */
		public abstract GLib.Value unpack(
			Gee.ArrayList<GLib.Value?> fields,
			int index,
			out int consumed
		);

		static Gee.HashMap<GLib.Type, TypeOverride>? by_type;

		/**
		 * Record one override under its argument type.
		 *
		 * @param over the override to record
		 */
		public static void register(TypeOverride over)
		{
			if (by_type == null) {
				by_type = new Gee.HashMap<GLib.Type, TypeOverride>();
			}
			by_type.set(over.override_type, over);
		}

		/**
		 * Find the override for a type.
		 *
		 * @param type the argument GType
		 * @return the override, or null when this type has none
		 */
		public static TypeOverride? lookup(GLib.Type type)
		{
			if (by_type == null || !by_type.has_key(type)) {
				return null;
			}
			return by_type.get(type);
		}

		/**
		 * Turn signal parameters into notification fields.
		 *
		 * Skips {@code param_values[0]}, the instance. An override replaces
		 * one parameter with the fields from {@link pack}.
		 *
		 * @param param_values instance then signal arguments
		 * @return fields in wire order
		 */
		public static Gee.ArrayList<GLib.Value?> pack_params(GLib.Value[] param_values)
		{
			var packed = new Gee.ArrayList<GLib.Value?>();
			for (var i = 1; i < param_values.length; i++) {
				var src = param_values[i];
				var helper = TypeOverride.lookup(src.type());
				if (helper == null) {
					packed.add(src);
					continue;
				}
				foreach (var field in helper.pack(src)) {
					packed.add(field);
				}
			}
			return packed;
		}

		/**
		 * Fill one GValue per signal parameter from notification fields.
		 *
		 * {@code dest[0]} is the instance and is left alone. An override
		 * consumes the field count from {@link unpack}. Any other parameter
		 * consumes one field.
		 *
		 * @param param_types signal parameter types, not including the instance
		 * @param fields the notification arguments
		 * @param dest instance at 0, then one slot per parameter, already inited
		 * @return how many fields were consumed
		 */
		public static int fill_params(
			GLib.Type[] param_types,
			Gee.ArrayList<GLib.Value?> fields,
			GLib.Value[] dest
		) {
			var wire = 0;
			for (var i = 0; i < param_types.length; i++) {
				var helper = TypeOverride.lookup(param_types[i]);
				if (helper != null) {
					var consumed = 0;
					helper.unpack(fields, wire, out consumed).transform(ref dest[i + 1]);
					wire += consumed;
					continue;
				}
				if (wire >= fields.size) {
					wire++;
					continue;
				}
				var src = fields.get(wire);
				if (!src.transform(ref dest[i + 1])
						&& src.holds(GLib.Type.OBJECT)
						&& param_types[i].is_a(GLib.Type.OBJECT)) {
					dest[i + 1].set_object(src.get_object());
				}
				wire++;
			}
			return wire;
		}

		/**
		 * Drop one value this override kept alive for {@link unpack}.
		 *
		 * Default does nothing.
		 */
		public virtual void release()
		{
		}

		/**
		 * Call {@link release} once per parameter that has an override.
		 *
		 * @param param_types signal parameter types, not including the instance
		 */
		public static void release_params(GLib.Type[] param_types)
		{
			foreach (var type in param_types) {
				var helper = TypeOverride.lookup(type);
				if (helper == null) {
					continue;
				}
				helper.release();
			}
		}
	}
}
