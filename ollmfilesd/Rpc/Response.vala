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

namespace OLLMfilesd.Rpc
{
	/** JSON-RPC 2.0 response (has wire `id`, plus `result` or `error`). */
	public class Response : GLib.Object, Json.Serializable
	{
		public string jsonrpc { get; set; default = "2.0"; }
		public int id { get; construct set; }
		public Error? error { get; set; default = null; }
		public GLib.Object? result { get; set; default = null; }
		public string msg { get; set; default = ""; }

		public Response(int id)
		{
			GLib.Object(id: id);
		}

		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}

		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			Value val = Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		public override Json.Node serialize_property(
			string property_name,
			Value value,
			ParamSpec pspec
		) {
			switch (property_name) {
				case "error":
					if (this.error == null) {
						return null;
					}
					return Json.gobject_serialize(this.error);
				case "result":
					if (this.result == null) {
						return null;
					}
					return Json.gobject_serialize(this.result);
				default:
					return default_serialize_property(property_name, value, pspec);
			}
		}
	}
}
