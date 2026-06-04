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

namespace OLLMfiles
{
	/**
	 * {@link Json.Serializable} objects that deserialize wire JSON in place.
	 *
	 * Add on types that already implement {@link Json.Serializable}:
	 * {@code public class Project : Object, JsonOverlay, Json.Serializable}.
	 * Use {@link overlay_jobject} / {@link overlay_jtext} instead of
	 * {@link Json.gobject_from_data} when the instance already exists.
	 */
	public interface JsonOverlay : Json.Serializable
	{
		/**
		 * Deserialize each member of {@link obj} onto this object.
		 *
		 * @param obj JSON object whose keys match GObject property names
		 */
		public void overlay_jobject(Json.Object obj) throws GLib.IOError
		{
			var target = (GLib.Object) this;
			foreach (var name in obj.get_members()) {
				var pspec = target.get_class().find_property(name);
				if (pspec == null) {
					continue;
				}
				Value val;
				if (this.deserialize_property(
					name,
					out val,
					pspec,
					obj.get_member(name)
				)) {
					this.set_property(pspec, val);
				}
			}
		}

		/**
		 * Parse {@link data} as a JSON object and {@link overlay_jobject}.
		 *
		 * @param data UTF-8 JSON object text
		 */
		public void overlay_jtext(string data) throws GLib.IOError
		{
			var parser = new Json.Parser();
			try {
				parser.load_from_data(data, -1);
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED(
					"JsonOverlay: parse: " + e.message
				);
			}
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				throw new GLib.IOError.FAILED(
					"JsonOverlay: expected a JSON object"
				);
			}
			this.overlay_jobject(root.get_object());
		}
	}
}
