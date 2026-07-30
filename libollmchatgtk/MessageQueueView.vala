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
	 * Pending mid-run queue strip: {@link Gtk.ColumnView} over a
	 * {@link OLLMchat.MessageQueue} (text | pencil | up/urgent).
	 *
	 * Construct with the parent {@link ChatWidget}. Owns one MessageQueue for
	 * life (ColumnView model is never swapped). Callers set ''queue.items''
	 * (and ''visible'') directly. Clicks: ColumnView
	 * {@link Gtk.GestureClick.released} → {@link on_click} (pick/walk). Pencil
	 * merges into the composer; up sets ''role = "urgent"'' (append-only — no
	 * reorder).
	 *
	 * == Example ==
	 *
	 * {{{
	 *   var strip = new MessageQueueView(chat_widget);
	 *   chat_widget.above_input.append(strip);
	 *   strip.queue.items = session.queued_messages;
	 *   strip.visible = true;
	 * }}}
	 */
	public class MessageQueueView : Gtk.Box
	{
		private weak ChatWidget chat_widget;
		private Gtk.SingleSelection selection;
		private Gtk.ColumnView column_view;
		private Gtk.GestureClick click_gesture;
		public OLLMchat.MessageQueue queue { get; private set; }

		/**
		 * @param chat_widget parent chat (composer / queue actions)
		 */
		public MessageQueueView(ChatWidget chat_widget)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.chat_widget = chat_widget;
			this.add_css_class("oc-message-queue");
			this.visible = false;

			this.queue = new OLLMchat.MessageQueue(new Gee.ArrayList<OLLMchat.Message>());
			this.selection = new Gtk.SingleSelection(this.queue);
			this.column_view = new Gtk.ColumnView(this.selection) {
				hexpand = true,
				vexpand = false,
				show_row_separators = true,
				single_click_activate = false
			};

			var text_factory = new Gtk.SignalListItemFactory();
			text_factory.setup.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				li.activatable = false;
				li.set_child(new Gtk.Label("") {
					halign = Gtk.Align.START,
					hexpand = true,
					xalign = 0,
					ellipsize = Pango.EllipsizeMode.END,
					single_line_mode = true
				});
			});
			text_factory.bind.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				var label = (Gtk.Label) li.child;
				var msg = (OLLMchat.Message) li.item;
				label.label = msg.content;
			});

			var pencil_factory = new Gtk.SignalListItemFactory();
			pencil_factory.setup.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				li.activatable = false;
				var image = new Gtk.Image.from_icon_name("document-edit-symbolic");
				image.set_data("queue-action", "pencil");
				li.set_child(image);
			});
			pencil_factory.bind.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				var image = (Gtk.Image) li.child;
				image.set_data("queue-msg", (OLLMchat.Message) li.item);
				image.set_data("queue-action", "pencil");
			});

			var up_factory = new Gtk.SignalListItemFactory();
			up_factory.setup.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				li.activatable = false;
				var image = new Gtk.Image.from_icon_name("go-up-symbolic");
				image.set_data("queue-action", "up");
				li.set_child(image);
			});
			up_factory.bind.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				var image = (Gtk.Image) li.child;
				var msg = (OLLMchat.Message) li.item;
				image.set_data("queue-msg", msg);
				image.set_data("queue-action", "up");
				if (msg.role == "urgent") {
					image.icon_name = "emblem-important-symbolic";
					image.tooltip_text = "Urgent";
					return;
				}
				image.icon_name = "go-up-symbolic";
				image.tooltip_text = "Make urgent";
			});

			var text_column = new Gtk.ColumnViewColumn("Queued", text_factory);
			text_column.expand = true;
			this.column_view.append_column(text_column);
			var pencil_column = new Gtk.ColumnViewColumn(null, pencil_factory);
			pencil_column.fixed_width = 40;
			pencil_column.resizable = false;
			this.column_view.append_column(pencil_column);
			var up_column = new Gtk.ColumnViewColumn(null, up_factory);
			up_column.fixed_width = 40;
			up_column.resizable = false;
			this.column_view.append_column(up_column);

			this.click_gesture = new Gtk.GestureClick();
			this.column_view.add_controller(this.click_gesture);
			this.click_gesture.released.connect(this.on_click);

			var scrolled = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = false,
				has_frame = true
			};
			scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
			scrolled.set_max_content_height(160);
			scrolled.set_propagate_natural_height(true);
			scrolled.set_child(this.column_view);
			this.append(scrolled);
		}

		/**
		 * ColumnView click: pick under pointer, walk parents until
		 * ''queue-action'' / ''queue-msg'' — then up, else pencil (default).
		 *
		 * @param n_press click count
		 * @param x pointer x in ColumnView
		 * @param y pointer y in ColumnView
		 */
		private void on_click(int n_press, double x, double y)
		{
			string? action = null;
			OLLMchat.Message? msg = null;
			var picked = this.column_view.pick((float) x, (float) y, Gtk.PickFlags.DEFAULT);
			while (picked != null && !(picked is Gtk.ColumnView)) {
				action = ((GLib.Object) picked).get_data<string>("queue-action");
				msg = ((GLib.Object) picked).get_data<OLLMchat.Message>("queue-msg");
				if (action != null && msg != null) {
					break;
				}
				picked = picked.get_parent();
			}
			if (action == null || msg == null) {
				return;
			}
			if (action == "up") {
				msg.role = "urgent";
				return;
			}
			this.queue.remove(msg);
			var existing = this.chat_widget.chat_input.text();
			if (existing.length == 0) {
				this.chat_widget.chat_input.update_entry(msg.content);
				return;
			}
			this.chat_widget.chat_input.update_entry(existing + "\n" + msg.content);
		}
	}
}
