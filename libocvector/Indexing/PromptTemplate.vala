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

namespace OLLMvector.Indexing
{
	/**
	 * Prompt template class for loading and filling templates.
	 */
	public class PromptTemplate : Object
	{
		/**
		 * Base path for ocvector resources.
		 */
		private const string RESOURCE_BASE_PREFIX = "/ocvector";
		
		public string system_message = "";
		public string user_template = "";
		
		private string resource_path;
		
		/**
		 * Constructor.
		 * 
		 * @param resource_path Relative path from RESOURCE_BASE_PREFIX (e.g., "analysis-prompt.txt")
		 */
		public PromptTemplate(string resource_path)
		{
			this.resource_path = resource_path;
		}
		
		/**
		 * Loads template from resources.
		 * 
		 * Template should use `---` separator between system and user messages.
		 */
		public void load() throws GLib.Error
		{
			var file = GLib.File.new_for_uri("resource://" + GLib.Path.build_filename(
				RESOURCE_BASE_PREFIX,
				this.resource_path
			));
			
			uint8[] data;
			string etag;
			file.load_contents(null, out data, out etag);
			
			var parts = ((string)data).split("---", 2);
			if (parts.length != 2) {
				throw new GLib.IOError.FAILED("Prompt template must contain '---' separator between system and user messages");
			}
			
			this.system_message = parts[0].strip();
			this.user_template = parts[1].strip();
		}
		
		/**
		 * Fills template placeholders with values.
		 * 
		 * Takes varargs of key-value pairs: fill("key1", value1, "key2", value2, ...)
		 * Replaces {key1} with value1, {key2} with value2, etc.
		 * Vala automatically passes null at the end of varargs to signal termination.
		 * 
		 * @param ... Varargs of string key-value pairs
		 * @return Filled user template
		 */
		public string fill(...)
		{
			var result = this.user_template;
			var args = va_list();
			
			// Process key-value pairs (Vala passes null at end automatically)
			while (true) {
				unowned string? key = args.arg<string?>();
				if (key == null) {
					break;
				}
				unowned string? value = args.arg<string?>();
				if (value == null) {
					break;
				}
				
				// Replace {key} with value
				var placeholder = "{" + key + "}";
				result = result.replace(placeholder, value);
			}
			
			return result;
		}
	}
}
