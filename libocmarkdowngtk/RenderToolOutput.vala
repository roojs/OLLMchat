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
	/**
	 * Shell listing for a bash fence. The command is the title.
	 *
	 * Stop emits {@link Render.stop_clicked}. Chat connects that
	 * signal when the renderer is created.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var frame = new RenderToolOutput(renderer,
	 *     "bash.oc-frame-info ls", true);
	 * frame.output("a.txt\n");
	 * }}}
	 */
	public class RenderToolOutput : Gtk.Frame
	{
		/**
		 * Renderer that owns {@link Render.stop_clicked}.
		 */
		public Render renderer { get; construct; }
		/**
		 * Fence info string. The title after the classes is the command.
		 */
		public string language_id { get; construct; }
		/**
		 * True while chunks are still arriving. Shows Stop.
		 */
		public bool is_streaming { get; construct; }
		/**
		 * Status line. Live sets this from the start notification.
		 * ''Running command as root (sudo)'' adds the ''root'' class.
		 */
		public string status { get; set; default = ""; }

		private Gtk.Button stop;
		private Gtk.Button collapse;
		private Gtk.Revealer body;
		private Gtk.ScrolledWindow scroll;
		private Gtk.TextView view;
		private Gtk.Label status_label;

		/**
		 * @param renderer parent renderer
		 * @param language_id fence info string
		 * @param is_streaming true while output is still arriving
		 */
		public RenderToolOutput(Render renderer, string language_id, bool is_streaming)
		{
			Object(renderer: renderer, language_id: language_id, is_streaming: is_streaming);
		}

		construct
		{
			var info = this.language_id.strip();
			var tokens = info.split(" ", 2);
			var language = tokens.length > 0 ? tokens[0] : "";
			var command = tokens.length > 1 ? tokens[1].strip() : "";
			var lang_parts = language.split(".");
			var frame_theme_classes = lang_parts.length > 1 ?
				lang_parts[1:lang_parts.length] : new string[0];
			var collapsed = "collapsed" in frame_theme_classes;
			string[] frame_classes = { "tool-frame", "oc-frame" };
			foreach (var c in frame_theme_classes) {
				if (c == "collapsed") {
					continue;
				}
				frame_classes += c;
			}
			this.css_classes = frame_classes;
			var header = new Gtk.Label("") {
				halign = Gtk.Align.START,
				ellipsize = Pango.EllipsizeMode.END,
				use_markup = true,
				hexpand = true,
				css_classes = { "command-preview" },
				tooltip_text = command,
				label = "<b>" + GLib.Markup.escape_text(command) + "</b>"
			};
			this.status_label = new Gtk.Label("") {
				halign = Gtk.Align.START,
				wrap = true
			};
			this.notify["status"].connect(() => {
				this.status_label.label = this.status;
				if (this.status == "Running command as root (sudo)") {
					this.add_css_class("root");
				}
			});
			this.body = new Gtk.Revealer() {
				reveal_child = !collapsed,
				hexpand = true
			};
			this.collapse = new Gtk.Button() {
				icon_name = collapsed ? "go-next-symbolic" : "go-up-symbolic",
				tooltip_text = collapsed ? "Expand" : "Collapse",
				valign = Gtk.Align.CENTER
			};
			this.collapse.clicked.connect(() => {
				this.body.reveal_child = !this.body.reveal_child;
				this.collapse.icon_name = this.body.reveal_child
					? "go-up-symbolic" : "go-next-symbolic";
				this.collapse.tooltip_text = this.body.reveal_child
					? "Collapse" : "Expand";
			});
			this.stop = new Gtk.Button.with_label("Stop") {
				valign = Gtk.Align.CENTER,
				visible = this.is_streaming,
				css_classes = { "destructive-action" }
			};
			this.stop.clicked.connect(() => {
				this.stop.visible = false;
				this.renderer.stop_clicked();
			});
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				css_classes = { "oc-frame-header" }
			};
			row.append(this.collapse);
			row.append(header);
			row.append(this.stop);
			this.view = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.NONE,
				monospace = true,
				hexpand = true,
				css_classes = { "tool-output" }
			};
			this.view.buffer.text = command + "\n";
			this.scroll = new Gtk.ScrolledWindow() {
				min_content_height = 200,
				max_content_height = 480,
				propagate_natural_height = true,
				propagate_natural_width = false,
				hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				hexpand = true,
				vexpand = false,
				margin_top = 4,
				margin_bottom = 4,
				margin_start = 4,
				margin_end = 4,
				css_classes = { "tool-output" }
			};
			this.scroll.set_child(this.view);
			this.body.set_child(this.scroll);
			var col = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
			col.append(row);
			col.append(this.status_label);
			col.append(this.body);
			this.set_child(col);
		}

		/**
		 * Append a chunk. Cap at 2000 lines. Stick to the bottom
		 * only when the view is already there.
		 *
		 * @param chunk text still arriving, or the restored tail
		 */
		public void output(string chunk)
		{
			var adj = this.scroll.get_vadjustment();
			var stick = adj.value >= adj.upper - adj.page_size - 8.0;
			Gtk.TextIter end;
			this.view.buffer.get_end_iter(out end);
			this.view.buffer.insert(ref end, chunk, -1);
			var extra = this.view.buffer.get_line_count() - 2000;
			if (extra > 0) {
				Gtk.TextIter start;
				Gtk.TextIter cut;
				this.view.buffer.get_start_iter(out start);
				this.view.buffer.get_iter_at_line(out cut, extra);
				this.view.buffer.delete(ref start, ref cut);
			}
			if (stick) {
				adj.value = adj.upper - adj.page_size;
			}
		}

		/**
		 * Run finished. Hide Stop and collapse. Leave the frame.
		 */
		public void close()
		{
			this.stop.visible = false;
			this.body.reveal_child = false;
			this.collapse.icon_name = "go-next-symbolic";
			this.collapse.tooltip_text = "Expand";
		}
	}
}
