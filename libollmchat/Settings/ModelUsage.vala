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
	 * Represents model usage configuration (connection, model, and optional options).
	 *
	 * This is a reusable class for any feature that needs to specify a connection,
	 * model, and optional options. The connection property references a connection
	 * URL from Config2's connections map.
	 *
	 * @since 1.0
	 */
	public class ModelUsage : Object, Json.Serializable
	{
		/**
		 * Connection URL key (references a connection from the connections map)
		 */
		public string connection { get; set; default = ""; }
		
		/**
		 * Model name to use
		 */
		public string model { get; set; default = ""; }
		
		/**
		 * Optional runtime options (temperature, top_p, top_k, num_ctx, etc.)
		 */
		public OLLMchat.Call.Options options { get; set; default = new OLLMchat.Call.Options(); }

		/**
		 * Default constructor.
		 */
		public ModelUsage()
		{
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

