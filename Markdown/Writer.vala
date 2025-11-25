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

using Gee;

namespace Markdown
{
	/**
	 * Handles markdown output writing.
	 */
	public class Writer : Object
	{
		public StringBuilder md;
		public int chars_in_curr_line = 0;
		public char prev_ch_in_md = 0;
		public char prev_prev_ch_in_md = 0;
		public Gee.HashMap<string, string> html_symbol_conversions;
		public int table_start = 0;
		public StringBuilder table_line = new StringBuilder();

		public Writer()
		{
			this.md = new StringBuilder();
			this.html_symbol_conversions = new Gee.HashMap<string, string>();
			this.initialize_html_symbol_conversions();
		}

	
		/**
		 * Append string to markdown.
		 */
		public void append(string str)
		{
			this.md.append(str);

			if (str.length == 1) {
				if (str == "\n") {
					this.chars_in_curr_line = 0;
				} else {
					this.chars_in_curr_line++;
				}
				return;
			}

			if (!str.contains("\n")) {
				this.chars_in_curr_line += str.length;
				return ;
			}

			unowned uint8[] data = str.data;
			for (int i = 0; i < data.length; i++) {
				char ch = (char)data[i];
				if (ch == '\n') {
					this.chars_in_curr_line = 0;
				} else {
					this.chars_in_curr_line++;
				}
			}

			return ;
		}


		/**
		 * Repeat string amount times.
		 */
		public void append_repeat(string str, int amount)
		{
			for (var i = 0; i < amount; ++i)
			{
				this.append(str);
			}
		}
 
 

		/**
		 * Update previous character tracking.
		 */
		public Writer update_prev_ch()
		{
			
			
			if (this.md.len > 0) {
				this.prev_ch_in_md = this.md.str[this.md.len - 1];

				if (this.md.len > 1) {
					this.prev_prev_ch_in_md = this.md.str[this.md.len - 2];
				}
			}

			return this;
		}

		/**
		 * Remove characters from end of markdown.
		 */
		public Writer shorten(int chars)
		{
			if (chars > this.md.len) {
				chars = (int)this.md.len;
			}

			var new_str = this.md.str.substring(0, (int)(this.md.len - chars));
			this.md = new StringBuilder();
			this.md.append(new_str);

			if (chars > this.chars_in_curr_line) {
				this.chars_in_curr_line = 0;
			} else {
				this.chars_in_curr_line = this.chars_in_curr_line - chars;
			}

			return this.update_prev_ch();
		}

		/**
		 * Reset writer state.
		 */
		public void reset()
		{
			this.md = new StringBuilder();
			this.prev_ch_in_md = 0;
			this.prev_prev_ch_in_md = 0;
			this.chars_in_curr_line = 0;
			this.table_start = 0;
			this.table_line = new StringBuilder();
		}

		/**
		 * Get the markdown string.
		 */
		public string to_string()
		{
			return this.md.str;
		}

		/**
		 * Post-process markdown to clean it up.
		 */
		public void clean_up_markdown()
		{
			var tidied = this.tidy_all_lines(this.to_string());
			var buffer = new StringBuilder();

			// Replace HTML symbols during the initial pass
			for (size_t i = 0; i < tidied.length;) {
				bool replaced = false;

				foreach (var entry in this.html_symbol_conversions.entries) {
					if (i + entry.key.length <= tidied.length &&
						tidied.substring((int)i, (int)entry.key.length) == entry.key) {
						buffer.append(entry.value);
						i += entry.key.length;
						replaced = true;
						break;
					}
				}

				if (!replaced) {
					buffer.append_c(tidied[(int)i]);
					i++;
				}
			}

			// Optimized replacement sequence
			this.replace_all(buffer, " , ", ", ");
			this.replace_all(buffer, "\n.\n", ".\n");
			this.replace_all(buffer, "\n↵\n", " ↵\n");
			this.replace_all(buffer, "\n*\n", "\n");
			this.replace_all(buffer, "\n. ", ".\n");
			this.replace_all(buffer, "\t\t  ", "\t\t");
			 
			this.reset();
			this.append(buffer.str);
		}

		/**
		 * Clean up all lines.
		 */
		private string tidy_all_lines(string str)
		{
			var res = new StringBuilder();

			uint8 amount_newlines = 0;
			bool in_code_block = false;

			foreach (var line in str.split("\n")) {
				if (line.has_prefix("```") || line.has_prefix("~~~")) {
					in_code_block = !in_code_block;
				}
				if (in_code_block) {
					res.append(line);
					res.append_c('\n');
					continue;
				}

				if (line.strip() == "") {
					if (amount_newlines < 2 && res.len > 0) {
						res.append_c('\n');
						amount_newlines++;
					}
				} else {
					amount_newlines = 0;
					res.append(line.strip());
					res.append_c('\n');
				}
			}

			return res.str;
		}


		
		/**
		 * Replace last space with newline.
		 */
		public bool replace_previous_space_in_line_by_newline()
		{
			var offset = this.md.len - 1;

			if (this.md.len == 0) {
				return true;
			}

			do {
				if (this.md.str[(int)offset] == '\n') {
					return false;
				}

				if (this.md.str[(int)offset] == ' ') {
					var new_str = this.md.str;
					this.md = new StringBuilder();
					this.md.append(new_str.substring(0, (int)offset));
					this.md.append_c('\n');
					this.md.append(new_str.substring((int)offset + 1));
					this.chars_in_curr_line = (int)this.md.len - (int)offset;
					return true;
				}

				if (offset == 0) {
					break;
				}
				offset--;
			} while (offset > 0);

			return false;
		}
 
		/**
		 * Replace all occurrences of needle with replacement in a StringBuilder buffer.
		 */
		private void replace_all(StringBuilder buffer, string needle, string replacement)
		{
			var result = buffer.str;
			var pos = result.index_of(needle);
			while (pos != -1) {
				result = result.splice(pos, pos + needle.length, replacement);
				pos = result.index_of(needle, pos + replacement.length);
			}
			buffer.erase(0, -1);
			buffer.append(result);
		}

		/**
		 * Initialize HTML symbol conversions map.
		 */
		private void initialize_html_symbol_conversions()
		{
			// Common HTML entities
			this.html_symbol_conversions.set("&amp;", "&");
			this.html_symbol_conversions.set("&lt;", "<");
			this.html_symbol_conversions.set("&gt;", ">");
			this.html_symbol_conversions.set("&quot;", "\"");
			this.html_symbol_conversions.set("&apos;", "'");
			this.html_symbol_conversions.set("&nbsp;", " ");
			this.html_symbol_conversions.set("&copy;", "©");
			this.html_symbol_conversions.set("&reg;", "®");
			this.html_symbol_conversions.set("&trade;", "™");
			this.html_symbol_conversions.set("&mdash;", "—");
			this.html_symbol_conversions.set("&ndash;", "–");
			this.html_symbol_conversions.set("&hellip;", "…");
		}
	}
}

