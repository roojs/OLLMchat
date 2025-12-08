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
	 * All properties are read-only getters from the client, with blank setters
	 * for serialization purposes. Default values are -1 for numbers (indicating
	 * no value set) or empty string for strings.
	 */
	public class Options : OllamaBase
	{
		// Numeric options - default to -1 (no value set)
		public int seed { get { return this.client.seed; } set { } }
		public double temperature { get { return this.client.temperature; } set { } }
		public double top_p { get { return this.client.top_p; } set { } }
		public int top_k { get { return this.client.top_k; } set { } }
		public int num_predict { get { return this.client.num_predict; } set { } }
		public double repeat_penalty { get { return this.client.repeat_penalty; } set { } }
		public int num_ctx { get { return this.client.num_ctx; } set { } }
		
		// String options - default to empty string (no value set)
		public string stop { get { return this.client.stop; } set { } }

		public Options(Client client)
		{
			base(client);
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

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			// Group cases by type and check default values
			switch (property_name) {
				case "client":
					return null;
				
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
	}
}

