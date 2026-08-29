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

namespace OLLMchatGtk
{
	/**
	 * Live ''run_command'' pane. One instance per run, added to the chat
	 * stream like any other frame. Stays after the command ends.
	 *
	 * @since 1.0
	 */
	public class ToolOutput : Gtk.Frame
	{
		private Gtk.Button stop;
		private Gtk.Button collapse;
		private Gtk.Revealer body;
		private Gtk.ScrolledWindow scroll;
		private Gtk.TextView view;
		private OLLMchat.History.Manager manager;

		/**
		 * @param manager History manager (Stop uses session.agent.active_tools).
		 * @param command Command line from ''client.run_tool.start'' message.
		 * @param action Status line from ''client.run_tool.start'' action.
		 */
		public ToolOutput(OLLMchat.History.Manager manager, string command, string action)
		{
			this.manager = manager;
			this.add_css_class("tool-frame");
			if (action == "Running command as root (sudo)") {
				this.add_css_class("root");
			}
			var header = new Gtk.Label("") {
				halign = Gtk.Align.START,
				ellipsize = Pango.EllipsizeMode.END,
				use_markup = true,
				hexpand = true
			};
			header.add_css_class("command-preview");
			header.tooltip_text = command;
			header.label = "<b>" + GLib.Markup.escape_text(command) + "</b>";
			var status = new Gtk.Label(action) {
				halign = Gtk.Align.START,
				wrap = true
			};
			this.body = new Gtk.Revealer() {
				reveal_child = true,
				hexpand = true
			};
			this.collapse = new Gtk.Button() {
				icon_name = "go-up-symbolic",
				tooltip_text = "Collapse",
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
				valign = Gtk.Align.CENTER
			};
			this.stop.add_css_class("destructive-action");
			this.stop.clicked.connect(() => {
				this.stop.visible = false;
				foreach (var req in this.manager.session.agent.active_tools.values) {
					req.stop();
				}
			});
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			row.append(this.collapse);
			row.append(header);
			row.append(this.stop);
			this.view = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.CHAR,
				monospace = true
			};
			this.view.add_css_class("tool-output");
			this.scroll = new Gtk.ScrolledWindow() {
				min_content_height = 80,
				max_content_height = 280,
				propagate_natural_height = true,
				hexpand = true,
				vexpand = false
			};
			this.scroll.add_css_class("tool-output");
			this.scroll.set_child(this.view);
			this.body.set_child(this.scroll);
			var col = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
			col.append(row);
			col.append(status);
			col.append(this.body);
			this.set_child(col);
		}

		/**
		 * Append a chunk. Cap at 2000 lines. Stick to bottom only if already there.
		 *
		 * @param chunk Text from ''client.run_tool.output'' message.
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
		 * Run finished. Hide Stop and collapse. Leave this frame in the stream.
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
