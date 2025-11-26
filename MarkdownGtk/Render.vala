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
	// Static callback wrappers for md4c parser
	// These are internal C callbacks and should not be exposed in GIR
	internal static int md4c_enter_block(MD4C.BlockType type, void* detail, void* userdata)
	{
		var render = (Render)userdata;
		return render.on_enter_block(type, detail);
	}
	
	internal static int md4c_leave_block(MD4C.BlockType type, void* detail, void* userdata)
	{
		var render = (Render)userdata;
		return render.on_leave_block(type, detail);
	}
	
	internal static int md4c_enter_span(MD4C.SpanType type, void* detail, void* userdata)
	{
		var render = (Render)userdata;
		return render.on_enter_span(type, detail);
	}
	
	internal static int md4c_leave_span(MD4C.SpanType type, void* detail, void* userdata)
	{
		var render = (Render)userdata;
		return render.on_leave_span(type, detail);
	}
	
	[CCode (cname = "oll_mchat_markdown_gtk_md4c_text")]
	internal static int md4c_text(MD4C.TextType type, string text, uint size, void* userdata)
	{
		var render = (Render)userdata;
		return render.on_text(type, text, size);
	}
	
	/**
	 * Renders markdown content to a Gtk.TextBuffer using md4c parser.
	 * 
	 * Processes markdown blocks and spans, converting them to Pango markup
	 * and inserting them into the specified TextBuffer range.
	 */
	public class Render : Object
	{
		private Gtk.TextView text_view;
		private Gtk.TextBuffer buffer { get { return this.text_view.buffer; } set {} }
		private Gtk.TextMark start_mark;
		private Gtk.TextMark end_mark;
		private string markdown_text = "";
		
		// State tracking
		private Gee.ArrayList<string> span_stack { get; set; default = new Gee.ArrayList<string>(); }
		private Gee.ArrayList<BlockState> block_stack { get; set; default = new Gee.ArrayList<BlockState>(); }
		private Table current_table { get; set; default = new TableEmpty(); }
		private bool in_code_block = false;
		private bool in_table = false;
		private bool table_error = false;
		
		// Text accumulation
		private StringBuilder current_text;
		
		// md4c parser
		private MD4C.Parser parser;
		
		private class BlockState
		{
			public MD4C.BlockType type;
			public int level;
			public bool is_tight;
			
			public BlockState(MD4C.BlockType t, int l, bool tight = false)
			{
				this.type = t;
				this.level = l;
				this.is_tight = tight;
			}
		}
		
		/**
		 * Creates a new Render instance.
		 * 
		 * @param buffer The TextBuffer to render into
		 */
		public Render(Gtk.TextView text_view)
		{
			this.text_view = text_view;
			
			// Initialize parser
			this.current_text = new StringBuilder();
			this.parser = MD4C.Parser();
			this.parser.abi_version = 0;
			this.parser.flags = MD4C.FLAG_TABLES | 
			                    MD4C.FLAG_STRIKETHROUGH | 
			                    MD4C.FLAG_UNDERLINE | 
			                    MD4C.FLAG_TASKLISTS;
			this.parser.enter_block = md4c_enter_block;
			this.parser.leave_block = md4c_leave_block;
			this.parser.enter_span = md4c_enter_span;
			this.parser.leave_span = md4c_leave_span;
			this.parser.text = md4c_text;
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
			this.markdown_text = markdown;
			this.start_mark = start_mark;
			this.end_mark = end_mark;
			
			// Clear state
			this.span_stack.clear();
			this.block_stack.clear();
			this.current_text = new StringBuilder();
			this.in_code_block = false;
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
			
			// Parse markdown
			int result = MD4C.parse(markdown, markdown.length, ref this.parser, this);
			
			// If table parsing failed, show unformatted text
			if (this.table_error || (this.current_table.active && this.current_table.error)) {
				// Insert raw markdown as unformatted text
				this.buffer.get_iter_at_mark(out start_iter, start_mark);
				this.buffer.insert(ref start_iter, GLib.Markup.escape_text(markdown, -1), -1);
			} else {
				// Flush any remaining text
				this.flush_text();
			}
			
			// Update end mark
			this.buffer.get_end_iter(out end_iter);
			this.buffer.move_mark(end_mark, end_iter);
		}
		
		internal int on_enter_block(MD4C.BlockType type, void* detail)
		{
			try {
				switch (type) {
					case MD4C.BlockType.P:
						this.block_stack.add(new BlockState(type, 0));
						break;
						
					case MD4C.BlockType.H:
						if (detail != null) {
							var h_detail = (MD4C.BlockHDetail*)detail;
							this.block_stack.add(new BlockState(type, (int)h_detail->level));
						} else {
							this.block_stack.add(new BlockState(type, 1));
						}
						break;
						
					case MD4C.BlockType.UL:
					case MD4C.BlockType.OL:
						if (detail != null) {
						
							bool is_tight = false;
							if (type == MD4C.BlockType.UL) {
								is_tight = ((MD4C.BlockULDetail*)detail)->is_tight != 0;
							} else {
								is_tight = ((MD4C.BlockOLDetail*)detail)->is_tight != 0;
							}
							this.block_stack.add(new BlockState(type, this.block_stack.size, is_tight));
						} else {
							this.block_stack.add(new BlockState(type, this.block_stack.size));
						}
						break;
						
					case MD4C.BlockType.LI:
						// List item - add indent
						if (!this.in_table) {
							var str = "";
							for(var i=0; i<this.block_stack.size - 1; i++) {
								str += "  ";
							}
							this.current_text.append(str);
						}
						break;
						
					case MD4C.BlockType.QUOTE:
						this.block_stack.add(new BlockState(type, this.block_stack.size));
						break;
						
					case MD4C.BlockType.CODE:
						this.in_code_block = true;
						if (detail != null) {
							var code_detail = (MD4C.BlockCodeDetail*)detail;
							// Language info available but not used for now
						}
						break;
						
					case MD4C.BlockType.HR:
						this.flush_text();
						this.insert_markup("<span size=\"large\">━━━━━━━━━━━━━━━━━━━━━━━━━━━━</span>\n");
						break;
						
					case MD4C.BlockType.TABLE:
						this.in_table = true;
						this.table_error = false;
						if (detail != null) {
							var table_detail = (MD4C.BlockTableDetail*)detail;
							this.current_table = new Table(this, table_detail->col_count);
							if (!this.current_table.active) {
								this.table_error = true;
							}
						} else {
							this.table_error = true;
						}
						break;
						
					case MD4C.BlockType.THEAD:
						if (this.current_table.active) {
							this.current_table.in_header = true;
							this.current_table.current_row = 0;
						}
						break;
						
					case MD4C.BlockType.TBODY:
						if (this.current_table.active) {
							this.current_table.in_header = false;
						}
						break;
						
					case MD4C.BlockType.TR:
						if (this.current_table.active) {
							this.current_table.current_col = 0;
						}
						break;
						
					case MD4C.BlockType.TH:
					case MD4C.BlockType.TD:
						// Cell content will be collected in text callbacks
						break;
					default:
						break;
				}
			} catch (Error e) {
				this.table_error = true;
				return 1; // Error
			}
			return 0; // Success
		}
		
		internal int on_leave_block(MD4C.BlockType type, void* detail)
		{
			try {
				switch (type) {
					case MD4C.BlockType.P:
						this.flush_text();
						this.insert_markup("\n");
						if (this.block_stack.size > 0 && this.block_stack[this.block_stack.size - 1].type == type) {
							this.block_stack.remove_at(this.block_stack.size - 1);
						}
						break;
						
					case MD4C.BlockType.H:
						this.flush_text();
						this.insert_markup("\n");
						if (this.block_stack.size > 0 && this.block_stack[this.block_stack.size - 1].type == type) {
							this.block_stack.remove_at(this.block_stack.size - 1);
						}
						break;
						
					case MD4C.BlockType.UL:
					case MD4C.BlockType.OL:
						this.flush_text();
						if (!this.in_table) {
							this.insert_markup("\n");
						}
						if (this.block_stack.size > 0 && this.block_stack[this.block_stack.size - 1].type == type) {
							this.block_stack.remove_at(this.block_stack.size - 1);
						}
						break;
						
					case MD4C.BlockType.LI:
						this.flush_text();
						if (!this.in_table) {
							this.insert_markup("\n");
						}
						break;
						
					case MD4C.BlockType.QUOTE:
						this.flush_text();
						this.insert_markup("\n");
						if (this.block_stack.size > 0 && this.block_stack[this.block_stack.size - 1].type == type) {
							this.block_stack.remove_at(this.block_stack.size - 1);
						}
						break;
						
					case MD4C.BlockType.CODE:
						this.flush_text();
						this.in_code_block = false;
						this.insert_markup("\n");
						break;
						
					case MD4C.BlockType.TABLE:
						if (this.current_table.active) {
							this.current_table.end_table(this);
						}
						this.in_table = false;
						break;
						
					case MD4C.BlockType.TH:
					case MD4C.BlockType.TD:
						// Flush cell content
						this.flush_text();
						if (this.current_table.active) {
							this.current_table.current_col++;
							if (this.current_table.current_col >= this.current_table.col_count) {
								this.current_table.current_col = 0;
								this.current_table.current_row++;
							}
						}
						break;
						
					case MD4C.BlockType.TR:
						// Row complete
						break;
					default:
						break;
				}
			} catch (Error e) {
				this.table_error = true;
				return 1; // Error
			}
			return 0; // Success
		}
		
		internal int on_enter_span(MD4C.SpanType type, void* detail)
		{
			try {
				switch (type) {
					case MD4C.SpanType.EM:
						this.span_stack.add("<i>");
						break;
						
					case MD4C.SpanType.STRONG:
						this.span_stack.add("<b>");
						break;
						
					case MD4C.SpanType.U:
						this.span_stack.add("<u>");
						break;
						
					case MD4C.SpanType.DEL:
						this.span_stack.add("<s>");
						break;
						
					case MD4C.SpanType.CODE:
						this.span_stack.add("<tt>");
						break;
						
					case MD4C.SpanType.A:
						if (detail != null) {
							var a_detail = (MD4C.SpanADetail*)detail;
							string href = "";
							if (a_detail->href.size > 0) {
								// Extract href from markdown text
								unowned string href_ptr = a_detail->href.text;
								if (href_ptr != null && a_detail->href.size > 0) {
									href = (string)href_ptr.substring(0, (int)a_detail->href.size);
								}
							}
							string escaped_href = GLib.Markup.escape_text(href, -1);
							this.span_stack.add("<a href=\"" + escaped_href + "\">");
						} else {
							this.span_stack.add("<a>");
						}
						break;
						
					case MD4C.SpanType.IMG:
						// Images not fully supported - just add placeholder
						this.span_stack.add("[IMG:");
						break;
					default:
						break;
				}
			} catch (Error e) {
				return 1; // Error
			}
			return 0; // Success
		}
		
		internal int on_leave_span(MD4C.SpanType type, void* detail)
		{
			try {
				switch (type) {
					case MD4C.SpanType.EM:
						if (this.span_stack.size > 0 && this.span_stack[this.span_stack.size - 1] == "<i>") {
							this.span_stack.remove_at(this.span_stack.size - 1);
							this.current_text.append("</i>");
						}
						break;
						
					case MD4C.SpanType.STRONG:
						if (this.span_stack.size > 0 && this.span_stack[this.span_stack.size - 1] == "<b>") {
							this.span_stack.remove_at(this.span_stack.size - 1);
							this.current_text.append("</b>");
						}
						break;
						
					case MD4C.SpanType.U:
						if (this.span_stack.size > 0 && this.span_stack[this.span_stack.size - 1] == "<u>") {
							this.span_stack.remove_at(this.span_stack.size - 1);
							this.current_text.append("</u>");
						}
						break;
						
					case MD4C.SpanType.DEL:
						if (this.span_stack.size > 0 && this.span_stack[this.span_stack.size - 1] == "<s>") {
							this.span_stack.remove_at(this.span_stack.size - 1);
							this.current_text.append("</s>");
						}
						break;
						
					case MD4C.SpanType.CODE:
						if (this.span_stack.size > 0 && this.span_stack[this.span_stack.size - 1] == "<tt>") {
							this.span_stack.remove_at(this.span_stack.size - 1);
							this.current_text.append("</tt>");
						}
						break;
						
					case MD4C.SpanType.A:
						if (this.span_stack.size > 0 && this.span_stack[this.span_stack.size - 1].has_prefix("<a")) {
							this.span_stack.remove_at(this.span_stack.size - 1);
							this.current_text.append("</a>");
						}
						break;
						
					case MD4C.SpanType.IMG:
						if (this.span_stack.size > 0 && this.span_stack[this.span_stack.size - 1] == "[IMG:") {
							this.span_stack.remove_at(this.span_stack.size - 1);
							this.current_text.append("]");
						}
						break;
					default:
						break;
				}
			} catch (Error e) {
				return 1; // Error
			}
			return 0; // Success
		}
		
		internal int on_text(MD4C.TextType type, string text, uint size)
		{
			try {
				string text_str = text.substring(0, (int)size);
				
				switch (type) {
					case MD4C.TextType.NORMAL:
						if (this.in_code_block) {
							// Code block - use <tt> tags
							this.current_text.append("<tt>");
							this.current_text.append(GLib.Markup.escape_text(text_str, -1));
							this.current_text.append("</tt>");
						} else {
							// Apply current span stack
							foreach (string span in this.span_stack) {
								this.current_text.append(span);
							}
							this.current_text.append(GLib.Markup.escape_text(text_str, -1));
							// Close spans in reverse order
							for (int i = this.span_stack.size - 1; i >= 0; i--) {
								string span = this.span_stack[i];
								if (span == "<i>") {
									this.current_text.append("</i>");
								} else if (span == "<b>") {
									this.current_text.append("</b>");
								} else if (span == "<u>") {
									this.current_text.append("</u>");
								} else if (span == "<s>") {
									this.current_text.append("</s>");
								} else if (span == "<tt>") {
									this.current_text.append("</tt>");
								} else if (span.has_prefix("<a")) {
									this.current_text.append("</a>");
								}
							}
						}
						break;
						
					case MD4C.TextType.BR:
						this.flush_text();
						this.insert_markup("\n");
						break;
						
					case MD4C.TextType.SOFTBR:
						if (!this.in_code_block) {
							this.current_text.append(" ");
						} else {
							this.current_text.append("\n");
						}
						break;
						
					case MD4C.TextType.ENTITY:
						// HTML entities - md4c provides decoded text
						this.current_text.append(GLib.Markup.escape_text(text_str, -1));
						break;
						
					case MD4C.TextType.CODE:
						// Inline code
						this.current_text.append("<tt>");
						this.current_text.append(GLib.Markup.escape_text(text_str, -1));
						this.current_text.append("</tt>");
						break;
					default:
						break;
				}
			} catch (Error e) {
				return 1; // Error
			}
			return 0; // Success
		}
		
		private void flush_text()
		{
			if (this.current_text.len > 0) {
				string text = this.current_text.str;
				this.current_text = new StringBuilder();
				
				// Handle headers
				if (this.block_stack.size > 0) {
					var block = this.block_stack[this.block_stack.size - 1];
					if (block.type == MD4C.BlockType.H) {
						string size_tag = "";
						switch (block.level) {
							case 1:
								size_tag = "<span size=\"xx-large\" weight=\"bold\">";
								break;
							case 2:
								size_tag = "<span size=\"x-large\" weight=\"bold\">";
								break;
							case 3:
								size_tag = "<span size=\"large\" weight=\"bold\">";
								break;
							default:
								size_tag = "<span weight=\"bold\">";
								break;
						}
						text = size_tag + text + "</span>";
					}
				}
				
				// Handle list items
				if (this.block_stack.size > 1) {
					var block = this.block_stack[this.block_stack.size - 1];
					if (block.type == MD4C.BlockType.LI) {
						// Check parent list type
						if (this.block_stack.size > 2) {
							var parent = this.block_stack[this.block_stack.size - 2];
							if (parent.type == MD4C.BlockType.UL) {
								text = "• " + text;
							} else if (parent.type == MD4C.BlockType.OL) {
								// TODO: track list item numbers
								text = "1. " + text;
							}
						}
					}
				}
				
				// Handle blockquotes
				if (this.block_stack.size > 0) {
					var block = this.block_stack[this.block_stack.size - 1];
					if (block.type == MD4C.BlockType.QUOTE) {
						text = "<i>" + text + "</i>";
					}
				}
				
				// Insert into buffer or table
				if (this.in_table && this.current_table.active && !this.table_error) {
					this.current_table.insert_table_cell(this, text);
				} else {
					this.insert_markup(text);
				}
			}
		}
		
		private void insert_markup(string markup)
		{
			Gtk.TextIter iter;
			if (this.end_mark != null) {
				this.buffer.get_iter_at_mark(out iter, this.end_mark);
			} else {
				this.buffer.get_end_iter(out iter);
			}
			this.buffer.insert_markup(ref iter, markup, -1);
		}
		
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

