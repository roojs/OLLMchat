/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
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

using GLib;

namespace OLLMchat.Settings
{
	/**
	 * Base configuration class for simple tools that only need enabled/disabled.
	 *
	 * This is the base class for all tool configurations. Simple tools like
	 * ReadFile, EditFile, and WebFetch can use this class directly. Complex
	 * tools that need additional configuration should extend this class.
	 *
	 * All properties must be GObject properties with proper metadata for
	 * Phase 2 UI generation via property introspection.
	 *
	 * @since 1.0
	 */
	public class BaseToolConfig : Object, Json.Serializable
	{
		/**
		 * Whether the tool is enabled.
		 */
		[Description(nick = "Enable", blurb = "You can disable this tool here")]
		public bool enabled { get; set; default = true; }

		/**
		 * Default constructor.
		 */
		public BaseToolConfig()
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

