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
		
		// Block-level callbacks - print with indentation
		public override void on_h(bool is_start, uint level)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <h%u>\n", level);
				return;
			}
			
			print_indent();
			stdout.printf("START: <h%u>\n", level);
			indent_level++;
		}
		
		public override void on_p(bool is_start)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <p>\n");
				return;
			}
			
			print_indent();
			stdout.printf("START: <p>\n");
			indent_level++;
		}
		
		public override void on_ul(bool is_start, uint indentation)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <ul> (indentation=%u)\n", indentation);
				return;
			}
			
			print_indent();
			stdout.printf("START: <ul> (indentation=%u)\n", indentation);
			indent_level++;
		}
		
		public override void on_ol(bool is_start, uint indentation)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <ol> (indentation=%u)\n", indentation);
				return;
			}
			
			print_indent();
			stdout.printf("START: <ol> (indentation=%u)\n", indentation);
			indent_level++;
		}
		
		public override void on_li(bool is_start, uint indent = 0)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <li>\n");
				return;
			}
			
			print_indent();
			stdout.printf("START: <li>\n");
			indent_level++;
		}
		
		public override void on_task_list(bool is_start, bool is_checked)
		{
			if (!is_start) {
				return;
			}
			
			print_indent();
			stdout.printf("START: <task_list> (checked=%s)\n", is_checked.to_string());
		}
		
		public override void on_code(bool is_start, string lang, char fence_char)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <code> (lang=%s, fence='%c')\n", lang, fence_char);
				return;
			}
			
			print_indent();
			stdout.printf("START: <code> (lang=%s, fence='%c')\n", lang, fence_char);
			indent_level++;
		}
		
		public override void on_code_text(string text)
		{
			print_indent();
			stdout.printf("CODE_TEXT: \"%s\"\n", text);
		}
		
		public override void on_code_block(bool is_start, string lang)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <code_block> (lang=%s)\n", lang);
				return;
			}
			
			print_indent();
			stdout.printf("START: <code_block> (lang=%s)\n", lang);
			indent_level++;
		}
		
		public override void on_quote(bool is_start, uint level)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <blockquote>\n");
				return;
			}
			
			print_indent();
			stdout.printf("START: <blockquote level=%u>\n", level);
			indent_level++;
		}
		
		public override void on_hr()
		{
			print_indent();
			stdout.printf("<hr>\n");
		}
		
		public override void on_table(bool is_start)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <table>\n");
				return;
			}
			print_indent();
			stdout.printf("START: <table>\n");
			indent_level++;
		}
		
		public override void on_table_row(bool is_start)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <tr>\n");
				return;
			}
			print_indent();
			stdout.printf("START: <tr>\n");
			indent_level++;
		}
		
		public override void on_table_hcell(bool is_start, int align)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <th>\n");
				return;
			}
			print_indent();
			stdout.printf("START: <th>\n");
			indent_level++;
		}
		
		public override void on_table_cell(bool is_start, int align)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <td>\n");
				return;
			}
			print_indent();
			stdout.printf("START: <td>\n");
			indent_level++;
		}
		
		public override void on_a(bool is_start, string href, string title, bool is_reference)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <a> (href=\"%s\", title=\"%s\", is_reference=%s)\n", href, title, is_reference.to_string());
				return;
			}
			
			print_indent();
			stdout.printf("START: <a> (href=\"%s\", title=\"%s\", is_reference=%s)\n", href, title, is_reference.to_string());
			indent_level++;
		}
		
		public override void on_img(string src, string title)
		{
			print_indent();
			stdout.printf("<img> (src=\"%s\", title=\"%s\")\n", src, title);
		}
		
		public override void on_br()
		{
			print_indent();
			stdout.printf("<br>\n");
		}
		
		public override void on_softbr()
		{
			print_indent();
			stdout.printf("<softbr>\n");
		}
		
		public override void on_entity(string text)
		{
			print_indent();
			stdout.printf("ENTITY: \"%s\"\n", text);
		}
		
		public override void on_u(bool is_start)
		{
			if (!is_start) {
				indent_level--;
				print_indent();
				stdout.printf("END: <u>\n");
				return;
			}
			
			print_indent();
			stdout.printf("START: <u>\n");
			indent_level++;
		}
	}
}

