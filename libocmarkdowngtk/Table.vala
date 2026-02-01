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

namespace MarkdownGtk
{
	internal class Table
	{
		private Render renderer;
		public Gtk.Grid grid { get; private set; }
		private int current_row = 0;
		private int current_cell = 0;
		private int num_cols = 0;
		private Gee.HashMap<int, Gee.HashMap<int, Gtk.ScrolledWindow>> cells {
			get; set; default = new Gee.HashMap<int, Gee.HashMap<int, Gtk.ScrolledWindow>>();
		}
		private Gee.HashMap<int, int> cellwidths { get; set; default = new Gee.HashMap<int, int>(); }

		// Fake stack and buffer when inside table but not in a cell (avoids nulls; add() never sees null)
		private Gtk.TextView table_fake_textview;
		private Gtk.TextBuffer table_fake_buffer;
		private TopState table_fake_top_state;

		public Table(Render renderer)
		{
			this.renderer = renderer;
			this.table_fake_textview = new Gtk.TextView();
			this.table_fake_buffer = this.table_fake_textview.buffer;
			// Set renderer to fake buffer before initialize() so TopState.initialize()
			// creates tag/marks in this table's fake buffer, not the previous cell's buffer
			this.renderer.current_textview = this.table_fake_textview;
			this.renderer.current_buffer = this.table_fake_buffer;
			this.table_fake_top_state = new TopState(this.renderer);
			this.renderer.top_state = this.table_fake_top_state;
			this.renderer.current_state = this.table_fake_top_state;
			this.table_fake_top_state.initialize();

			this.grid = new Gtk.Grid() {
				hexpand = true,
				vexpand = true,
				column_homogeneous = false,
				row_homogeneous = false,
				column_spacing = 0,
				row_spacing = 0,
				margin_start = 2,
				margin_end = 2,
				margin_top = 2,
				margin_bottom = 2
			};
			if (this.renderer.box == null) {
				return;
			}
			this.renderer.box.append(this.grid);
		}

		private void set_renderer_to_fake()
		{
			// Close any open formatting states so we leave the cell in a safe state
			while (this.renderer.current_state != this.renderer.top_state) {
				this.renderer.current_state.close_state();
			}
			this.renderer.current_textview = this.table_fake_textview;
			this.renderer.current_buffer = this.table_fake_buffer;
			this.renderer.top_state = this.table_fake_top_state;
			this.renderer.current_state = this.table_fake_top_state;
		}

		/** Measure cell content width by line: Pango layout per line, max width. */
		private int measure_cell_width(Gtk.TextView text_view)
		{
			var buffer = text_view.buffer;
			Gtk.TextIter start_iter;
			buffer.get_start_iter(out start_iter);
			int max_width = 0;
			while (!start_iter.is_end()) {
				var end_iter = start_iter;
				end_iter.forward_to_line_end();
				string line = buffer.get_text(start_iter, end_iter, false);
				if (line.length > 0) {
					var layout = text_view.create_pango_layout(line);
					int line_width;
					layout.get_pixel_size(out line_width, null);
					max_width = int.max(max_width, line_width);
				}
				if (!start_iter.forward_line()) {
					break;
				}
			}
			int margin = text_view.left_margin + text_view.right_margin;
			return max_width > 0 ? max_width + margin : margin;
		}

		private void resize(Gee.HashMap<int, int> widths)
		{
			foreach (var row_entry in this.cells.entries) {
				var row_cells = row_entry.value;
				foreach (var col_entry in row_cells.entries) {
					var  c = col_entry.key;
					var sw = col_entry.value;
					var w = widths.has_key(c) ? widths.get(c) : 100;
					sw.width_request = w;
				}
			}
		}

		private void build_widths_and_resize()
		{
			var ncols = this.num_cols > 0 ? this.num_cols : this.current_cell;
			var container = 400;
			if (this.grid.get_width() > 0) {
				container = this.grid.get_width();
			}
			var min_col = (ncols < 5) ? (int)(0.10 * container) : 50;
			var max_col = (ncols <= 5) ? (int)(0.60 * container) : 400;

			var widths = new Gee.HashMap<int, int>();
			foreach (var e in this.cellwidths.entries) {
				var c = e.key;
				var w = e.value.clamp(min_col, max_col);
				widths.set(c, w);
			}
			this.resize(widths);
		}

