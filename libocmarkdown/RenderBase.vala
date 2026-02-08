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

namespace Markdown
{
	/**
	 * Base abstract class for renderers that use the Parser.
	 * 
	 * Provides parser setup and callback interface without requiring
	 * buffer or mark functionality. Subclasses implement the callback
	 * methods to handle parsed content.
	 */
	public abstract class RenderBase : Object
	{
		public Parser parser { get; private set; }
		
		/**
		 * Creates a new RenderBase instance.
		 */
		protected RenderBase()
		{
			// Create parser instance
			this.parser = new Parser(this);
		}
		
		/**
		 * Main method: adds text to be parsed and rendered.
		 * 
		 * @param text The markdown text to process
		 */
		public virtual void add(string text)
		{
			this.parser.add(text);
		}

		/**
		 * Finalizes the current chunk. Call this before starting a new chunk with add_start
		 * to ensure all pending content is processed.
		 */
		public void flush()
		{
			this.parser.flush();
		}
		
		/**
		 * Starts/initializes the parser for a new block.
		 * 
		 * Resets the parser's internal state. Should be called when beginning a new content block.
		 */
		public void start()
		{
			this.parser.start();
		}
		
		/**
		 * Single entry point for string-based callbacks (type, is_start, 0–3 strings).
		 * Default implementation switches on type and calls the protected virtual methods.
		 */
		public virtual void on_node(FormatType type, bool is_start, string s1 = "", string s2 = "", string s3 = "")
		{
			switch (type) {
				case FormatType.TEXT:
					this.on_text(s1);
					return;
				case FormatType.IMAGE:
					this.on_img(s1, s2);
					return;
				case FormatType.PARAGRAPH:
					this.on_p(is_start);
					return;
				case FormatType.HEADING_1:
					this.on_h(is_start, 1);
					return;
				case FormatType.HEADING_2:
					this.on_h(is_start, 2);
					return;
				case FormatType.HEADING_3:
					this.on_h(is_start, 3);
					return;
				case FormatType.HEADING_4:
					this.on_h(is_start, 4);
					return;
				case FormatType.HEADING_5:
					this.on_h(is_start, 5);
					return;
				case FormatType.HEADING_6:
					this.on_h(is_start, 6);
					return;
				case FormatType.ITALIC:
				case FormatType.ITALIC_ASTERISK:
				case FormatType.ITALIC_UNDERSCORE:
					this.on_em(is_start);
					return;
				case FormatType.BOLD:
				case FormatType.BOLD_ASTERISK:
				case FormatType.BOLD_UNDERSCORE:
					this.on_strong(is_start);
					return;
				case FormatType.BOLD_ITALIC_ASTERISK:
				case FormatType.BOLD_ITALIC_UNDERSCORE:
					if (is_start) {
						this.on_strong(true);
						this.on_em(true);
					} else {
						this.on_em(false);
						this.on_strong(false);
					}
					return;
				case FormatType.CODE:
					this.on_code_span(is_start);
					return;
				case FormatType.STRIKETHROUGH:
					this.on_del(is_start);
					return;
				case FormatType.U:
					this.on_u(is_start);
					return;
				case FormatType.HTML:
					this.on_html(is_start, s1, s2);
					return;
				case FormatType.OTHER:
					this.on_other(is_start, s1);
					return;
				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					this.on_code_block(is_start, s1);
					return;
				case FormatType.TABLE:
					this.on_table(is_start);
					return;
				case FormatType.TABLE_ROW:
					this.on_table_row(is_start);
					return;
				case FormatType.BR:
					this.on_br();
					return;
				case FormatType.CODE_TEXT:
					this.on_code_text(s1);
					return;
				case FormatType.HORIZONTAL_RULE:
					this.on_hr();
					return;
				case FormatType.SOFTBR:
					this.on_softbr();
					return;
				case FormatType.ENTITY:
					this.on_entity(s1);
					return;
				case FormatType.TASK_LIST:
					this.on_task_list(true, false);
					return;
				case FormatType.TASK_LIST_DONE:
					this.on_task_list(true, true);
					return;
				default:
					break;
			}
		}

		/**
		 * Entry point for int/uint-based callbacks (type, is_start, one int).
		 */
		public virtual void on_node_int(FormatType type, bool is_start, int v1 = 0)
		{
			switch (type) {
				case FormatType.LIST_BLOCK:
					this.on_list(is_start);
					return;
				case FormatType.BLOCKQUOTE:
					this.on_quote(is_start, (uint)v1);
					return;
				case FormatType.TABLE_HCELL:
					this.on_table_hcell(is_start, v1);
					return;
				case FormatType.TABLE_CELL:
					this.on_table_cell(is_start, v1);
					return;
				default:
					break;
			}
		}

		/** List block start/end (one pair per list; parser uses do_block(LIST_BLOCK). No per-level signals. */
		protected virtual void on_list(bool is_start) {}

		// Protected virtual callbacks (dispatched from on_node; subclasses override as needed)
		protected virtual void on_p(bool is_start) {}
		protected virtual void on_h(bool is_start, uint level) {}
		protected virtual void on_em(bool is_start) {}
		protected virtual void on_strong(bool is_start) {}
		protected virtual void on_code_span(bool is_start) {}
		protected virtual void on_del(bool is_start) {}
		protected virtual void on_u(bool is_start) {}
		protected virtual void on_text(string text) {}
		protected virtual void on_html(bool is_start, string tag, string attributes) {}
		protected virtual void on_other(bool is_start, string tag_name) {}
		protected virtual void on_code_block(bool is_start, string lang) {}
		protected virtual void on_table(bool is_start) {}
		protected virtual void on_table_row(bool is_start) {}
		protected virtual void on_img(string src, string title) {}
		protected virtual void on_br() {}
		protected virtual void on_code_text(string text) {}
		protected virtual void on_hr() {}
		protected virtual void on_softbr() {}
		protected virtual void on_entity(string text) {}
		protected virtual void on_ul(bool is_start, uint indentation) {}
		protected virtual void on_ol(bool is_start, uint indentation) {}
		protected virtual void on_quote(bool is_start, uint level) {}
		protected virtual void on_table_hcell(bool is_start, int align) {}
		protected virtual void on_table_cell(bool is_start, int align) {}
		protected virtual void on_task_list(bool is_start, bool is_checked) {}

		// Public callbacks not in on_node/on_node_int pipeline (parser/BlockMap call directly)
		/** List item start/end. list_number: 0 = unordered, 1/2/3… = ordered. space_skip: spaces before marker. task_checked: -1 = N/A, 0 = unchecked, 1 = checked. */
		public virtual void on_li(bool is_start, int list_number = 0, uint space_skip = 0, int task_checked = -1) {}
		public virtual void on_a(bool is_start, string href, string title, bool is_reference) {}
		public virtual void on_code(bool is_start, string lang, char fence_char) {}
	}
}

