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
	 * Chat text area: multiline input only. ChatWidget places this in the paned
	 * and wires send_clicked / get_text_to_send with ChatBar.
	 *
	 * @since 1.0
	 */
	public class ChatInput : Gtk.Box
	{
		private Gtk.ScrolledWindow scrolled;
		private Gtk.TextView text_view;
		private Gtk.TextBuffer buffer;

		/** Emitted when the user submits (Ctrl+Enter) with the message text. */
		public signal void send_clicked(string text);

		public ChatInput()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			hexpand = true;
			vexpand = true;
			set_size_request(-1, 60);

			this.scrolled = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = true,
				hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				vscrollbar_policy = Gtk.PolicyType.AUTOMATIC
			};
			this.scrolled.set_size_request(-1, 60);

			this.buffer = new Gtk.TextBuffer(null);
			this.text_view = new Gtk.TextView.with_buffer(this.buffer) {
				wrap_mode = Gtk.WrapMode.WORD,
				margin_start = 10,
				margin_end = 10,
				margin_top = 5,
				margin_bottom = 5,
				tooltip_text = "Ctrl+Enter to send, Enter adds new lines"
			};
			this.text_view.set_size_request(-1, 60);
			this.text_view.add_css_class("chat-input-text");
			this.scrolled.set_child(this.text_view);
			this.append(this.scrolled);

			var controller = new Gtk.EventControllerKey();
			controller.key_pressed.connect(this.on_key_pressed);
			this.text_view.add_controller(controller);
		}

		public string default_message
		{
			get { return ""; }
			set { this.buffer.set_text(value, -1); }
		}

		/** Returns current buffer content, stripped; empty if nothing to send. */
		public string get_text_to_send()
		{
			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			return this.buffer.get_text(start_iter, end_iter, false).strip();
		}

		public void clear_input()
		{
			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			this.buffer.delete(ref start_iter, ref end_iter);
		}

		public void set_default_text(string text)
		{
			Gtk.TextIter start_iter, end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			this.buffer.delete(ref start_iter, ref end_iter);
			this.buffer.insert(ref start_iter, text, -1);
		}

		/** Set text area editable/sensitive (e.g. false when streaming). */
		public void set_input_editable(bool editable)
		{
			this.text_view.editable = editable;
		}

		public void set_input_sensitive(bool sensitive)
		{
			this.text_view.sensitive = sensitive;
		}

		private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state)
		{
			if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
				if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
					var text = this.get_text_to_send();
					if (text.length > 0) {
						this.send_clicked(text);
					}
					return true;
				}
				return false;
			}
			return false;
		}
	}
}
