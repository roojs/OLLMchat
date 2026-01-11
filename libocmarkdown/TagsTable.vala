/*
 * Copyright (c) Tim Gromeyer
 * Licensed under the MIT License - https://opensource.org/licenses/MIT
 *
 * Ported to Vala by Alan Knowles <alan@roojs.com>
 */

using Gee;

namespace Markdown
{
	/**
	 * Handler for table tags.
	 */
	internal class TagTable : TagIgnored
	{
		private const int MIN_LINE_LENGTH = 3;

		public TagTable(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			c.is_in_table = true;
			this.writer.append("\n");
			this.writer.table_start = (int)this.writer.md.len;
		}

		public override void close(HtmlParser c)
		{
			c.is_in_table = false;
			this.writer.append("\n");

			if (!c.format_table) {
				return;
			}

			var table = this.writer.md.str.substring(this.writer.table_start);
			table = this.format_markdown_table(table);
			this.writer.shorten((int)this.writer.md.len - this.writer.table_start);
			this.writer.append(table);
		}

		/**
		 * Enlarge table header line based on alignment markers.
		 */
		private string enlarge_table_header_line(string str, size_t length)
		{
			if (str.length == 0 || length < MIN_LINE_LENGTH) {
				return "";
			}

			int first = str.index_of_char(':');
			int last = str.last_index_of_char(':');

			if (first == 0 && first == last) {
				last = -1; // string::npos equivalent
			}

			var line = string.nfill((int)length, '-');

			if (first == 0) {
				var builder = new StringBuilder();
				builder.append_c(':');
				builder.append(line.substring(1));
				line = builder.str;
			}
			if (last != -1 && last == (int)str.length - 1) {
				var builder = new StringBuilder();
				builder.append(line.substring(0, (int)length - 1));
				builder.append_c(':');
				line = builder.str;
			}

			return line;
		}

		/**
		 * Format a markdown table with proper column alignment.
		 */
		private string format_markdown_table(string input_table)
		{
			var table_data = new Gee.ArrayList<Gee.ArrayList<string>>();

			// Parse the input table into a 2D list
			foreach (var line in input_table.split("\n")) {
				if (line.length == 0) {
					continue;
				}

				var row_data = new Gee.ArrayList<string>();
				var cells = line.split("|");

				foreach (var cell in cells) {
					if (cell.length > 0) {
						row_data.add(cell.strip());
					}
				}

				if (row_data.size > 0) {
					table_data.add(row_data);
				}
			}

			if (table_data.size == 0) {
				return "";
			}

			// Determine maximum width of each column
			var column_widths = new Gee.ArrayList<int>();
			if (table_data.size > 0) {
				// Initialize with first row size
				for (int i = 0; i < table_data[0].size; i++) {
					column_widths.add(0);
				}
			}

			foreach (var row in table_data) {
				// Resize column_widths if needed
				while (column_widths.size < row.size) {
					column_widths.add(0);
				}

				for (int i = 0; i < row.size; i++) {
					if (row[i].length > column_widths[i]) {
						column_widths[i] = (int)row[i].length;
					}
				}
			}

			// Build the formatted table
			var formatted_table = new StringBuilder();
			for (int row_number = 0; row_number < table_data.size; row_number++) {
				var row = table_data[row_number];

				formatted_table.append("|");

				for (int i = 0; i < row.size; i++) {
					if (row_number == 1) {
						// This is the separator row
						var header_line = this.enlarge_table_header_line(row[i], column_widths[i] + 2);
						formatted_table.append(header_line);
						formatted_table.append("|");
						continue;
					}

					// Format cell with proper width and left alignment
					var cell = row[i];
					var padding = column_widths[i] - (int)cell.length;
					formatted_table.append(" ");
					formatted_table.append(cell);
					for (int j = 0; j < padding; j++) {
						formatted_table.append_c(' ');
					}
					formatted_table.append(" |");
				}
				formatted_table.append_c('\n');
			}

			return formatted_table.str;
		}
	}

	/**
	 * Handler for table row tags.
	 */
	internal class TagTableRow : TagIgnored
	{
		public TagTableRow(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			this.writer.append("\n");
		}

		public override void close(HtmlParser c)
		{
			this.writer.update_prev_ch();
			if (this.writer.prev_ch_in_md == '|') {
				this.writer.append("\n"); // There's a bug
			} else {
				this.writer.append("|");
			}

			if (this.writer.table_line.len > 0) {
				if (this.writer.prev_ch_in_md != '\n') {
					this.writer.append("\n");
				}

				this.writer.table_line.append("|\n");
				this.writer.append(this.writer.table_line.str);
				this.writer.table_line = new StringBuilder();
			}
		}
	}

	/**
	 * Handler for table header tags.
	 */
	internal class TagTableHeader : TagIgnored
	{
		public TagTableHeader(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			var align = c.attr.has_key("align") ? c.attr.get("align") : "";
			if (align == null) {
				align = "";
			}

			var line = "| ";

			if (align == "left" || align == "center") {
				line += ":";
			}

			line += "-";

			if (align == "right" || align == "center") {
				line += ": ";
			} else {
				line += " ";
			}

			this.writer.table_line.append(line);

			this.writer.append("| ");
		}
	}

	/**
	 * Handler for table data tags.
	 */
	internal class TagTableData : TagIgnored
	{
		public TagTableData(Writer writer)
		{
			base(writer);
		}

		public override void open(HtmlParser c)
		{
			if (this.writer.prev_prev_ch_in_md != '|') {
				this.writer.append("| ");
			}
		}
	}
}

