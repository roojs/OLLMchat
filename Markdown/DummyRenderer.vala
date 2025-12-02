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

namespace OLLMchat.Markdown
{
	/**
	 * Dummy renderer for testing the Parser.
	 * Extends Render and overrides methods to print callbacks instead of rendering.
	 */
	public class DummyRenderer : MarkdownGtk.Render
	{
		private int indent_level = 0;
		
		public DummyRenderer(Gtk.TextBuffer buffer, Gtk.TextMark start_mark) {
			base(buffer, start_mark);
		}
		
		private void print_indent()
		{
			for (int i = 0; i < indent_level; i++) {
				stdout.printf("  ");
			}
		}
		
		public override void on_text(string text)
		{
			print_indent();
			stdout.printf("TEXT: \"%s\"\n", text);
		}
		
		public override void on_em()
		{
			print_indent();
			stdout.printf("START: <em>\n");
			indent_level++;
		}
		
		public override void on_strong()
		{
			print_indent();
			stdout.printf("START: <strong>\n");
			indent_level++;
		}
		
		public override void on_code_span()
		{
			print_indent();
			stdout.printf("START: <code>\n");
			indent_level++;
		}
		
		public override void on_del()
		{
			print_indent();
			stdout.printf("START: <del>\n");
			indent_level++;
		}
		
		public override void on_other(string tag_name)
		{
			print_indent();
			stdout.printf("START: <%s>\n", tag_name);
			indent_level++;
		}
		
		public override void on_html(string tag, string attributes)
		{
			print_indent();
			if (attributes != "") {
				stdout.printf("START: <%s %s>\n", tag, attributes);
			} else {
				stdout.printf("START: <%s>\n", tag);
			}
			indent_level++;
		}
		
		public override void on_end()
		{
			indent_level--;
			print_indent();
			stdout.printf("END\n");
		}
	}
}

