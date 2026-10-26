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
	 * Read-only markdown preview of one document.
	 *
	 * {@link CoderView} owns this widget and shows it in place of
	 * {@link SourceView}. The same text does not rebuild. Changed
	 * text restores the scroll position. A different document starts
	 * at the top. A link click shows the address, and a click on
	 * that popover follows the link.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var preview = new MarkdownView();
	 * preview.show_file(file, true);
	 * preview.show_match("Hello", true, false, false);
	 * }}}
	 */
	public class MarkdownView : Gtk.Box, DocView
	{
		private MarkdownGtk.RenderBox box;
		private MarkdownGtk.Render render;
		private Gtk.ScrolledWindow scroller;
		private Gtk.Popover link_popover;
		private Gtk.Button link_button;
		private string shown = "";
		private string link_href = "";
		private string match_query = "";
		private bool has_shown = false;
		private int match_child = -1;
		private int match_end = 0;
		private double kept_scroll = 0;

		/**
		 * Build the scroller, the renderer, and the link popover.
		 */
		public MarkdownView()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.hexpand = true;
			this.vexpand = true;
			this.box = new MarkdownGtk.RenderBox();
			this.render = new MarkdownGtk.Render(this.box) {
				scroll_to_end = false
			};
			this.scroller = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true,
				child = this.box
			};
			this.append(this.scroller);
			this.link_button = new Gtk.Button.with_label("") {
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 8
			};
			this.link_button.clicked.connect(() => {
				this.link_popover.popdown();
				if (this.link_href == "") {
					return;
				}
				var win = this.get_root() as Gtk.Window;
				if (win == null) {
					return;
				}
				var launcher = new Gtk.UriLauncher(this.link_href);
				launcher.launch.begin(win, null, (obj, res) => {
					try {
						((Gtk.UriLauncher) obj).launch.end(res);
					} catch (GLib.Error e) {
						GLib.warning("Failed to open link %s: %s", this.link_href, e.message);
					}
				});
			});
			this.link_popover = new Gtk.Popover() {
				autohide = true,
				position = Gtk.PositionType.BOTTOM,
				child = this.link_button
			};
			this.link_popover.set_parent(this);
			this.render.link_clicked.connect((href, title) => {
				this.link_href = href;
				this.link_button.label = href;
				this.link_button.tooltip_text = title;
				this.link_popover.popup();
			});
		}

		/**
		 * Show this markdown file.
		 *
		 * Reads the document from ''file.buffer''. The same text
		 * leaves the current render in place. Changed text rebuilds
		 * and restores the scroll position. A new document starts
		 * at the top.
		 *
		 * @param file Open file
		 * @param new_document True when the open file changed
		 */
		public void show_file(OLLMfiles.File file, bool new_document)
		{
			var text = ((GtkSource.Buffer) file.buffer).text;
			if (this.has_shown && text == this.shown) {
				if (!new_document) {
					return;
				}
				this.scroller.vadjustment.value = 0;
				this.match_query = "";
				this.match_child = -1;
				this.match_end = 0;
				return;
			}
			this.kept_scroll = 0;
			if (!new_document) {
				this.kept_scroll = this.scroller.vadjustment.value;
			}
			this.shown = text;
			this.has_shown = true;
			this.match_query = "";
			this.match_child = -1;
			this.match_end = 0;
			this.render.clear();
			this.render.disconnect_box();
			this.box = new MarkdownGtk.RenderBox();
			this.scroller.set_child(this.box);
			this.render.box = this.box;
			this.render.box.on_link_click_released.connect(this.render.on_link_click_released);
			this.render.box.on_link_motion.connect(this.render.on_link_motion);
			this.render.box.on_link_leave.connect(this.render.on_link_leave);
			this.render.scroll_to_end = false;
			this.render.start();
			this.render.add(text);
			this.render.flush();
			GLib.Idle.add(() => {
				var upper = this.scroller.vadjustment.upper - this.scroller.vadjustment.page_size;
				this.scroller.vadjustment.value = double.max(0, double.min(this.kept_scroll, upper));
				return false;
			});
		}

		/**
		 * Scroll the render to the next match of this query.
		 *
		 * @param query Search text. A regex when ''use_regex'' is true
		 * @param forward True for the next match, false for the previous
		 * @param case_sensitive True when case matters
		 * @param use_regex True when ''query'' is a regular expression
		 * @return True when a match was shown
		 */
		public bool show_match(string query, bool forward, bool case_sensitive, bool use_regex)
		{
			if (query == "") {
				return false;
			}
			if (query != this.match_query) {
				this.match_query = query;
				this.match_child = -1;
				this.match_end = 0;
			}
			var source = query;
			if (!use_regex) {
				source = GLib.Regex.escape_string(query);
			}
			var flags = GLib.RegexCompileFlags.OPTIMIZE;
			if (!case_sensitive) {
				flags |= GLib.RegexCompileFlags.CASELESS;
			}
			GLib.Regex pattern;
			try {
				pattern = new GLib.Regex(source, flags, 0);
			} catch (GLib.RegexError e) {
				return false;
			}
			var views = new Gee.ArrayList<Gtk.TextView>();
			var child = this.box.get_first_child();
			while (child != null) {
				var view = child as Gtk.TextView;
				if (view != null) {
					views.add(view);
				}
				child = child.get_next_sibling();
			}
			if (views.size < 1) {
				return false;
			}
			if (forward) {
				var index = 0;
				if (this.match_child >= 0) {
					index = this.match_child;
				}
				while (index < views.size) {
					var view = views.get(index);
					var from_offset = 0;
					if (index == this.match_child) {
						from_offset = this.match_end;
					}
					Gtk.TextIter from_iter;
					Gtk.TextIter end_iter;
					view.buffer.get_iter_at_offset(out from_iter, from_offset);
					view.buffer.get_end_iter(out end_iter);
					var slice = view.buffer.get_text(from_iter, end_iter, false);
					GLib.MatchInfo info;
					if (!pattern.match(slice, 0, out info)) {
						index++;
						continue;
					}
					var b0 = 0;
					var b1 = 0;
					info.fetch_pos(0, out b0, out b1);
					var char_end = from_offset + slice.substring(0, b1).char_count();
					if (char_end <= from_offset) {
						this.match_child = index;
						this.match_end = from_offset + 1;
						index++;
						continue;
					}
					var char_start = from_offset + slice.substring(0, b0).char_count();
					this.match_child = index;
					this.match_end = char_end;
					var y = 0;
					var sibling = this.box.get_first_child();
					while (sibling != view) {
						y += sibling.get_height();
						sibling = sibling.get_next_sibling();
					}
					Gtk.TextIter at;
					view.buffer.get_iter_at_offset(out at, char_start);
					Gdk.Rectangle loc;
					view.get_iter_location(at, out loc);
					this.scroller.vadjustment.value = y + loc.y;
					return true;
				}
				return false;
			}
			var back = views.size - 1;
			if (this.match_child >= 0) {
				back = this.match_child;
			}
			while (back >= 0) {
				var view = views.get(back);
				var end_offset = view.buffer.get_char_count();
				if (back == this.match_child) {
					end_offset = this.match_end;
				}
				Gtk.TextIter start_iter;
				Gtk.TextIter from_iter;
				view.buffer.get_start_iter(out start_iter);
				view.buffer.get_iter_at_offset(out from_iter, end_offset);
				var slice = view.buffer.get_text(start_iter, from_iter, false);
				var best_b0 = -1;
				var best_b1 = -1;
				try {
					GLib.MatchInfo info;
					if (pattern.match(slice, 0, out info)) {
						do {
							var b0 = 0;
							var b1 = 0;
							info.fetch_pos(0, out b0, out b1);
							best_b0 = b0;
							best_b1 = b1;
						} while (info.next());
					}
				} catch (GLib.RegexError e) {
					return false;
				}
				if (best_b0 < 0) {
					back--;
					continue;
				}
				var char_start = slice.substring(0, best_b0).char_count();
				var char_end = slice.substring(0, best_b1).char_count();
				if (char_end <= 0) {
					back--;
					continue;
				}
				this.match_child = back;
				this.match_end = char_end;
				var y = 0;
				var sibling = this.box.get_first_child();
				while (sibling != view) {
					y += sibling.get_height();
					sibling = sibling.get_next_sibling();
				}
				Gtk.TextIter at;
				view.buffer.get_iter_at_offset(out at, char_start);
				Gdk.Rectangle loc;
				view.get_iter_location(at, out loc);
				this.scroller.vadjustment.value = y + loc.y;
				return true;
			}
			return false;
		}
	}
}
