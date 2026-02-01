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
		private Gtk.Grid grid;
		private int current_row = 0;
		private int current_cell = 0;

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

		public void on_row(bool is_start)
		{
			if (is_start) {
				this.current_cell = 0;
				return;
			}
			this.current_row++;
		}

		public void on_hcell(bool is_start, int align)
		{
			if (is_start) {
				this.create_cell(align, true);
				return;
			}
			this.set_renderer_to_fake();
			this.current_cell++;
		}

		public void on_cell(bool is_start, int align)
		{
			if (is_start) {
				this.create_cell(align, false);
				return;
			}
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
			this.grid.attach(cell_scrolled, this.current_cell, this.current_row, 1, 1);
			// Initialize new cell's top state for this buffer without changing render's
			// current_buffer/current_state yet, so we never have buffer A with state from buffer B
			var cell_top = new TopState(this.renderer);
			cell_top.initialize_for_buffer(cell_view.buffer);
			// Column alignment via TextTag justification (view keeps FILL for expansion)
			if (cell_top.style != null) {
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
