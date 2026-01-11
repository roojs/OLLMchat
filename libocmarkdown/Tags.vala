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

namespace Markdown
{
	/**
	 * Base class for tag handlers.
	 * Default implementations do nothing (ignore behavior).
	 */
	internal class TagIgnored : Object
	{
		protected Writer writer;

		public TagIgnored(Writer writer)
		{
			this.writer = writer;
		}

		public virtual void open(HtmlParser c) {}
		public virtual void close(HtmlParser c) {}
	}

	/**
	 * Generic handler for simple tags that add the same string at opening and closing.
	 */
	internal class TagSimple : TagIgnored
	{
		private string md;

		public TagSimple(Writer writer, string md)
		{
			base(writer);
			this.md = md;
		}

		public override void open(HtmlParser c)
		{
			this.writer.append(this.md);
		}

		public override void close(HtmlParser c)
		{
			this.writer.append(this.md);
		}
	}

	/**
	 * Generic handler for tags that add start on open, and check previous char before adding end on close.
	 */
	internal class TagSimpleWithBreak : TagIgnored
	{
		private string start_str;
		private string end_str;

		public TagSimpleWithBreak(Writer writer, string start_str, string end_str)
		{
			base(writer);
			this.start_str = start_str;
			this.end_str = end_str;
		}

		public override void open(HtmlParser c)
		{
			this.writer.append(this.start_str);
		}

		public override void close(HtmlParser c)
		{
			if (this.writer.prev_prev_ch_in_md != ' ') {
				this.writer.append(this.end_str);
			}
		}
	}

	/**
	 * Handler for anchor tags.
	 */
	internal class TagAnchor : TagIgnored
	{
		private string current_title = "";
		private string current_href = "";

		public TagAnchor(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			if (c.prev_tag == "img") {
				this.writer.append("\n");
			}

			this.current_title = c.attr.has_key("title") ? c.attr.get("title") : "";
			this.writer.append("[");
			this.current_href = c.attr.has_key("href") ? c.attr.get("href") : "";
		}

		public override void close(HtmlParser c)
		{
			// Check if we need to shorten (if previous char is '[')
			if (this.writer.md.len > 0 && this.writer.md.str[this.writer.md.len - 1] == '[') {
				this.writer.shorten(1);
				return;
			}

			this.writer.append("](");
			this.writer.append(this.current_href);

			// If title is set append it
			if (this.current_title != "") {
				this.writer.append(" \"");
				this.writer.append(this.current_title);
				this.writer.append("\"");
				this.current_title = "";
			}

			this.writer.append(")");

			if (c.prev_tag == "img") {
				this.writer.append("\n");
			}
		}
	}

	/**
	 * Handler for underline tags.
	 */
	internal class TagUnderline : TagIgnored
	{
		public TagUnderline(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			this.writer.append("<u>");
		}

		public override void close(HtmlParser c)
		{
			this.writer.append("</u>");
		}
	}

	/**
	 * Handler for break tags.
	 */
	internal class TagBreak : TagIgnored
	{
		public TagBreak(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			if (c.is_in_list) {
				// When it's in a list, it's not in a paragraph
				this.writer.append("  \n");
				this.writer.append_repeat("  ", c.index_li);
			} else if (c.is_in_table) {
				this.writer.append("<br>");
			} else if (this.writer.md.len > 0) {
				this.writer.append("  \n");
			}
		}
	}

	/**
	 * Handler for div tags.
	 */
	internal class TagDiv : TagIgnored
	{
		public TagDiv(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			if (this.writer.prev_ch_in_md != '\n') {
				this.writer.append("\n");
			}

			if (this.writer.prev_prev_ch_in_md != '\n') {
				this.writer.append("\n");
			}
		}
	}

	/**
	 * Handler for list item tags.
	 */
	internal class TagListItem : TagIgnored
	{
		public TagListItem(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			if (c.is_in_table) {
				return;
			}

			if (!c.is_in_ordered_list) {
				this.writer.append("%c ".printf(c.unordered_list));
				return;
			}

			c.index_ol++;
			this.writer.append("%d%c ".printf(c.index_ol, c.ordered_list));
		}

		public override void close(HtmlParser c)
		{
			if (c.is_in_table) {
				return;
			}

			if (this.writer.prev_ch_in_md != '\n') {
				this.writer.append("\n");
			}
		}
	}

	/**
	 * Handler for option tags.
	 */
	internal class TagOption : TagIgnored
	{
		public TagOption(Writer writer)
		{
			base(writer);
		}

		public override void close(HtmlParser c)
		{
			if (this.writer.md.len > 0) {
				this.writer.append("  \n");
			}
		}
	}

	/**
	 * Handler for ordered list tags.
	 */
	internal class TagOrderedList : TagIgnored
	{
		public TagOrderedList(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			if (c.is_in_table) {
				return;
			}

			c.is_in_list = true;
			c.is_in_ordered_list = true;
			c.index_ol = 0;

			c.index_li++;

			c.replace_previous_space_in_line_by_newline();

			this.writer.append("\n");
		}

		public override void close(HtmlParser c)
		{
			if (c.is_in_table) {
				return;
			}

			c.is_in_ordered_list = false;

			if (c.index_li != 0) {
				c.index_li--;
			}

			c.is_in_list = c.index_li != 0;

			this.writer.append("\n");
		}
	}

