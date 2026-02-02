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

namespace OLLMchat.Settings
{
	/**
	 * Represents an available model from the Ollama models cache.
	 *
	 * NOTE: This class is technically Ollama-specific, but is kept generic
	 * for potential future use with other model providers.
	 *
	 * Format: { "name": "gemma3", "description": "...", "tags": ["1b", "4b", ...] }
	 */
	public class AvailableModel : Object, Json.Serializable
	{
		/**
		 * Model name (e.g., "gemma3", "qwen3")
		 */
		public string name { get; set; default = ""; }
		
		/**
		 * Model description
		 */
		public string description { get; set; default = ""; }
		
		/**
		 * Array of model tags (can be strings or ModelTag objects)
		 */
		public Gee.ArrayList<string> tags { get; set; default = new Gee.ArrayList<string>(); }
		
		/**
		 * Array of ModelTag objects parsed from tags array
		 */
		public Gee.ArrayList<ModelTag> tag_objects { get; private set; default = new Gee.ArrayList<ModelTag>(); }
		
		/**
		 * Array of unique size display strings with context (e.g., ["7b (25GB - context 12K)", "34b (70GB - context 128K)"]).
		 * Computed when tags are loaded.
		 */
		public Gee.ArrayList<string> unique_sizes { get; private set; default = new Gee.ArrayList<string>(); }
		
		/**
		 * Array of model features (e.g., ["embedding", "vision"])
		 */
		public Gee.ArrayList<string> features { get; set; default = new Gee.ArrayList<string>(); }
		
		/**
		 * Total number of downloads
		 */
		public int64 downloads { get; set; default = 0; }
		
		/**
		 * Formatted display string: "name - description" (e.g., "gemma3 - The current, most capable model...").
		 */
		public string display {
			owned get {
				if (this.description != "") {
					return this.name + " - " + this.description;
				}
				return this.name;
			}
		}
		
		/**
		 * Pango markup string for displaying in the model list.
		 * Includes name, description, sizes, features, and downloads.
		 */
		public string list_markup {
			owned get {
				// Build pango markup: name + line break + small grey description + tags
				var s = GLib.Markup.escape_text(this.name, -1);
				if (this.description != "") {
					s += "\n<span size=\"small\" foreground=\"grey\">%s</span>".printf(GLib.Markup.escape_text(this.description, -1));
				}
				if (this.unique_sizes.size == 0 && this.features.size == 0 && this.downloads == 0) {
					return s;
				}
				string[] tags = {};
				foreach (var size in this.unique_sizes) {
					tags += "<span background=\"#ffffcc\" size=\"small\"> %s </span>".printf(GLib.Markup.escape_text(size, -1));
				}
				var span_fmt = "<span background=\"%s\" foreground=\"#000000\" weight=\"bold\" size=\"small\"> %s </span>";
				foreach (var feature in this.features) {
					switch (feature) {
						case "embedding":
							tags += span_fmt.printf("#e1bee7", "🏭 embedding");
							break;
						case "tools":
							tags += span_fmt.printf("#ffdd99", "🔧 tools");
							break;
						case "vision":
							tags += span_fmt.printf("#c8e6c9", "👁️ vision");
							break;
						case "thinking":
							tags += span_fmt.printf("#fff9c4", "🧠 thinking");
							break;
						case "cloud":
							tags += span_fmt.printf("#e3f2fd", "☁️ cloud");
							break;
						default:
							tags += "<span background=\"#ccffff\" size=\"small\"> %s </span>".printf(GLib.Markup.escape_text(feature, -1));
							break;
					}
				}
				if (this.downloads > 0) {
					string downloads_str = this.downloads >= 1000000 ? "%.1fM pulls".printf((double)this.downloads / 1000000.0)
						: this.downloads >= 1000 ? "%.1fk pulls".printf((double)this.downloads / 1000.0)
						: "%s pulls".printf(this.downloads.to_string());
					tags += "<span size=\"small\" foreground=\"grey\">%s</span>".printf(GLib.Markup.escape_text(downloads_str, -1));
				}
				return s + "\n" + string.joinv(" ", tags);
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
			switch (property_name) {
				case "tags":
					var array = property_node.get_array();
					for (int i = 0; i < array.get_length(); i++) {
						var element = array.get_element(i);
						var tag_obj = Json.gobject_deserialize(typeof(ModelTag), element) as ModelTag;
						this.tag_objects.add(tag_obj);
						// Also store name as string for compatibility
						this.tags.add(tag_obj.name);
					}
					
					// Compute unique sizes from tags
					this.update_unique_sizes();
					
					// Set the value object (required for proper deserialization)
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.tags);
					return true;
					
				case "features":
					var features_array = property_node.get_array();
					for (int i = 0; i < features_array.get_length(); i++) {
						var element = features_array.get_element(i);
						this.features.add(element.get_string());
					}
					
					// Set the value object (required for proper deserialization)
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.features);
					return true;
					
				case "downloads":
					// Default gint64 deserializer does not accept JSON null; handle null and delegate the rest
					if (property_node.get_node_type() == Json.NodeType.NULL) {
						this.downloads = 0;
						value = Value(typeof(int64));
						value.set_int64(0);
						return true;
					}
					return default_deserialize_property(property_name, out value, pspec, property_node);
					
				default:
					// Use default deserialization for other properties
					return default_deserialize_property(property_name, out value, pspec, property_node);
			}
		}
		
