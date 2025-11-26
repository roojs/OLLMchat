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

namespace OLLMchat.MarkdownGtk
{
	/**
	 * Renders markdown content to a Gtk.TextBuffer using a state-based renderer.
	 * 
	 * Processes markdown blocks and spans, converting them to Pango markup
	 * and inserting them into the specified TextBuffer range.
	 */
	public class Render : Object
	{
		public Gtk.TextBuffer buffer { get; private set; }
		public Gtk.TextMark start_mark { get; private set; }
		public Gtk.TextMark end_mark { get; private set; }
		public TopState top_state { get; private set; }
		public State current_state { get; internal set; }
		public Parser parser { get; private set; }
		
		// Optional text_view for table support
		private Gtk.TextView? text_view = null;
		
		// Table support (temporary - will be refactored later)
		private Table current_table { get; set; default = new TableEmpty(); }
		private bool in_table = false;
		private bool table_error = false;
		
		/**
		 * Creates a new Render instance.
		 * 
		 * @param buffer The TextBuffer to render into
		 * @param start_mark Start mark for the range
		 */
		public Render(Gtk.TextBuffer buffer, Gtk.TextMark start_mark)
		{
			this.buffer = buffer;
			this.start_mark = start_mark;
			
			// Create end_mark at the same position as start_mark
			Gtk.TextIter iter;
			this.buffer.get_iter_at_mark(out iter, start_mark);
			this.end_mark = this.buffer.create_mark(null, iter, true);
			
			// Create parser instance
			this.parser = new Parser(this);
			
			// Create top_state
			this.top_state = new TopState(this);
			
			// Initialize current_state to top_state.state (never null)
			this.current_state = this.top_state.state;
		}
		
		/**
		 * Sets the optional TextView for table support.
		 * 
		 * @param text_view The TextView to use for table anchors
		 */
		public void set_text_view(Gtk.TextView? text_view)
		{
			this.text_view = text_view;
		}
		
		/**
		 * Main method: adds text to be parsed and rendered.
		 * 
		 * @param text The markdown text to process
		 */
		public void add(string text)
		{
			this.parser.add(text);
		}
		
		/**
		 * Processes a markdown block and updates the TextView range.
		 * 
		 * @param markdown The markdown text to process
		 * @param start_mark Start mark for the range
		 * @param end_mark End mark for the range
		 */
		public void process_block(string markdown, Gtk.TextMark start_mark, Gtk.TextMark end_mark)
		{
			this.start_mark = start_mark;
			this.end_mark = end_mark;
			
			// Clear state
			this.top_state = new TopState(this);
			this.current_state = this.top_state.state;
			this.in_table = false;
			this.table_error = false;
			this.current_table = new TableEmpty();
			
			// Delete old content between marks
			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_iter_at_mark(out start_iter, start_mark);
			this.buffer.get_iter_at_mark(out end_iter, end_mark);
			this.buffer.delete(ref start_iter, ref end_iter);
			
			// Get new start position after deletion
			this.buffer.get_iter_at_mark(out start_iter, start_mark);
			
			// Process markdown
			this.add(markdown);
			
			// Update end mark
			this.buffer.get_end_iter(out end_iter);
			this.buffer.move_mark(end_mark, end_iter);
		}
		
		// Callback methods for parser
		
		/**
		 * Callback for header blocks.
		 * 
		 * @param level Header level (1-6)
		 */
		internal void on_h(uint level)
		{
			string tag = @"h$level";
			string size_attr = "";
			switch (level) {
				case 1:
					size_attr = "size=\"xx-large\" weight=\"bold\"";
					break;
				case 2:
					size_attr = "size=\"x-large\" weight=\"bold\"";
					break;
				case 3:
					size_attr = "size=\"large\" weight=\"bold\"";
					break;
				default:
					size_attr = "weight=\"bold\"";
					break;
			}
			this.current_state.add_state(tag, size_attr);
		}
		
		/**
		 * Callback for unordered list blocks.
		 * 
		 * @param is_tight Whether the list is tight
		 * @param mark The list marker character
		 */
		internal void on_ul(bool is_tight, char mark)
		{
			this.current_state.add_state("ul", "");
		}
		
		/**
		 * Callback for ordered list blocks.
		 * 
		 * @param start The starting number
		 * @param is_tight Whether the list is tight
		 * @param mark_delimiter The delimiter character
		 */
		internal void on_ol(uint start, bool is_tight, char mark_delimiter)
		{
			this.current_state.add_state("ol", "");
		}
		
		/**
		 * Callback for list item blocks.
		 * 
		 * @param is_task Whether this is a task list item
		 * @param task_mark The task marker character
		 * @param task_mark_offset The offset of the task marker
		 */
		internal void on_li(bool is_task, char task_mark, uint task_mark_offset)
		{
			this.current_state.add_state("li", "");
		}
		
		/**
		 * Callback for code blocks.
		 * 
		 * @param lang The language identifier (may be null)
		 * @param fence_char The fence character used
		 */
		internal void on_code(string? lang, char fence_char)
		{
			this.current_state.add_state("code", "");
		}
		
		/**
		 * Callback for paragraph blocks.
		 */
		internal void on_p()
		{
			this.current_state.add_state("p", "");
		}
		
