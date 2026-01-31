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
			this.table_fake_top_state = new TopState(this.renderer);
			this.table_fake_top_state.initialize();
			this.renderer.current_textview = this.table_fake_textview;
			this.renderer.current_buffer = this.table_fake_buffer;
			this.renderer.top_state = this.table_fake_top_state;
			this.renderer.current_state = this.table_fake_top_state;

			this.grid = new Gtk.Grid() {
				column_homogeneous = false,
				row_homogeneous = false,
				column_spacing = 4,
				row_spacing = 4,
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
				this.create_cell(align);
				return;
			}
			this.set_renderer_to_fake();
			this.current_cell++;
		}

		public void on_cell(bool is_start, int align)
		{
			if (is_start) {
				this.create_cell(align);
				return;
			}
			this.set_renderer_to_fake();
			this.current_cell++;
		}

		private void create_cell(int align)
		{
			var cell_view = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.WORD,
				hexpand = true,
				vexpand = false
			};

			switch (align) {
				case 0:
					cell_view.halign = Gtk.Align.CENTER;
					break;
				case 1:
					cell_view.halign = Gtk.Align.END;
					break;
				default:
					cell_view.halign = Gtk.Align.START;
					break;
			}

			this.grid.attach(cell_view, this.current_cell, this.current_row, 1, 1);
			this.renderer.current_textview = cell_view;
			this.renderer.current_buffer = cell_view.buffer;
			this.renderer.top_state = new TopState(this.renderer);
			this.renderer.top_state.initialize();
			this.renderer.current_state = this.renderer.top_state;
		}
	}
}
