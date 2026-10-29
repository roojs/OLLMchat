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
	 * Owns one editor buffer and the parts last applied to it.
	 *
	 * Construct it with the editor buffer for the current view.
	 * {@link SourceView} holds that instance. {@link update} returns a
	 * second instance whose {@link parts} include unchanged runs.
	 * {@link apply} writes that instance into this buffer. The two
	 * instances are not swapped.
	 *
	 * == Example ==
	 *
	 * === Empty part list ===
	 *
	 * {{{
	 * var view = new OLLMcoder.ChangeView(buffer);
	 * var hunks = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
	 * var next = view.update(file, hunks);
	 * view.apply(next);
	 * }}}
	 */
	public class ChangeView : Object
	{
		/**
		 * Editor buffer from the constructor. Null on the
		 * secondary instance. Not allocated here.
		 */
		private GtkSource.Buffer? buffer;

		/**
		 * True when this instance holds no parts.
		 * A new instance starts empty. That is the flag.
		 */
		public bool empty = true;

		/**
		 * Whole file for this view. Unchanged runs and hunks.
		 */
		public Gee.ArrayList<OLLMfiles.FileDiffPart> parts {
			get; set; default = new Gee.ArrayList<OLLMfiles.FileDiffPart>();
		}

		/**
		 * Current or secondary change view.
		 *
		 * The secondary view passes null. The current view passes the
		 * editor buffer. That buffer receives ''diff-add'' and
		 * ''diff-remove'' when the tag table lacks them.
		 *
		 * @param buffer editor buffer, or null for the secondary view
		 */
		public ChangeView(GtkSource.Buffer? buffer)
		{
			this.buffer = buffer;
			if (this.buffer == null) {
				return;
			}
			if (this.buffer.tag_table.lookup("diff-add") != null) {
				return;
			}
			this.buffer.tag_table.add(new Gtk.TextTag("diff-add") {
				paragraph_background_rgba = Gdk.RGBA() {
					red = 0.75f,
					green = 0.95f,
					blue = 0.75f,
					alpha = 1.0f
				}
			});
			this.buffer.tag_table.add(new Gtk.TextTag("diff-remove") {
				paragraph_background_rgba = Gdk.RGBA() {
					red = 0.95f,
					green = 0.75f,
					blue = 0.75f,
					alpha = 1.0f
				},
				editable = false
			});
		}

		/**
		 * Build a secondary change view from the file and the
		 * incoming hunks. Does not call {@link apply}.
		 * Gaps between hunks become unchanged parts. An empty
		 * hunk list still builds those parts from the file.
		 *
		 * @param file file text for the unchanged runs
		 * @param parts incoming hunks, or an empty list
		 * @return the secondary change view
		 */
		public ChangeView update(OLLMfiles.File file, Gee.ArrayList<OLLMfiles.FileDiffPart> parts)
		{
			var next = new ChangeView(null);
			var lines = file.buffer.get_text().split("\n");
			var new_at = 1;
			var old_at = 1;
			for (var i = 0; i <= parts.size; i++) {
				var new_end = lines.length;
				var old_end = old_at + lines.length - new_at;
				if (i < parts.size) {
					var inc = parts.get(i);
					new_end = inc.new_line_start - 1;
					old_end = inc.old_line_start - 1;
				}
				if (new_end > lines.length) {
					new_end = lines.length;
				}
				if (new_at <= new_end) {
					var gap = new OLLMfiles.FileDiffPart() {
						new_line_start = new_at,
						new_line_end = new_end,
						old_line_start = old_at,
						old_line_end = old_end,
						hunk_add = string.joinv("\n", lines[new_at - 1:new_end]),
						unchanged = true
					};
					gap.update_sum();
					next.parts.add(gap);
					new_at = gap.new_line_end + 1;
					if (gap.old_line_end >= gap.old_line_start) {
						old_at = gap.old_line_end + 1;
					}
				}
				if (i == parts.size) {
					break;
				}
				var inc = parts.get(i);
				inc.update_sum();
				next.parts.add(inc);
				if (inc.new_line_end >= inc.new_line_start) {
					new_at = inc.new_line_end + 1;
				}
				if (inc.old_line_end >= inc.old_line_start) {
					old_at = inc.old_line_end + 1;
				}
			}
			next.empty = next.parts.size == 0;
			return next;
		}

		/**
		 * Write {@link next} into this buffer.
		 *
		 * A filled {@link parts} list calls {@link apply_parts} and
		 * returns. An empty list writes the secondary view with one
		 * ''set_text'', then paints green and red on the hunk spans.
		 * {@link update} does not call this. The caller redraws the
		 * strip with ''ReviewBar.update_diff''.
		 *
		 * @param next secondary change view from {@link update}
		 */
		public void apply(ChangeView next)
		{
			if (this.parts.size > 0) {
				this.apply_parts(next);
				return;
			}
			var add_tag = this.buffer.tag_table.lookup("diff-add");
			var remove_tag = this.buffer.tag_table.lookup("diff-remove");
			string[] blobs = {};
			for (var n = 0; n < next.parts.size; n++) {
				var part = next.parts.get(n);
				var new_n = part.new_line_end < part.new_line_start ? 0 : part.new_line_end - part.new_line_start + 1;
				var old_n = part.old_line_end < part.old_line_start ? 0 : part.old_line_end - part.old_line_start + 1;
				if (part.unchanged) {
					if (new_n > 0) {
						blobs += part.hunk_add;
					}
					continue;
				}
				if (old_n > 0) {
					blobs += part.hunk_remove;
				}
				if (new_n > 0) {
					blobs += part.hunk_add;
				}
			}
			this.buffer.set_text(string.joinv("\n", blobs), -1);
			var at = 0;
			for (var n = 0; n < next.parts.size; n++) {
				var part = next.parts.get(n);
				var new_n = part.new_line_end < part.new_line_start ? 0 : part.new_line_end - part.new_line_start + 1;
				var old_n = part.old_line_end < part.old_line_start ? 0 : part.old_line_end - part.old_line_start + 1;
				if (part.unchanged) {
					at += new_n;
					continue;
				}
				if (old_n > 0) {
					Gtk.TextIter tag_start;
					Gtk.TextIter tag_end;
					this.buffer.get_iter_at_line(out tag_start, at);
					if (!this.buffer.get_iter_at_line(out tag_end, at + old_n)) {
						this.buffer.get_end_iter(out tag_end);
					}
					this.buffer.apply_tag(remove_tag, tag_start, tag_end);
					at += old_n;
				}
				if (new_n > 0) {
					Gtk.TextIter tag_start;
					Gtk.TextIter tag_end;
					this.buffer.get_iter_at_line(out tag_start, at);
					if (!this.buffer.get_iter_at_line(out tag_end, at + new_n)) {
						this.buffer.get_end_iter(out tag_end);
					}
					this.buffer.apply_tag(add_tag, tag_start, tag_end);
					at += new_n;
				}
			}
			this.parts.clear();
			this.parts.add_all(next.parts);
			this.empty = this.parts.size == 0;
		}

		/**
		 * Write {@link next} by the differentials.
		 *
		 * {@link OLLMfiles.FileDiffPart.compare} 2 or 3 leaves the
		 * stretch. 1 replaces it. 0 takes out a piece only in this
		 * view or puts one in from {@link next}.
		 * {@link apply} calls this when {@link parts} is filled.
		 *
		 * @param next secondary change view from {@link update}
		 */
		private void apply_parts(ChangeView next)
		{
			var add_tag = this.buffer.tag_table.lookup("diff-add");
			var remove_tag = this.buffer.tag_table.lookup("diff-remove");
			var i = 0;
			var j = 0;
			var at = 0;
			while (i < this.parts.size || j < next.parts.size) {
				var put = i >= this.parts.size;
				var take = j >= next.parts.size;
				if (i < this.parts.size && j < next.parts.size) {
					var cur = this.parts.get(i);
					var inc = next.parts.get(j);
					var rel = cur.compare(inc);
					if (rel == 2 || rel == 3) {
						at += cur.new_line_end < cur.new_line_start ? 0 : cur.new_line_end - cur.new_line_start + 1;
						if (!cur.unchanged) {
							at += cur.old_line_end < cur.old_line_start ? 0 : cur.old_line_end - cur.old_line_start + 1;
						}
						i++;
						j++;
						continue;
					}
					if (rel == 1) {
						put = true;
						take = true;
					}
					if (rel == 0) {
						var later_next = j + 1;
						while (later_next < next.parts.size) {
							var ahead = cur.compare(next.parts.get(later_next));
							if (ahead == 2 || ahead == 3) {
								break;
							}
							later_next++;
						}
						var later_cur = i + 1;
						while (later_cur < this.parts.size) {
							var ahead = inc.compare(this.parts.get(later_cur));
							if (ahead == 2 || ahead == 3) {
								break;
							}
							later_cur++;
						}
						var found_next = later_next < next.parts.size;
						var found_cur = later_cur < this.parts.size;
						put = !found_cur || (found_next && later_next - j <= later_cur - i);
						take = !found_next || (found_cur && later_cur - i < later_next - j);
					}
				}
				if (take) {
					var cur = this.parts.get(i);
					var old_n = cur.old_line_end < cur.old_line_start ? 0 : cur.old_line_end - cur.old_line_start + 1;
					var new_n = cur.new_line_end < cur.new_line_start ? 0 : cur.new_line_end - cur.new_line_start + 1;
					var span = new_n;
					if (!cur.unchanged) {
						span = old_n + new_n;
					}
					if (span > 0) {
						Gtk.TextIter start_iter;
						if (this.buffer.get_iter_at_line(out start_iter, at)) {
							Gtk.TextIter end_iter;
							if (!this.buffer.get_iter_at_line(out end_iter, at + span)) {
								this.buffer.get_end_iter(out end_iter);
							}
							this.buffer.delete(ref start_iter, ref end_iter);
						}
					}
					i++;
				}
				if (!put) {
					continue;
				}
				var inc = next.parts.get(j);
				var old_n = inc.old_line_end < inc.old_line_start ? 0 : inc.old_line_end - inc.old_line_start + 1;
				var new_n = inc.new_line_end < inc.new_line_start ? 0 : inc.new_line_end - inc.new_line_start + 1;
				var text = inc.hunk_add;
				if (!inc.unchanged && inc.hunk_remove != "") {
					text = inc.hunk_add == "" ? inc.hunk_remove : inc.hunk_remove + "\n" + inc.hunk_add;
				}
				var span = new_n;
				if (!inc.unchanged) {
					span = old_n + new_n;
				}
				Gtk.TextIter at_iter;
				var at_end = !this.buffer.get_iter_at_line(out at_iter, at);
				if (at_end) {
					this.buffer.get_end_iter(out at_iter);
				}
				if (text == "" && span > 0) {
					var blanks = span;
					if (at_end) {
						blanks = span - 1;
					}
					text = string.nfill(blanks, '\n');
				}
				if (text != "" && !at_end && !text.has_suffix("\n")) {
					text = text + "\n";
				}
				if (text != "") {
					this.buffer.insert(ref at_iter, text, -1);
				}
				if (!inc.unchanged && old_n > 0) {
					Gtk.TextIter tag_start;
					Gtk.TextIter tag_end;
					this.buffer.get_iter_at_line(out tag_start, at);
					if (!this.buffer.get_iter_at_line(out tag_end, at + old_n)) {
						this.buffer.get_end_iter(out tag_end);
					}
					this.buffer.apply_tag(remove_tag, tag_start, tag_end);
				}
				if (!inc.unchanged && new_n > 0) {
					Gtk.TextIter tag_start;
					Gtk.TextIter tag_end;
					this.buffer.get_iter_at_line(out tag_start, at + old_n);
					if (!this.buffer.get_iter_at_line(out tag_end, at + old_n + new_n)) {
						this.buffer.get_end_iter(out tag_end);
					}
					this.buffer.apply_tag(add_tag, tag_start, tag_end);
				}
				at += span;
				j++;
			}
			this.parts.clear();
			this.parts.add_all(next.parts);
			this.empty = this.parts.size == 0;
		}
	}
}