		/**
		 * Extracts the size part from a tag (before first dash, or whole tag if no dash).
		 * Examples: "7b-instruct" -> "7b", "34b-chat" -> "34b", "1b" -> "1b"
		 */
		private string extract_size_part(string tag)
		{
			var dash_pos = tag.index_of_char('-');
			if (dash_pos > 0) {
				return tag.substring(0, dash_pos);
			}
			return tag;
		}
		
		/**
		 * Updates the unique_sizes list from the current tags.
		 * Called automatically when tags are deserialized.
		 * Stores just the size part (e.g., "7b", "34b") for display in the model list.
		 * The full format with context is shown in the size dropdown via ModelTag.get_dropdown_display().
		 */
		private void update_unique_sizes()
		{
			this.unique_sizes.clear();
			var seen_sizes = new Gee.HashSet<string>();
			
			// Process ModelTag objects - just extract unique size parts
			foreach (var tag_obj in this.tag_objects) {
				var size_part = this.extract_size_part(tag_obj.name);
				if (!seen_sizes.contains(size_part)) {
					seen_sizes.add(size_part);
					// Store just the size part (e.g., "7b") - context is shown in size dropdown
					this.unique_sizes.add(size_part);
				}
			}
		}
		
		/**
		 * Parses a tag string to extract the numeric size in billions.
		 * Returns -1 if the tag cannot be parsed.
		 *
		 * Note: Returns double to handle decimal values like "0.6b" and "1.7b".
		 * If all tags are integers, this could be simplified to return int.
		 *
		 * Examples:
		 * - "1b" -> 1.0
		 * - "4b" -> 4.0
		 * - "12b" -> 12.0
		 * - "27b" -> 27.0
		 * - "235b" -> 235.0
		 * - "0.6b" -> 0.6
		 * - "1.7b" -> 1.7
		 * - "1b-it-qat" -> 1.0 (extracts number before 'b')
		 * - "1b-it-q4_K_M" -> 1.0 (extracts number before 'b')
		 * - "12b-it-qat" -> 12.0 (extracts number before 'b')
		 */
		public double parse_tag_size(string tag)
		{
			// Extract the size part before any dashes or other suffixes
			var cleaned = tag.strip();
			
			// Find the position of 'b' or 'B' (case insensitive)
			int b_pos = -1;
			for (int i = 0; i < cleaned.length; i++) {
				if (cleaned[i] == 'b' || cleaned[i] == 'B') {
					b_pos = i;
					break;
				}
			}
			
			if (b_pos <= 0) {
				return -1; // No 'b' found or it's at the start
			}
			
			// Extract the number part before 'b'
			var number_str = cleaned.substring(0, b_pos);
			
			// Check if string is empty or contains only whitespace
			if (number_str.strip() == "") {
				return -1;
			}
			
			// Try to parse as double
			double result = double.parse(number_str);
			
			// double.parse() returns 0.0 on parse failure, so we need to check
			// if the string actually represents zero
			if (result == 0.0) {
				// Check if the string is actually "0" or starts with "0."
				var stripped = number_str.strip();
				if (stripped != "0" && !stripped.has_prefix("0.") && stripped != "0.0") {
					return -1; // Parse failure
				}
			}
			
			return result;
		}
		
		/**
		 * Finds the largest tag that is less than the specified size (in billions).
		 * Returns null if no such tag exists.
		 *
		 * Works with both simple tags (e.g., "4b") and tags with suffixes
		 * (e.g., "1b-it-qat", "1b-it-q4_K_M") by parsing the numeric size
		 * from each tag before comparison.
		 */
		public string? find_largest_tag_below(double max_size_b)
		{
			string? best_tag = null;
			double best_size = -1;
			
			foreach (var tag in this.tags) {
				var size = this.parse_tag_size(tag);
				if (size >= 0 && size < max_size_b && size > best_size) {
					best_size = size;
					best_tag = tag;
				}
			}
			
			return best_tag;
		}
	}
}