		public void on_row(bool is_start)
		{
			if (is_start) {
				this.current_cell = 0;
				this.cells.set(this.current_row, new Gee.HashMap<int, Gtk.ScrolledWindow>());
				return;
			}
			this.num_cols = int.max(this.num_cols, this.current_cell);
			// Add a bottom-only separator line below this row
			var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL) {
				hexpand = true,
				height_request = (this.current_row == 0) ? 4 : 2
			};
			sep.add_css_class(this.current_row == 0 ? "oc-table-header-sep" : "oc-table-body-sep");
			this.grid.attach(sep, 0, this.current_row * 2 + 1, this.current_cell, 1);
			GLib.Idle.add(() => {
				this.build_widths_and_resize();
				return false;
			});
			this.current_row++;
		}

		public void on_hcell(bool is_start, int align)
		{
			if (is_start) {
				this.create_cell(align, true);
				return;
			}
			var nat_w = this.measure_cell_width(this.renderer.current_textview);
			var cur = this.cellwidths.has_key(this.current_cell) ? this.cellwidths.get(this.current_cell) : 0;
			this.cellwidths.set(this.current_cell, int.max(cur, nat_w));
			this.set_renderer_to_fake();
			this.current_cell++;
		}

		public void on_cell(bool is_start, int align)
		{
			if (is_start) {
				this.create_cell(align, false);
				return;
			}
			var nat_w = this.measure_cell_width(this.renderer.current_textview);
			var cur = this.cellwidths.has_key(this.current_cell) ? this.cellwidths.get(this.current_cell) : 0;
			this.cellwidths.set(this.current_cell, int.max(cur, nat_w));
			this.set_renderer_to_fake();
			this.current_cell++;
		}

		// Minimum cell size: a few characters wide, one line high (approx. 8px per char)
	

		private void create_cell(int align, bool is_header)
		{
			var cell_view = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.WORD,
				hexpand = true,
				vexpand = false,
				halign = Gtk.Align.FILL,
				valign = Gtk.Align.FILL,
				left_margin = 4,
				right_margin = 4,
				top_margin = 4,
				bottom_margin = 4,
				width_request = 100,
				height_request = -1,
				margin_top = 0,
				margin_bottom = 0
			};
			cell_view.add_css_class("oc-markdown-text");

			var cell_scrolled = new Gtk.ScrolledWindow() {
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				vscrollbar_policy = Gtk.PolicyType.NEVER,
				propagate_natural_height = false,
				propagate_natural_width = false,
				min_content_height = 0,
				hexpand = true,
				vexpand = false,
				halign = Gtk.Align.FILL,
				valign = Gtk.Align.FILL,
				margin_top = 0,
				margin_bottom = 0
			};
			cell_scrolled.set_child(cell_view);
			// Grid row = current_row * 2 (separator rows go at current_row * 2 + 1)
			this.grid.attach(cell_scrolled, this.current_cell, this.current_row * 2, 1, 1);
			this.cells.get(this.current_row).set(this.current_cell, cell_scrolled);
			// Initialize new cell's top state for this buffer without changing render's
			// current_buffer/current_state yet, so we never have buffer A with state from buffer B
			var cell_top = new TopState(this.renderer);
			cell_top.initialize_for_buffer(cell_view.buffer);
			// Header bold and column alignment via TextTag justification (view keeps FILL for expansion)
			if (cell_top.style != null) {
				if (is_header) {
					cell_top.style.weight = Pango.Weight.BOLD;
				}
				switch (align) {
					case 0:
						cell_top.style.justification = Gtk.Justification.CENTER;
						break;
					case 1:
						cell_top.style.justification = Gtk.Justification.RIGHT;
						break;
					default:
						cell_top.style.justification = Gtk.Justification.LEFT;
						break;
				}
			}
			this.renderer.current_textview = cell_view;
			this.renderer.current_buffer = cell_view.buffer;
			this.renderer.top_state = cell_top;
			this.renderer.current_state = cell_top;
			// Touch buffer with insert() so the view treats it as loaded (GTK TextBuffer requirement)
			Gtk.TextIter iter;
			cell_view.buffer.get_end_iter(out iter);
			cell_view.buffer.insert(ref iter, "", -1);
		}
	}
}
