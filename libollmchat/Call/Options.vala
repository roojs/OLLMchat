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
	 *
	 * == Example ==
	 *
	 * {{{
	 * var call = new Call.Chat(client, "llama3.2");
	 * call.options = new Call.Options() {
	 *     temperature = 0.7,
	 *     top_p = 0.9,
	 *     num_predict = 100
	 * };
	 *
	 * // Or modify existing options
	 * call.options.temperature = 0.5;
	 * call.options.stop = "\n\n";
	 * }}}
	 */
	public class Options : Object, Json.Serializable
	{
		// Numeric options - default to -1 (no value set)
		[Description(nick = "Seed", blurb = "Random seed for reproducible outputs")]
		public int seed { get; set; default = -1; }
		
		[Description(nick = "Temperature", blurb = "Controls randomness in the output (0.0 = deterministic, higher = more random)")]
		public double temperature { get; set; default = -1.0; }
		
		[Description(nick = "Top P", blurb = "Nucleus sampling: consider tokens with top_p probability mass")]
		public double top_p { get; set; default = -1.0; }
		
		[Description(nick = "Top K", blurb = "Limit the number of highest probability tokens to consider")]
		public int top_k { get; set; default = -1; }
		
		[Description(nick = "Max Tokens", blurb = "Maximum number of tokens to generate")]
		public int num_predict { get; set; default = -1; }
		
		[Description(nick = "Min P", blurb = "Minimum probability threshold for token selection")]
		public double min_p { get; set; default = -1.0; }
		
		[Description(nick = "Context Window", blurb = "Size of the context window in tokens")]
		public int num_ctx { get; set; default = -1; }
		
		// String options - default to empty string (no value set)
		[Description(nick = "Stop Sequences", blurb = "Sequences that will stop generation (separate multiple with commas)")]
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
				var value = this.get_property(pspec);
				new_obj.set_property(pspec, value);
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
				|| this.min_p != -1.0
				|| this.num_ctx != -1
				|| this.stop != "";
		}

		/**
		 * Fills this Options object with values parsed from model parameters string.
		 *
		 * Parses the model's parameters string (format: "temperature 0.7\nnum_ctx 2048")
		 * and sets the corresponding properties using set_property.
		 * Uses switch case grouped by type (int, double, string).
		 *
		 * @param model The model object containing the parameters string
		 */
		public void fill_from_model(OLLMchat.Response.Model model)
		{
			if (model.parameters == null || model.parameters == "") {
				return;
			}

			var lines = model.parameters.split("\n");
			foreach (var line in lines) {
				line = line.strip();
				if (line == "") {
					continue;
				}
				
				// Split on first space to separate parameter name from value
				var parts = line.split(" ", 2);
				if (parts.length < 2) {
					continue;
				}
				
				var param_name = parts[0].strip();
				var param_value = parts[1].strip();
				
				if (param_name == "" || param_value == "") {
					continue;
				}

				// Use switch case on parameter name to set the property
				// Cast to Object to use set_property on Json.Serializable
				switch (param_name) {
					// Integer properties
					case "seed":
					case "top_k":
					case "num_predict":
					case "num_ctx":
						int int_value;
						if (int.try_parse(param_value, out int_value)) {
							var value = Value(typeof(int));
							value.set_int(int_value);
							((GLib.Object)this).set_property(param_name, value);
						}
						break;
					
					// Double properties
					case "temperature":
					case "top_p":
					case "min_p":
						double double_value;
						if (double.try_parse(param_value, out double_value)) {
							var value = Value(typeof(double));
							value.set_double(double_value);
							((GLib.Object)this).set_property(param_name, value);
						}
						break;
					
					// String properties
					case "stop":
						var value = Value(typeof(string));
						value.set_string(param_value);
						((GLib.Object)this).set_property(param_name, value);
						break;
					
					default:
						// Unknown parameter name, skip
						break;
				}
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

		public virtual Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			// Group cases by type and check default values
			// Note: Vala converts underscores to hyphens when calling serialize_property
			switch (property_name) {
				// Integer properties - default -1
				case "seed":
				case "top-k":
				case "num-predict":
				case "num-ctx":
					if (value.get_int() == -1) {
						return null;
					}
					return default_serialize_property(property_name, value, pspec);
				
				// Double properties - default -1.0
				case "temperature":
				case "top-p":
				case "min-p":
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

