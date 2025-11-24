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

namespace OLLMchat.Ollama
{
	/**
	 * Represents an array parameter with items definition.
	 * 
	 * Used for parameters with type "array" that define the structure
	 * of array items (which can be ParamSimple, ParamObject, or ParamArray).
	 */
	public class ParamArray : Param
	{
		/**
		 * The name of the parameter.
		 */
		public override string name { get; set; }
		
		/**
		 * The JSON schema type (always "array").
		 */
		public override string x_type { get; set; default = "array"; }
		
		/**
		 * A description of what the parameter does.
		 */
		public string description { get; set; default = ""; }
		
		/**
		 * Whether this parameter is required.
		 */
		public override bool required { get; set; default = false; }
		
		/**
		 * The item definition for array elements.
		 * Can be ParamSimple, ParamObject, or ParamArray.
		 */
		public Param items { get; set; }

		public ParamArray()
		{
			this.x_type = "array";
		}

		public ParamArray.with_name(string name, Param items, string description = "", bool required = false)
		{
			this.name = name;
			this.x_type = "array";
			this.items = items;
			this.description = description;
			this.required = required;
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "items":
					// Serialize nested items definition
					if (this.items != null) {
						var items_node = Json.gobject_serialize(this.items);					 
						items_node.get_object().set_string_member("type", this.items.x_type);
						return items_node;
					}
					return null;
				
				default:
					return base.serialize_property(property_name, value, pspec);
			}
		}
	}
}
