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
	 * Marker map for inline format markers (bold, italic, code, etc.).
	 * Used by the parser for format detection via eat().
	 */
	public class FormatMap : MarkerMap
	{
		private static Gee.HashMap<string, FormatType> mp;
		private weak Parser? parser;

		private const string LINK_INNER_PATTERN =
			"(<[^>]*>|[^\\s\"'()]+)" +
			"(?:\\s+(\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|\\([^)]*\\)))?";
		private static GLib.Regex? inner_link_regex = null;
		private static GLib.Regex? inline_link_regex = null;

		/**
		 * Extract verified link data from chunk[chunk_pos..end_offset), then emit via parser: on_a(true,...), process_inline(link_text), on_a(false,...).
		 * seq_pos = byte after the 3-char lead [??; end_offset = byte after the link (e.g. after ')' for inline, after ']' for reference).
		 * Sets is_reference true for reference-style; then href is the ref label (consumer resolves to URL).
		 */
		public void handle_link(
			string chunk,
			int chunk_pos,
			int seq_pos,
			int end_offset
		) {
			var rest = chunk.substring(seq_pos, end_offset - seq_pos);
			var close_idx = rest.index_of_char(']');
			var link_text_val = chunk.substring(chunk_pos + 1, (seq_pos + close_idx) - (chunk_pos + 1));
			var after_close = seq_pos + close_idx + 1;
			var c1 = chunk.get_char(after_close);
			var href = chunk.substring(after_close + 1, (end_offset - 1) - (after_close + 1)).strip();
			var title = "";
			var is_reference = false;
			if (c1 != '(') {
				is_reference = true;
				var ref_start = after_close + 1;
				var ref_end_byte = end_offset - 1;
				href = ref_end_byte > ref_start
					? chunk.substring(ref_start, ref_end_byte - ref_start).strip()
					: link_text_val.strip();  // implicit reference [text][] — use link text as ref key (no reference table)
			}
			if (c1 == '(') {
				if (inner_link_regex == null) {
					inner_link_regex = new GLib.Regex(
						"^\\s*" + LINK_INNER_PATTERN + "\\s*$");
				}
				GLib.MatchInfo mi;
				if (inner_link_regex.match_full(href, -1, 0, 0, out mi)) {
					var dest = mi.fetch(1);
					href = dest.has_prefix("<") ? dest.substring(1, dest.length - 2) : dest.strip();
					var t = mi.fetch(2);
					if (t != null && t.length >= 2) {
						var raw = t.substring(1, t.length - 2);
						title = raw.replace("\\\\", "\\")
							.replace("\\\"", "\"")
							.replace("\\'", "'")
							.replace("\\" + ")", ")");
					}
				}
			}
			this.parser.renderer.on_a(true, href, title, is_reference);
			this.parser.process_inline(link_text_val);
			this.parser.renderer.on_a(false, href, title, is_reference);
		}

		/**
		 * Parse and consume a link after the 3-char lead [??. Only eats the chunk; does not extract strings.
		 * Caller uses returned end offset and calls handle_link(chunk, chunk_pos, seq_pos, end_offset).
		 * @return -1 need more input, 0 no match, >0 byte offset in chunk after the consumed link
		 */
		public int eat_link(
			string chunk,
			int chunk_pos,
			int seq_pos,
			bool is_end_of_chunks
		) {
			var rest = chunk.substring(seq_pos, chunk.length - seq_pos);
			var close_idx = rest.index_of_char(']');
			if (close_idx == -1) {
				if (!is_end_of_chunks) {
					return -1;
				}
				return 0;
			}
			// Newline inside link text [..\n..] → not a link (CommonMark); return no match. Newline after the link is valid (no check).
			if (rest.substring(0, close_idx).index_of_char('\n') != -1) {
				return 0;
			}
			// Link text containing '[' → reject (so process_inline(link_text) never sees LINK; table cells still parse links via LINK branch below).
			if (rest.substring(0, close_idx).index_of_char('[') != -1) {
				return 0;
			}
			var after_close = seq_pos + close_idx + 1;
			if (chunk.length - after_close < 2) {
				if (!is_end_of_chunks) {
					return -1;
				}
				return 0;
			}
			var c1 = chunk.get_char(after_close);
			if (c1 != '(' && c1 != '[') {
				return 0;
			}
			if (c1 == '(') {
				// Match full inline link ](dest "title") or ](dest 'title') or ](dest (title)) with regex; no character loop
				if (inline_link_regex == null) {
					inline_link_regex = new GLib.Regex(
						"^\\s*\\(" + LINK_INNER_PATTERN + "\\s*\\)");
				}
				var rest_link = chunk.substring(after_close, chunk.length - after_close);
				GLib.MatchInfo mi;
				if (inline_link_regex.match_full(rest_link, -1, 0, 0, out mi)) {
					var matched = mi.fetch(0);
					return after_close + matched.length;
				}
				if (!is_end_of_chunks) {
					return -1;
				}
				return 0;
			}
			// c1 == '[' — reference-style: ][ref] or ][]. Parser does not resolve refs; just return end offset.
			var ref_start = after_close + 1;
			var ref_end = chunk.index_of_char(']', ref_start);
			if (ref_end == -1) {
				if (!is_end_of_chunks) {
					return -1;
				}
				return 0;
			}
			return ref_end + 1; // Match; handle_link will set is_reference true and href = ref label
		}

		private static void init()
		{
			if (mp != null) {
				return;
			}
			mp = new Gee.HashMap<string, FormatType>();

			// Asterisk and underscore emphasis: handled by StartMap (line start), LeftMap (preceded by space), RightMap (followed by whitespace/newline)

			// Code and inline code
			mp["`"] = FormatType.LITERAL;
			mp["``"] = FormatType.CODE;

			// Strikethrough (GFM)
			mp["~"] = FormatType.INVALID;
			mp["~~"] = FormatType.STRIKETHROUGH;

			// Task list checkboxes: [ ], [x], [X] (GFM). Link lead: "[?" → eat() -1; "[??" → LINK
			mp.set("[", FormatType.INVALID);
			mp.set("[?", FormatType.INVALID);
			mp.set("[??", FormatType.LINK);
			mp.set("[ ]", FormatType.TASK_LIST);
			mp.set("[x]", FormatType.TASK_LIST_DONE);
			mp.set("[X]", FormatType.TASK_LIST_DONE);

			mp.set("<", FormatType.HTML);
		}

		public FormatMap(Parser parser)
		{
			FormatMap.init();
			base(FormatMap.mp);
			this.parser = parser;
		}

		/**
		 * Peek for closing backtick delimiter when inside a code span (is_literal != "").
		 * @return 0 no match (treat char as literal), -1 need more data, N match length in bytes
		 */
		public int peek_literal(string chunk, int chunk_pos, bool is_end_of_chunks, string is_literal)
		{
			if (is_literal == "" || chunk_pos >= chunk.length) {
				return 0;
			}
			var c0 = chunk.get_char(chunk_pos);
			if (c0 != '`') {
				return 0;
			}
			if (is_literal.length == 1) {
				return 1;
			}
			if (chunk_pos + 1 >= chunk.length) {
				if (!is_end_of_chunks) {
					return -1;
				}
				return 0;
			}
			var c1 = chunk.get_char(chunk_pos + 1);
			if (c1 != '`') {
				return 0;
			}
			return 2;
		}

		/**
		 * Handles format peek result. Caller calls eat() then this.
		 * Updates chunk_pos, str, chunk when consuming; may set parser.leftover_chunk.
		 * @return true (need more characters or flushed; leftover_chunk may be set), false to keep processing the rest of the chunk
		 */
		public bool handle_format_result(
			int match_len,
			FormatType matched_format,
			unichar c,
			ref int chunk_pos,
			ref string str,
			ref string chunk,
			bool is_end_of_chunks
		) {
			if (match_len == -1) {
				this.parser.leftover_chunk = str + chunk.substring(chunk_pos, chunk.length - chunk_pos);
				str = "";
				return true;
			}
			if (match_len == 0) {
				// No match - caller advances chunk_pos and adds char to str
				return false;
			}
			this.parser.renderer.on_node(FormatType.TEXT, false, str);
			str = "";
			var seq_pos = chunk_pos;
			for (int i = 0; i < match_len; i++) {
				var ch = chunk.get_char(seq_pos);
				seq_pos += ch.to_string().length;
			}
			if (matched_format == FormatType.LINK) {
				var link_result = this.eat_link(chunk, chunk_pos, seq_pos, is_end_of_chunks);
				if (link_result == -1) {
					this.parser.leftover_chunk = str + chunk.substring(chunk_pos, chunk.length - chunk_pos);
					str = "";
					return true;
				}
				if (link_result == 0) {
					this.parser.renderer.on_node(FormatType.TEXT, false, chunk.substring(chunk_pos, seq_pos - chunk_pos));
					chunk_pos = seq_pos;
					return false;
				}
				this.handle_link(chunk, chunk_pos, seq_pos, link_result);
				chunk_pos = link_result;
				return false;
			}
			if (matched_format != FormatType.HTML) {
				this.parser.got_format(matched_format);
				chunk_pos = seq_pos;
				return false;
			}
			var html_res = this.parser.peekHTML(chunk, seq_pos, is_end_of_chunks);
			if (html_res == -1) {
				this.parser.leftover_chunk = str + chunk.substring(chunk_pos, chunk.length - chunk_pos);
				str = "";
				return true;
			}
			if (html_res == 0) {
				var html_text = chunk.substring(chunk_pos, seq_pos - chunk_pos);
				str += html_text;
				chunk_pos = seq_pos;
				return false;
			}
			chunk_pos = seq_pos;
			chunk = this.parser.add_html(chunk.substring(chunk_pos, chunk.length - chunk_pos));
			chunk_pos = 0;
			if (chunk.length > 0 && chunk.get_char(0) == '<' && is_end_of_chunks) {
				return false;
			}
			if (chunk.length > 0 && chunk.get_char(0) == '<') {
				this.parser.leftover_chunk = str + chunk; // a bit werid as we have modified chunk in here
				return true;
			}
			return false;
		}
	}
}
