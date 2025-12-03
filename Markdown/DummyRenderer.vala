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

namespace Markdown
{
	/**
	 * Dummy renderer for testing the Parser.
	 * Extends RenderBase and overrides methods to print callbacks instead of rendering.
	 */
	public class DummyRenderer : RenderBase
	{
		private int indent_level = 0;
		
		public DummyRenderer()
		{
			base();
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
		
		public override void on_em(bool is_start)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <em>\n");
				return;
			}
			
			print_indent();
			stdout.printf("START: <em>\n");
			indent_level++;
		}
		
		public override void on_strong(bool is_start)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <strong>\n");
				return;
			}
			
			print_indent();
			stdout.printf("START: <strong>\n");
			indent_level++;
		}
		
		public override void on_code_span(bool is_start)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <code>\n");
				return;
			}
			
			print_indent();
			stdout.printf("START: <code>\n");
			indent_level++;
		}
		
		public override void on_del(bool is_start)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <del>\n");
				return;
			}
			
			print_indent();
			stdout.printf("START: <del>\n");
			indent_level++;
		}
		
		public override void on_other(bool is_start, string tag_name)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <%s>\n", tag_name);
				return;
			}
			
			print_indent();
			stdout.printf("START: <%s>\n", tag_name);
			indent_level++;
		}
		
		public override void on_html(bool is_start, string tag, string attributes)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				if (attributes != "") {
					stdout.printf("END: <%s %s>\n", tag, attributes);
				} else {
					stdout.printf("END: <%s>\n", tag);
				}
				return;
			}
			
			print_indent();
			if (attributes != "") {
				stdout.printf("START: <%s %s>\n", tag, attributes);
			} else {
				stdout.printf("START: <%s>\n", tag);
			}
			indent_level++;
		}
	}
}

