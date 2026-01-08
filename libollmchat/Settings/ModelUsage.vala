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
		[Description(nick = "Connection", blurb = "Connection URL key (references a connection from the connections map)")]
		public string connection { get; set; default = ""; }
		
		/**
		 * Model name to use
		 */
		[Description(nick = "Model", blurb = "Model name to use")]
		public string model { get; set; default = ""; }
		
		/**
		 * Optional runtime options (temperature, top_p, top_k, num_ctx, etc.)
		 */
		[Description(nick = "Options", blurb = "Optional runtime options (temperature, top_p, top_k, num_ctx, etc.)")]
		public OLLMchat.Call.Options options { get; set; default = new OLLMchat.Call.Options(); }
		
		/**
		 * Whether this ModelUsage is valid (connection exists, model is available).
		 * 
		 * Not serialized and not shown in config dialogs.
		 * Set to false by validation methods if the connection is missing or
		 * the model is not available on the server.
		 */
		public bool is_valid = true;
		
		/**
		 * Response.Model object for display names and filling in details later.
		 * Not serialized - runtime only.
		 */
		public Response.Model? model_obj = null;
		
		/**
		 * Verifies that the model specified in this ModelUsage is available on the connection.
		 * 
		 * Creates a temporary client, fetches the list of available models from the server,
		 * and checks if the model name exists in the available models. Updates the `is_valid`
		 * property based on the verification result.
		 * 
		 * Returns false if connection is empty, model is empty, connection is not found,
		 * or if there's an error fetching models. Returns true only if the model is available.
		 * 
		 * @param config The Config2 instance containing the connection configuration
		 * @return true if the model is available, false otherwise
		 */
		public async bool verify_model(Config2 config)
		{
			if (this.connection == "" || this.model == "") {
				this.is_valid = false;
				return false;
			}
			
			var connection_obj = config.connections.get(this.connection);
			if (connection_obj == null) {
				this.is_valid = false;
				return false;
			}
			
			try {
				var client = new OLLMchat.Client(connection_obj);
				yield client.models();
				
				this.is_valid = client.available_models.has_key(this.model);
				return this.is_valid;
			} catch (GLib.Error e) {
				this.is_valid = false;
				return false;
			}
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
			// Skip is_valid field - it's not serialized
			
			return default_serialize_property(property_name, value, pspec);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
		
		/**
		 * Returns the display name for this model (just the model name).
		 * 
		 * @return The model name
		 */
		public string display_name()
		{
			return this.model;
		}
		
		/**
		 * Returns the display name with size in parentheses (e.g., "llama3.1:70b (4.1 GB)").
		 * Uses model_obj if available, otherwise just returns the model name.
		 * 
		 * @return The model name with size, or just the model name if model_obj is null
		 */
		public string display_name_with_size()
		{
			if (this.model_obj != null) {
				return this.model_obj.name_with_size;
			}
			return this.model;
		}
	
	}
}

