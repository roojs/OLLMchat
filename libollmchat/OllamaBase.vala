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

namespace OLLMchat
{
	public errordomain OllamaError {
		INVALID_ARGUMENT,
		FAILED
	}

	/**
	 * Base class for Ollama API objects that need JSON serialization.
	 *
	 * Provides common functionality for serializing and deserializing objects
	 * to/from JSON. Used as a base for API calls and responses. Automatically
	 * excludes the client property from serialization (it's an internal reference).
	 */
	public class OllamaBase : Object, Json.Serializable
	{
		public Settings.Connection? connection { get; protected set; }
		public string chat_content { get; set; default = ""; }

		protected OllamaBase(Settings.Connection? connection = null)
		{
			this.connection = connection;
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
			// Block connection from serialization - it's an internal reference, not API data
			if (property_name == "connection") {
				return null;
			}
			return default_serialize_property(property_name, value, pspec);
		}

		public virtual bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
	}
}

