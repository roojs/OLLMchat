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

namespace OLLMchat.Markdown
{
	/**
	 * Simple renderer that converts markdown and HTML tags to Pango markup strings.
	 * 
	 * Extends Render and uses the parser to handle markdown and HTML tags, but instead
	 * of rendering to a buffer, it builds a Pango markup string.
	 * 
	 * Supported markdown tags:
	 * - *text* or _text_ - Italic text (<i>)
	 * - **text** or __text__ - Bold text (<b>)
	 * - ~~text~~ - Strikethrough text (<s>)
	 * - `text` - Code/monospace text (<tt>)
	 * 
	 * Supported HTML tags:
	 * - <b>, <strong> - Bold text
	 * - <i>, <em> - Italic text
	 * - <u> - Underlined text
	 * - <s>, <del> - Strikethrough text
	 * - <code> - Monospace text
	 * - <small> - Small text
	 * - <span> - Generic span (no styling by default)
	 */
	public class PangoRender : RenderBase
	{
		private StringBuilder pango_markup;
		private Gee.ArrayList<string> open_tags;
		
		/**
		 * Creates a new PangoRender instance.
		 */
		public PangoRender()
		{
			base();
			this.pango_markup = new StringBuilder();
			this.open_tags = new Gee.ArrayList<string>();
		}
		
		/**
		 * Closes a tag by removing it from the open tags stack and appending the closing tag.
		 * 
		 * @param tag The tag name to close
		 */
		private void close_tag(string tag)
		{
			if (this.open_tags.size > 0) {
				this.open_tags.remove_at(this.open_tags.size - 1);
				this.pango_markup.append("</" + tag + ">");
			}
		}
		
		/**
		 * Converts HTML text to Pango markup string.
		 * 
		 * @param html_text The HTML text to convert
		 * @return Pango markup string
		 */
		public string toPango(string html_text)
		{
			this.pango_markup = new StringBuilder();
			this.open_tags.clear();
			
			// Use parser to process HTML tags
			this.start();
			this.add(html_text);
			this.flush();
			
			// Close any remaining open tags
			// Map tag names back to the appropriate method calls
			while (this.open_tags.size > 0) {
				var tag = this.open_tags[this.open_tags.size - 1];
				switch (tag) {
					case "i":
						this.on_em(false);
						break;
					case "b":
						this.on_strong(false);
						break;
					case "tt":
						this.on_code_span(false);
						break;
					case "s":
						this.on_del(false);
						break;
					case "span":
						this.on_html(false, "span", "");
						break;
					default:
						// Unknown tag - close it directly
						this.close_tag(tag);
						break;
				}
			}
			
			return this.pango_markup.str;
		}
		
		// Support all markdown formatting tags - convert to Pango markup
		public override void on_em(bool is_start)
		{
			if (!is_start) {
				this.close_tag("i");
				return;
			}
			
			this.pango_markup.append("<i>");
			this.open_tags.add("i");
		}
		
		public override void on_strong(bool is_start)
		{
			if (!is_start) {
				this.close_tag("b");
				return;
			}
			
			this.pango_markup.append("<b>");
			this.open_tags.add("b");
		}
		
		public override void on_code_span(bool is_start)
		{
			if (!is_start) {
				this.close_tag("tt");
				return;
			}
			
			this.pango_markup.append("<tt>");
			this.open_tags.add("tt");
		}
		
		public override void on_del(bool is_start)
		{
			if (!is_start) {
				this.close_tag("s");
				return;
			}
			
			this.pango_markup.append("<s>");
			this.open_tags.add("s");
		}
		
		/**
		 * Handles other unmapped tags.
		 */
		public override void on_other(bool is_start, string tag_name)
		{
			// For unknown tags, we don't add Pango markup
			// So we'll just ignore unknown tags
		}
		
		/**
		 * Handles HTML tags and converts them to Pango markup.
		 */
		public override void on_html(bool is_start, string tag, string attributes)
		{
			if (!is_start) {
				// Closing tag - close the most recently opened tag
				// We need to determine which tag was opened, so we'll use the tag parameter
				var tag_lower = tag.down();
				string? pango_tag = null;
				
				// Map HTML tag to Pango tag
				switch (tag_lower) {
					case "b":
					case "strong":
						pango_tag = "b";
						break;
					case "i":
					case "em":
						pango_tag = "i";
						break;
					case "u":
						pango_tag = "u";
						break;
					case "s":
					case "del":
						pango_tag = "s";
						break;
					case "code":
						pango_tag = "tt";
						break;
					case "small":
						pango_tag = "small";
						break;
					case "span":
						pango_tag = "span";
						break;
					default:
						// Unknown tag - try to close using the tag name as-is
						pango_tag = tag_lower;
						break;
				}
				
				if (pango_tag != null) {
					this.close_tag(pango_tag);
				}
				return;
			}
			
			// Opening tag
			var tag_lower = tag.down();
			string? pango_tag = null;
			
			// Convert HTML tags to Pango markup
			switch (tag_lower) {
				case "b":
				case "strong":
					pango_tag = "b";
					break;
					
				case "i":
				case "em":
					pango_tag = "i";
					break;
					
				case "u":
					pango_tag = "u";
					break;
					
				case "s":
				case "del":
					pango_tag = "s";
					break;
					
				case "code":
					pango_tag = "tt";
					break;
					
				case "small":
					pango_tag = "small";
					break;
					
				case "span":
					// Handle span with attributes (assume attributes are valid Pango markup)
					if (attributes != "") {
						this.pango_markup.append("<span " + attributes + ">");
					} else {
						this.pango_markup.append("<span>");
					}
					this.open_tags.add("span");
					return;
					
				default:
					// Unknown tag - ignore
					return;
			}
			
			if (pango_tag != null) {
				this.pango_markup.append("<" + pango_tag + ">");
				this.open_tags.add(pango_tag);
			}
		}
		
		/**
		 * Handles text content - escape and append to Pango markup.
		 */
		public override void on_text(string text)
		{
			// Escape special Pango markup characters
			var escaped = GLib.Markup.escape_text(text, -1);
			this.pango_markup.append(escaped);
		}
		
		/**
		 * Handles HTML entities (already decoded by parser).
		 */
		public override void on_entity(string text)
		{
			var escaped = GLib.Markup.escape_text(text, -1);
			this.pango_markup.append(escaped);
		}
	}
}

