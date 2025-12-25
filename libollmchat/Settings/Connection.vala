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
	 * Represents a single server connection configuration.
	 * 
	 * @since 1.0
	 */
	public class Connection : Object, Json.Serializable
	{
		/**
		 * Connection alias/name (e.g., "Local Ollama", "OpenAI", "Remote Server")
		 */
		public string name { get; set; default = ""; }
		
		/**
		 * Server URL (e.g., http:\/\/127.0.0.1:11434\/api)
		 */
		public string url { get; set; default = ""; }
		
		/**
		 * Optional API key for authentication
		 */
		public string api_key { get; set; default = ""; }
		
		/**
		 * Whether this is the default connection
		 */
		public bool default { get; set; default = false; }
		
		/**
		 * List of model names to hide from the UI
		 */
		public Gee.ArrayList<string> hidden_models { get; set; default = new Gee.ArrayList<string>(); }

		/**
		 * Default constructor.
		 */
		public Connection()
		{
		}

		/**
		 * Creates a clone of this Connection object with all properties copied.
		 * 
		 * @return A new Connection instance with all properties copied from this object
		 */
		public Connection clone()
		{
			var new_obj = new Connection();
			
			foreach (unowned ParamSpec pspec in this.get_class().list_properties()) {
				var value = this.get_property(pspec);
				new_obj.set_property(pspec, value);
			}
			
			return new_obj;
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

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
}

