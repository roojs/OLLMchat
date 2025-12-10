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

namespace OLLMchat.Call
{
	/**
	 * Options object for Ollama API calls.
	 * 
	 * This is technically accessed through call.options (e.g., chatCall.options, embedCall.options).
	 * Contains all runtime parameters that can be passed to Ollama API.
	 * Default values are -1 for numbers (indicating no value set) or empty string for strings.
	 */
	public class Options : Object, Json.Serializable
	{
		// Numeric options - default to -1 (no value set)
		public int seed { get; set; default = -1; }
		public double temperature { get; set; default = -1.0; }
		public double top_p { get; set; default = -1.0; }
		public int top_k { get; set; default = -1; }
		public int num_predict { get; set; default = -1; }
		public double repeat_penalty { get; set; default = -1.0; }
		public int num_ctx { get; set; default = -1; }
		
		// String options - default to empty string (no value set)
		public string stop { get; set; default = ""; }

		public Options()
		{
		}

		/**
		 * Creates a clone of this Options object with all properties copied.
		 * 
		 * Uses GObject introspection to iterate through all properties and copy them.
		 * 
		 * @return A new Options instance with all properties copied from this object
		 */
		public Options clone()
		{
			var new_obj = new Options();
			
			foreach (unowned ParamSpec pspec in this.get_class().list_properties()) {
				var value = Value(pspec.value_type);
				this.get_property(pspec.get_name(), ref value);
				new_obj.set_property(pspec.get_name(), value);
			}
			
			return new_obj;
		}

		/**
		 * Checks if any options have valid values set.
		 * 
		 * Returns true if at least one option has a non-default value.
		 * For numeric options, -1 indicates no value set.
		 * For string options, empty string indicates no value set.
		 * 
		 * @return true if options have values, false otherwise
		 */
		public bool has_values()
		{
			return this.seed != -1
				|| this.temperature != -1.0
				|| this.top_p != -1.0
				|| this.top_k != -1
				|| this.num_predict != -1
				|| this.repeat_penalty != -1.0
				|| this.num_ctx != -1
				|| this.stop != "";
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

		public virtual Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			// Group cases by type and check default values
			switch (property_name) {
				// Integer properties - default -1
				case "seed":
				case "top_k":
				case "num_predict":
				case "num_ctx":
					if (value.get_int() == -1) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				// Double properties - default -1.0
				case "temperature":
				case "top_p":
				case "repeat_penalty":
					if (value.get_double() == -1.0) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				// String properties - default empty string
				case "stop":
					if (value.get_string() == "") {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				default:
					return null;
			}
		}

		public virtual bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
}