		/**
		 * Callback for blockquote blocks.
		 */
		internal void on_quote()
		{
			this.current_state.add_state("blockquote", "");
		}
		
		/**
		 * Callback for horizontal rule blocks.
		 */
		internal void on_hr()
		{
			this.current_state.add_text("<span size=\"large\">━━━━━━━━━━━━━━━━━━━━━━━━━━━━</span>\n");
		}
		
		/**
		 * Callback for link spans.
		 * 
		 * @param href The link URL
		 * @param title The link title (may be null)
		 * @param is_autolink Whether this is an autolink
		 */
		internal void on_a(string href, string? title, bool is_autolink)
		{
			string escaped_href = GLib.Markup.escape_text(href, -1);
			this.current_state.add_state("a", @"href=\"$escaped_href\"");
		}
		
		/**
		 * Callback for image spans.
		 * 
		 * @param src The image source URL
		 * @param title The image title (may be null)
		 */
		internal void on_img(string src, string? title)
		{
			// Images not fully supported - just add placeholder
			this.current_state.add_text("[IMG:");
		}
		
		/**
		 * Callback for emphasis/italic spans.
		 */
		internal void on_em()
		{
			this.current_state.add_state("i", "");
		}
		
		/**
		 * Callback for strong/bold spans.
		 */
		internal void on_strong()
		{
			this.current_state.add_state("b", "");
		}
		
		/**
		 * Callback for underline spans.
		 */
		internal void on_u()
		{
			this.current_state.add_state("u", "");
		}
		
		/**
		 * Callback for strikethrough spans.
		 */
		internal void on_del()
		{
			this.current_state.add_state("s", "");
		}
		
		/**
		 * Callback for inline code spans.
		 */
		internal void on_code_span()
		{
			this.current_state.add_state("tt", "");
		}
		
		/**
		 * Generic callback for unmapped block/span types.
		 * 
		 * @param tag_name The tag name
		 */
		internal void on_other(string tag_name)
		{
			this.current_state.add_state(tag_name, "");
		}
		
		/**
		 * Callback for text content.
		 * 
		 * @param text The text content
		 */
		internal void on_text(string text)
		{
			string escaped_text = GLib.Markup.escape_text(text, -1);
			this.current_state.add_text(escaped_text);
		}
		
		// Table support (temporary - will be refactored later)
		private class Table
		{
			public virtual bool active { get; set; default = true; }
			public Gtk.Frame? frame = null;
			public Gtk.Grid? grid = null;
			public Gtk.TextChildAnchor? anchor = null;
			public uint col_count = 0;
			public uint current_row = 0;
			public uint current_col = 0;
			public bool in_header = false;
			public bool error = false;
			
			public Table(Render? renderer, uint cols)
			{
				this.col_count = cols;
				
				if (renderer == null) {
					this.active = false;
					return;
				}
				
				try {
					// Create frame and grid
					this.frame = new Gtk.Frame(null) {
						hexpand = true,
						margin_start = 5,
						margin_end = 5,
						margin_top = 5,
						margin_bottom = 5
					};
					this.frame.add_css_class("code-block-box");
					
					this.grid = new Gtk.Grid() {
						column_homogeneous = false,
						row_homogeneous = false,
						column_spacing = 5,
						row_spacing = 5,
						margin_start = 5,
						margin_end = 5,
						margin_top = 5,
						margin_bottom = 5
					};
					
					this.frame.set_child(this.grid);
					
					// Create child anchor
					Gtk.TextIter iter;
					if (renderer.end_mark != null) {
						renderer.buffer.get_iter_at_mark(out iter, renderer.end_mark);
					} else {
						renderer.buffer.get_end_iter(out iter);
					}
					
					this.anchor = renderer.buffer.create_child_anchor(iter);
					
				} catch (Error e) {
					this.error = true;
					this.active = false;
				}
			}
			
			public void insert_table_cell(Render renderer, string content)
			{
				if (!this.active || this.error || this.grid == null) {
					return;
				}
				
				try {
					// Create label for cell content
					var label = new Gtk.Label(null) {
						use_markup = true,
						wrap = true,
						halign = Gtk.Align.START,
						valign = Gtk.Align.START
					};
					
					// Set alignment based on cell type
					if (this.in_header) {
						label.add_css_class("table-header");
					}
					
					label.set_markup(content);
					
					// Attach to grid
					this.grid.attach(label, 
						(int)this.current_col, 
						(int)this.current_row, 
						1, 1);
					
				} catch (Error e) {
					this.error = true;
				}
			}
			
			public void end_table(Render renderer)
			{
				if (!this.active || this.error || this.frame == null || this.anchor == null) {
					renderer.table_error = true;
					return;
				}
				
				try {
					// Insert frame via child anchor
					if (renderer.text_view != null) {
						renderer.text_view.add_child_at_anchor(this.frame, this.anchor);
					}
					
					// Show frame
					this.frame.set_visible(true);
					
				} catch (Error e) {
					renderer.table_error = true;
				}
			}
		}
		
		private class TableEmpty : Table
		{
			public override bool active { get; set; default = false; }
			
			public TableEmpty()
			{
				base(null, 0);
			}
		}
	}
}
