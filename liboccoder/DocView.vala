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

namespace OLLMcoder
{
	/**
	 * Rendered view of one open file.
	 *
	 * {@link CoderView} shows one {@link DocView} in place of
	 * {@link SourceView}. {@link MarkdownView} is the markdown
	 * implementor. Another implementor can render a different kind
	 * of file behind the same toggle.
	 *
	 * == Example ==
	 *
	 * {{{
	 * DocView doc = new MarkdownView();
	 * doc.show_file(file, true);
	 * doc.show_match("Hello", true, false, false);
	 * }}}
	 */
	public interface DocView : Gtk.Widget
	{
		/**
		 * Show this file.
		 *
		 * A new file starts at the top. The same file with the same
		 * contents does not rebuild.
		 *
		 * @param file Open file. The viewer reads what it needs.
		 * @param new_document True when the open file changed
		 */
		public abstract void show_file(OLLMfiles.File file, bool new_document);

		/**
		 * Move the view to the next match.
		 *
		 * A viewer that cannot search returns false.
		 *
		 * @param query Search text. A regex when ''use_regex'' is true
		 * @param forward True for the next match, false for the previous
		 * @param case_sensitive True when case matters
		 * @param use_regex True when ''query'' is a regular expression
		 * @return True when a match was shown
		 */
		public abstract bool show_match(string query, bool forward, bool case_sensitive, bool use_regex);
	}
}
