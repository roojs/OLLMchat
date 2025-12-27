/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMchat.Settings
{
	/**
	 * Loading status information for a model pull operation.
	 * 
	 * Combines both runtime tracking and persistence data.
	 * 
	 * @since 1.3.4
	 */
	internal class LoadingStatus : GLib.Object, Json.Serializable
	{
		// Persistence fields (saved to JSON)
		public string status { get; set; default = ""; }
		public int progress { get; set; default = 0; }
		public string started { get; set; default = ""; }
		public string error { get; set; default = ""; }
		public string last_chunk_status { get; set; default = ""; }
		public int retry_count { get; set; default = 0; }
		public string connection_url { get; set; default = ""; }
		
		// Runtime fields (not serialized)
		public bool active = false;
		public int64 last_update_time = 0;
		public OLLMchat.Settings.Connection? connection = null;
		
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
		
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			// Don't serialize runtime-only fields
			if (property_name == "active" || property_name == "last_update_time" || property_name == "connection") {
				return null;
			}
			// Serialize all other fields (defaults will handle empty/zero values)
			return default_serialize_property(property_name, value, pspec);
		}
	}
}

