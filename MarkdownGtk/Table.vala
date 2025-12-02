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
	internal class Table
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
		// Store cell content to be inserted at end
		private Gee.ArrayList<TableCell> cells;
		
		public Table(Render? renderer, uint cols)
		{
			this.col_count = cols;
			this.cells = new Gee.ArrayList<TableCell>();
			
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
				
				// Create child anchor - will be set when building table
				
			} catch (Error e) {
				this.error = true;
				this.active = false;
			}
		}
		
		public void store_cell_content(string content, uint row, uint col, bool is_header)
		{
			this.cells.add(new TableCell(content, row, col, is_header));
		}
		
		public void build_and_insert_table(Render renderer)
		{
			if (!this.active || this.error || this.frame == null || this.grid == null) {
				return;
			}
			
			try {
				// Create child anchor at current position
				if (renderer.current_buffer == null) {
					return;
				}
				Gtk.TextIter iter;
				// Use end of buffer (TopState's end mark is protected)
				renderer.current_buffer.get_end_iter(out iter);
				
				this.anchor = renderer.current_buffer.create_child_anchor(iter);
				
				// Build all cells
				foreach (var cell in this.cells) {
					var label = new Gtk.Label(null) {
						use_markup = true,
						wrap = true,
						halign = Gtk.Align.START,
						valign = Gtk.Align.START
					};
					
					if (cell.is_header) {
						label.add_css_class("table-header");
					}
					
					label.set_markup(cell.content);
					
					this.grid.attach(label, (int)cell.col, (int)cell.row, 1, 1);
				}
				
				// Insert frame via child anchor
				// Note: text_view handling removed - tables will be handled separately
				// TODO: Implement table insertion when table handling is added
				
				// Show frame
				this.frame.set_visible(true);
				
			} catch (Error e) {
				this.error = true;
				// Note: table_error property removed - tables will be handled separately
			}
		}
	}
	
	internal class TableEmpty : Table
	{
		public override bool active { get; set; default = false; }
		
		public TableEmpty()
		{
			base(null, 0);
		}
	}
}

