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

namespace OLLMchat.Prompt
{
	/**
	 * Base prompt template: load from resource URI or filesystem, fill placeholders.
	 * Subclasses set source and base_dir (e.g. resource:// + /ocvector, or filesystem path).
	 */
	public class Template : Object
	{
		public string source { get; set; default = "resource://"; }
		public string base_dir { get; set; default = ""; }
		public string filename { get; set; default = ""; }

		public string system_message { get; set; default = ""; }
		public string user_template { get; set; default = ""; }

		public Template(string filename)
		{
			this.filename = filename;
		}

		/**
		 * Returns true if the template exists and can be loaded.
		 * For source == "resource://", assumes always exists; otherwise checks filesystem.
		 */
		public bool exists() throws GLib.Error
		{
			if (this.source == "resource://") {
				return true;
			}
			return GLib.File.new_for_uri(
				this.source + GLib.Path.build_filename(this.base_dir, this.filename)).query_exists();
		}

		/**
		 * Loads template. Calls exists() first; throws if not found.
		 * Template should use `---` separator between system and user messages.
		 */
		public virtual void load() throws GLib.Error
		{
			if (!this.exists()) {
				throw new GLib.IOError.NOT_FOUND("Prompt template not found: %s", GLib.Path.build_filename(this.base_dir, this.filename));
			}
			uint8[] data;
			string etag;
			GLib.File.new_for_uri(
					.source + GLib.Path.build_filename(this.base_dir, this.filename)
				).load_contents(null, out data, out etag);
			var parts = ((string) data).split("---", 2);
			if (parts.length != 2) {
				throw new GLib.IOError.FAILED("Prompt template must contain '---' separator between system and user messages");
			}
			this.system_message = parts[0].strip();
			this.user_template = parts[1].strip();
		}

		/**
		 * Fills template placeholders with values.
		 * Varargs key-value pairs: fill("key1", value1, "key2", value2, ...).
		 * Replaces {key1} with value1, etc. Vala passes null at end of varargs.
		 */
		public string fill(...)
		{
			var result = this.user_template;
			var args = va_list();
			while (true) {
				unowned string? key = args.arg<string?>();
				if (key == null) {
					break;
				}
				unowned string? value = args.arg<string?>();
				if (value == null) {
					break;
				}
				result = result.replace("{" + key + "}", value);
			}
			return result;
		}
	}
}