	/**
	 * Handler for pre tags.
	 */
	internal class TagPre : TagIgnored
	{
		public TagPre(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			c.is_in_pre = true;

			if (this.writer.prev_ch_in_md != '\n') {
				this.writer.append("\n");
			}

			if (this.writer.prev_prev_ch_in_md != '\n') {
				this.writer.append("\n");
			}

			if (c.is_in_list && c.prev_tag != "p") {
				this.writer.shorten(2);
			}

			if (c.is_in_list) {
				this.writer.append("\t\t");
			} else {
				this.writer.append("```");
			}
		}

		public override void close(HtmlParser c)
		{
			c.is_in_pre = false;
			// Code block ends when pre closes
			this.writer.is_in_code_block = false;

			if (c.is_in_list) {
				return;
			}

			this.writer.append("```");
			this.writer.append("\n"); // Don't combine because of blockquote
		}
	}

	/**
	 * Handler for code tags.
	 */
	internal class TagCode : TagIgnored
	{
		public TagCode(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			c.is_in_code = true;

			if (c.is_in_pre) {
				// Code block - set flag
				this.writer.is_in_code_block = true;
				if (c.is_in_list) {
					return;
				}

				var code = c.attr.has_key("class") ? c.attr.get("class") : "";
				if (code != "") {
					if (code.has_prefix("language-")) {
						code = code.substring(9); // remove language-
					}
					this.writer.append(code);
				}
				this.writer.append("\n");
			} else {
				this.writer.append("`");
			}
		}

		public override void close(HtmlParser c)
		{
			c.is_in_code = false;

			if (c.is_in_pre) {
				// Code block continues - only ends when pre closes
				return;
			}

			this.writer.append("`");
		}
	}

	/**
	 * Handler for paragraph tags.
	 */
	internal class TagParagraph : TagIgnored
	{
		public TagParagraph(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			c.is_in_p = true;

			if (c.is_in_list && c.prev_tag == "p") {
				this.writer.append("\n\t");
			} else if (!c.is_in_list) {
				this.writer.append("\n");
			}
		}

		public override void close(HtmlParser c)
		{
			c.is_in_p = false;

			if (this.writer.md.len > 0) {
				this.writer.append("\n"); // Workaround \n restriction for blockquotes
			}

			if (c.index_blockquote != 0) {
				this.writer.append_repeat("> ", c.index_blockquote);
			}
		}
	}

	/**
	 * Handler for unordered list tags.
	 */
	internal class TagUnorderedList : TagIgnored
	{
		public TagUnorderedList(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			if (c.is_in_list || c.is_in_table) {
				return;
			}

			c.is_in_list = true;

			c.index_li++;

			this.writer.append("\n");
		}

		public override void close(HtmlParser c)
		{
			if (c.is_in_table) {
				return;
			}

			if (c.index_li != 0) {
				c.index_li--;
			}

			c.is_in_list = c.index_li != 0;

			if (this.writer.prev_prev_ch_in_md == '\n' && this.writer.prev_ch_in_md == '\n') {
				this.writer.shorten(1);
			} else if (this.writer.prev_ch_in_md != '\n') {
				this.writer.append("\n");
			}
		}
	}

	/**
	 * Handler for title tags.
	 */
	internal class TagTitle : TagIgnored
	{
		public TagTitle(Writer writer)
		{
			base(writer);
		}

		public override void close(HtmlParser c)
		{
			c.turn_line_into_header1();
		}
	}

	/**
	 * Handler for image tags.
	 */
	internal class TagImage : TagIgnored
	{
		public TagImage(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			if (c.prev_tag != "a" && this.writer.prev_ch_in_md != '\n') {
				this.writer.append("\n");
			}

			this.writer.append("![");
			this.writer.append(c.attr.has_key("alt") ? c.attr.get("alt") : "");
			this.writer.append("](");
			this.writer.append(c.attr.has_key("src") ? c.attr.get("src") : "");

			var title = c.attr.has_key("title") ? c.attr.get("title") : "";
			if (title != "") {
				this.writer.append(" \"");
				this.writer.append(title);
				this.writer.append("\"");
			}

			this.writer.append(")");
		}

		public override void close(HtmlParser c)
		{
			if (c.prev_tag == "a") {
				this.writer.append("\n");
			}
		}
	}

	/**
	 * Handler for separator tags.
	 */
	internal class TagSeperator : TagIgnored
	{
		public TagSeperator(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			this.writer.append("\n---\n"); // NOTE: We can make this an option
		}
	}

	/**
	 * Handler for blockquote tags.
	 */
	internal class TagBlockquote : TagIgnored
	{
		public TagBlockquote(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			c.index_blockquote++;
			this.writer.append("\n");
			this.writer.append_repeat("> ", c.index_blockquote);
		}

		public override void close(HtmlParser c)
		{
			c.index_blockquote--;
			// Only shorten if a "> " was added (i.e., a newline was processed in the blockquote)
			if (this.writer.md.len >= 2 &&
				this.writer.md.str.substring((int)(this.writer.md.len - 2)) == "> ") {
				this.writer.shorten(2); // Remove the '> ' only if it exists
			}
		}
	}

}
