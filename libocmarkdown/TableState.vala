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
 * along with this library; if not, see <https://www.gnu.org/licenses/>.
 */

namespace Markdown
{
	/**
	 * Helper class that owns table line parsing and emits renderer callbacks.
	 * Used by Parser when current_block == TABLE; one line is fed at a time via feed_line().
	 */
	internal class TableState
	{
		private Parser parser;
		private string table_header_line = "";
		private Gee.ArrayList<int> table_alignments = new Gee.ArrayList<int>();
		private int table_row_index = 0;

		internal TableState(Parser parser)
		{
			this.parser = parser;
		}

		private string[] split_row(string line)
		{
			var inner = line.substring(1, line.length - 2);
			var parts = inner.split("|");
			var result = new string[parts.length];
			for (var i = 0; i < parts.length; i++) {
				result[i] = parts[i];
			}
			return result;
		}

		private int parse_align(string cell)
		{
			var s = cell.strip();
			return s.has_prefix(":") && s.has_suffix(":") ? 0 : (s.has_suffix(":") ? 1 : -1);
		}

		private void emit_row(string[] cells, bool is_header)
		{
			this.parser.renderer.on_table_row(true);
			for (var i = 0; i < cells.length; i++) {
				var align = (i < this.table_alignments.size) ? this.table_alignments.get(i) : -1;
				if (is_header) {
					this.parser.renderer.on_table_hcell(true, align);
				} else {
					this.parser.renderer.on_table_cell(true, align);
				}
				this.parser.process_inline(cells[i]);
				if (is_header) {
					this.parser.renderer.on_table_hcell(false, align);
				} else {
					this.parser.renderer.on_table_cell(false, align);
				}
			}
			this.parser.renderer.on_table_row(false);
		}

		internal void feed_line(string line)
		{
			if (this.table_row_index == 0) {
				this.table_header_line = line;
				this.table_row_index = 1;
				return;
			}
			if (this.table_row_index == 1) {
				var cells = this.split_row(line);
				this.table_alignments.clear();
				for (var i = 0; i < cells.length; i++) {
					this.table_alignments.add(this.parse_align(cells[i]));
				}
				this.table_row_index = 2;
				return;
			}
			if (this.table_row_index == 2) {
				this.parser.renderer.on_table(true);
				var cells1 = this.split_row(this.table_header_line);
				this.emit_row(cells1, true);
				var cells3 = this.split_row(line);
				this.emit_row(cells3, false);
				this.table_row_index = 3;
				return;
			}
			var cells = this.split_row(line);
			this.emit_row(cells, false);
			this.table_row_index++;
		}
	}
}
