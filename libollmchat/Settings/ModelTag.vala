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
	 * Represents a model tag with size, context, and input information.
	 *
	 * Format: { "name": "latest", "size": "14GB", "context": "128K", "input": "Text" }
	 */
	public class ModelTag : Object, Json.Serializable
	{
		/**
		 * Tag name (e.g., "latest", "20b", "l12")
		 */
		public string name { get; set; default = ""; }
		
		/**
		 * Model size (e.g., "14GB")
		 */
		public string size { get; set; default = ""; }
		
		/**
		 * Context window size (e.g., "128K")
		 */
		public string context { get; set; default = ""; }
		
		/**
		 * Input types as comma-separated string (e.g., "Text" or "Text, Image")
		 */
		public string input { get; set; default = ""; }
		
		public ModelTag()
		{
		}
		
		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			// Don't serialize - we write the raw JSON content from the API response directly
			return null;
		}
		
		public override bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			 
			
			// Use default deserialization for other properties
			return default_deserialize_property(property_name, out value, pspec, property_node);
		}
		
		/**
		 * Parses the size string to extract the numeric size in GB.
		 * Returns -1 if the size cannot be parsed.
		 *
		 * Handles formats like "14GB", "1.5GB", etc.
		 * If the size is in bytes (suffix "B"), converts to GB.
		 */
		public double parse_size_gb()
		{
			if (this.size == "") {
				return -1;
			}
			
			var cleaned = this.size.strip().up();
			
			// Remove "GB" or "B" suffix
			if (cleaned.has_suffix("GB")) {
				var number_str = cleaned.substring(0, cleaned.length - 2).strip();
				return double.parse(number_str);
			} else if (cleaned.has_suffix("B")) {
				var number_str = cleaned.substring(0, cleaned.length - 1).strip();
				var bytes = double.parse(number_str);
				// Convert bytes to GB (divide by 1e9)
				return bytes / 1e9;
			}
			
			return -1;
		}
		
		/**
		 * Display string for the tag with size and context info.
		 */
		public string display_string {
			owned get {
				var parts = new Gee.ArrayList<string>();
				parts.add(this.name);
				
				if (this.size != "") {
					parts.add(this.size);
				}
				if (this.context != "") {
					parts.add(this.context);
				}
				
				return string.joinv(" • ", parts.to_array());
			}
		}
		
		/**
		 * Display string for dropdown: "7b (25GB - context 12K)" or just "7b" if no size/context.
		 */
		public string dropdown_display {
			owned get {
				if (this.size != "" && this.context != "") {
					return this.name + " (" + this.size + " - context " + this.context + ")";
				}
				return this.name;
			}
		}
		
		/**
		 * Markup-formatted display string for dropdown with name in normal text
		 * and size/context in small grey text.
		 */
		public string dropdown_markup {
			owned get {
				if (this.size == "" && this.context == "" && this.input == "") {
					return GLib.Markup.escape_text(this.name, -1);
				}
				
				var details = "";
				if (this.size != "") {
					details = this.size;
				}
				if (this.context != "") {
					if (details != "") {
						details += " • ";
					}
					details += "context " + this.context;
				}
				if (this.input != "") {
					if (details != "") {
						details += " • ";
					}
					details += this.input;
				}
				
				return GLib.Markup.escape_text(this.name, -1) +
				       " <span size='small' foreground='grey'>" +
				       GLib.Markup.escape_text(details, -1) +
				       "</span>";
			}
		}
	}
}

