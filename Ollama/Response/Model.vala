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
	 * Represents model information from the Ollama server.
	 * 
	 * Contains model metadata including name, size, capabilities, context length,
	 * and other details. Used in model listing and model information responses.
	 */
	public class Model : BaseResponse
	{
		public string name { get; set; default = ""; }
		public string modified_at { get; set; default = ""; }
		public int64 size { get; set; default = 0; }
		public string digest { get; set; default = ""; }
		public Gee.ArrayList<string> capabilities { get;  set; default = new Gee.ArrayList<string>(); }

		public int64 size_vram { get; set; default = 0; }
		public int64 total_duration { get; set; default = 0; }
		public int64 load_duration { get; set; default = 0; }
		public int prompt_eval_count { get; set; default = 0; }
		public int64 prompt_eval_duration { get; set; default = 0; }
		public int eval_count { get; set; default = 0; }
		public int64 eval_duration { get; set; default = 0; }
		public string? model { get; set; } 
		public string? expires_at { get; set; }
		public int context_length { get; set; default = 0; }

		/**
		 * Returns whether the model supports thinking output
		 */
		public bool is_thinking {
			get {
				GLib.debug("is_thinking: %s %s", this.name, 
					this.capabilities.contains("thinking") ? "1" : "0");
				return this.capabilities.contains("thinking");
			}
			private set { }
		}

		/**
		 * Returns whether the model supports tool/function calling
		 */
		public bool can_call {
			get {
				GLib.debug("can_call: %s %s", this.name, 
					this.capabilities.contains("tools") ? "1" : "0");
				return this.capabilities.contains("tools");
			}
			private set { }
		}

		/**
		 * Returns model name with size in parentheses (e.g., "llama3.1:70b (4.1 GB)")
		 */
		public string name_with_size {
			owned get {
				if (this.size == 0) {
					return this.name;
				}
				double size_gb_val = (double)this.size / (1024.0 * 1024.0 * 1024.0);
				string size_str;
				if (size_gb_val >= 1.0) {
					size_str = "%.1f GB".printf(size_gb_val);
				} else {
					size_str = "<1GB";
				}
				return "%s (%s)".printf(this.name, size_str);
			}
		}

		public Model(Client? client = null)
		{
			base(client);
		}

		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			// Exclude computed properties from deserialization
			switch (property_name) {
				case "size_gb":
				case "is_thinking":
				case "can_call":
				case "name_with_size":
					// These are computed properties, skip deserialization
					value = Value(pspec.value_type);
					return true;
				case "capabilities":
					// Handle capabilities as string array
					var capabilities = new Gee.ArrayList<string>();
					var array = property_node.get_array();
					for (int i = 0; i < array.get_length(); i++) {
						var element = array.get_element(i);
						capabilities.add(element.get_string());
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(capabilities);
					return true;
				default:
					// Let default handler process other properties
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
		
		/**
		 * Updates this model's properties from a show API response.
		 * Only updates fields that come from the show API endpoint:
		 * - modified_at
		 * - capabilities
		 * - context_length (if present in show response)
		 * 
		 * Does NOT update fields from models() API (name, size, digest) or
		 * runtime fields from ps() API (size_vram, durations, counts).
		 * 
		 * @param source The model from show API response to copy properties from
		 */
		public void updateFrom(Model source)
		{
			this.freeze_notify();
			// Only update fields that come from show API
			this.modified_at = source.modified_at;
			
			// Freeze notifications to batch property changes
 			
			// Update capabilities by clearing and adding, rather than replacing
			this.capabilities.clear();
			foreach (var cap in source.capabilities) {
				this.capabilities.add(cap);
			}
			// Notify computed properties that depend on capabilities
			//this.notify_property("capabilities");

			this.notify_property("is-thinking");
			this.notify_property("can-call");
			
			// Update context_length if present in show response
			if (source.context_length > 0) {
				this.context_length = source.context_length;
			}
			this.thaw_notify();
			// Thaw notifications - all property change signals will be emitted now
 		}
		
	}

}