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
	 * Represents an available model from the Ollama models cache.
	 * 
	 * NOTE: This class is technically Ollama-specific, but is kept generic
	 * for potential future use with other model providers.
	 * 
	 * The details object from the JSON response is flattened into
	 * details_format and details_family properties.
	 */
	public class AvailableModel : Object, Json.Serializable
	{
		/**
		 * Model name with tag (e.g., "model-name:tag")
		 */
		public string name { get; set; default = ""; }
		
		/**
		 * Last modified timestamp (ISO 8601 format)
		 */
		public string last_modified { get; set; default = ""; }
		
		/**
		 * Model size in bytes
		 */
		public int64 size { get; set; default = 0; }
		
		/**
		 * Model digest (SHA256 hash)
		 */
		public string digest { get; set; default = ""; }
		
		/**
		 * Model format (flattened from details.format)
		 */
		public string details_format { get; set; default = ""; }
		
		/**
		 * Model family (flattened from details.family)
		 */
		public string details_family { get; set; default = ""; }
		
		/**
		 * Formatted display string: "model_name size" (e.g., "llama3:8b 4.7GB" or "tinyllama 637MB").
		 */
		public string display {
			owned get {
				return this.name + " " + this.format_size(this.size);
			}
		}
		
		/**
		 * Details object (used only for deserialization, flattened into details_format and details_family)
		 * This property exists so the JSON deserializer recognizes the "details" key.
		 */
		private Object? details { get; set; default = null; }
		
		/**
		 * Formats size in bytes to GB (if >= 1GB) or MB (if < 1GB), showing 1 decimal place.
		 */
		private string format_size(int64 bytes)
		{
			const int64 GB = 1024 * 1024 * 1024;
			const int64 MB = 1024 * 1024;
			
			if (bytes >= GB) {
				var gb = (double)bytes / GB;
				return "%.1fGB".printf(gb);
			} else {
				var mb = (double)bytes / MB;
				return "%.1fMB".printf(mb);
			}
		}
		
		public AvailableModel()
		{
		}
		
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			// Don't serialize - we write the raw JSON content from the API response directly
			return null;
		}		
		
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			// Use default deserialization for properties other than "details"
			if (property_name != "details") {
				return default_deserialize_property(property_name, out value, pspec, property_node);
			}
			
			// Handle nested "details" object by flattening it
			if (property_node.get_node_type() != Json.NodeType.OBJECT) {
				return false;
			}
			
			var details_obj = property_node.get_object();
			
			// Extract format
			if (details_obj.has_member("format")) {
				this.details_format = details_obj.get_string_member("format");
			}
			
			// Extract family
			if (details_obj.has_member("family")) {
				this.details_family = details_obj.get_string_member("family");
			}
			
			// Return true to indicate we handled this property
			value = Value(pspec.value_type);
			return true;
		}
	}
}

