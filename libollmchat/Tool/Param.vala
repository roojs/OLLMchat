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

namespace OLLMchat.Tool
{
	/**
	 * Abstract base class for parameter definitions.
	 *
	 * Provides shared serialization code for all parameter types.
	 * Child classes should extend this class.
	 */
	public abstract class Param : Object, Json.Serializable
	{
		/**
		 * The name of the parameter.
		 */
		public abstract string name { get; set; }
		
		/**
		 * The JSON schema type of the parameter (e.g., "string", "integer", "boolean", "array", "object").
		 * Stored as x_type to avoid conflict with GObject's reserved "type" property.
		 */
		public abstract string x_type { get; set; }
		
		/**
		 * Whether this parameter is required.
		 */
		public abstract bool required { get; set; }

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
			switch (property_name) {
				case "name":
					// Exclude name when used as a property in JSON Schema (the key IS the name)
					return null;
				
				case "description":
					// Only include description if it's not empty
					if (value.get_string() != "") {
						return default_serialize_property(property_name, value, pspec);
					}
					return null;
				
				case "x_type":
				case "x-type":
					// Don't serialize x_type directly - we'll add "type" manually in the JSON object
					return null;
				
				default:
					return null;
			}
		}
	}
}
