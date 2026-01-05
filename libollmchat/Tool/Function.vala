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
	 * Concrete class representing a function within a Tool.
	 *
	 * This class is built from a Tool's properties on construction.
	 * It provides name, description, and parameters for serialization.
	 * Used internally by the tool system to generate function schemas
	 * for the LLM API.
	 */
	public class Function : Object, Json.Serializable
	{
		private BaseTool tool;
		
		public Function(BaseTool tool)
		{
			this.tool = tool;
		}
		
		/**
		 * The name of the function (from Tool).
		 */
		public string name
		{
			get { return this.tool.name; }
		}
		
		/**
		 * The description of the function (from Tool).
		 */
		public string description
		{
			get { return this.tool.description; }
		}
		
		/**
		 * The parameters of the function.
		 */
		public ParamObject parameters { get; set; default = new ParamObject(); }
		
		/**
		 * The textual parameter description (from Tool).
		 */
		public string? parameter_description
		{
			get { return this.tool.parameter_description; }
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

		public Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			switch (property_name) {
				case "name":
				case "description":
					return default_serialize_property(property_name, value, pspec);
				
				case "parameters":
				
					var param_node = Json.gobject_serialize(this.parameters);
					param_node.get_object().set_string_member("type", this.parameters.x_type);
					return param_node;
							 
				default:
					return null;
			}
		}
	}
}
