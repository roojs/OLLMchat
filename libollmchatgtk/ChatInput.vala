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
	 * Chat composer: one expanding TextView with play on the right when
	 * single-line; play moves to {@link ChatBar} when text needs a second line.
	 *
	 * Height is owned by {@link scrolled} (TextView buffer.changed →
	 * content_height, capped by {@link ScrolledView.max_height}). ChatWidget
	 * wires send and footer play visibility via {@link expanded_changed}.
	 *
	 * == Usage Examples ==
	 *
	 * === Wire send and footer play ===
	 *
	 * {{{
	 *   var input = new OLLMchatGtk.ChatInput();
	 *   input.send_clicked.connect((text) => { … });
	 *   input.expanded_changed.connect((expanded) => {
	 *     chat_bar.composer_expanded = expanded;
	 *     chat_bar.action_button.visible = streaming || expanded;
	 *   });
	 * }}}
	 *
	 * @since 1.0
	 */
	public class ChatInput : Gtk.Box
	{
		private Gtk.Button inline_play;
		private Gtk.Label placeholder;
		public ScrolledView scrolled { get; private set; }
		private Gtk.TextView text_view;
		private Gtk.TextBuffer buffer;
		private bool is_expanded = false;
		private bool syncing = false;

		/** Emitted when the user submits (Ctrl+Enter or play) with the message text. */
		public signal void send_clicked(string text);

		/**
		 * Emitted when compact (single-line + side play) vs expanded
		 * (full-width; footer play) changes.
		 */
		public signal void expanded_changed(bool expanded);

		public ChatInput()
		{
			Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
			hexpand = true;
			vexpand = false;
			this.add_css_class("chat-composer");

			this.scrolled = new ScrolledView() {
				hexpand = true,
				vexpand = false
			};
			this.scrolled.add_css_class("chat-composer-entry");
			this.buffer = new Gtk.TextBuffer(null);
			this.text_view = new Gtk.TextView.with_buffer(this.buffer) {
				wrap_mode = Gtk.WrapMode.WORD_CHAR,
				hexpand = true,
				vexpand = false,
				valign = Gtk.Align.FILL,
				top_margin = 4,
				bottom_margin = 4,
				left_margin = 6,
				right_margin = 6,
				tooltip_text = "Ctrl+Enter to send, Enter adds new lines"
			};
			this.text_view.add_css_class("chat-composer-entry");
			this.text_view.add_css_class("chat-input-text");
			this.scrolled.set_child(this.text_view);

			this.placeholder = new Gtk.Label("Give me a task") {
				halign = Gtk.Align.START,
				valign = Gtk.Align.CENTER,
				margin_start = 6,
				can_target = false
			};
			this.placeholder.add_css_class("dim-label");
			this.placeholder.add_css_class("chat-composer-placeholder");

			var overlay = new Gtk.Overlay() {
				hexpand = true,
				vexpand = false
			};
			overlay.set_child(this.scrolled);
			overlay.add_overlay(this.placeholder);
			/* Placeholder must not inflate row height above ScrolledView content. */
			overlay.set_measure_overlay(this.placeholder, false);
			this.append(overlay);

			this.inline_play = new Gtk.Button.from_icon_name("media-playback-start-symbolic") {
				tooltip_text = "Send",
				valign = Gtk.Align.FILL
			};
			/* App blue #3584E4 — not suggested-action (follows desktop accent, often orange). */
			this.inline_play.add_css_class("chat-composer-send");
			this.inline_play.clicked.connect(() => {
				if (this.text().length > 0) {
					this.send_clicked(this.text());
				}
			});
			this.append(this.inline_play);
			this.scrolled.line_peer = this.inline_play;

			this.buffer.changed.connect(() => {
				if (this.syncing) {
					return;
				}
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				this.buffer.get_start_iter(out start_iter);
				this.buffer.get_end_iter(out end_iter);
				var text = this.buffer.get_text(start_iter, end_iter, false);
				this.placeholder.visible = this.buffer.get_char_count() == 0;
				/* Compact vs expanded: inline below (same as update_entry). */
				var want_expanded = text.contains("\n");
				if (!want_expanded && this.get_width() > 0) {
					var play_min = 0;
					var play_nat = 0;
					this.inline_play.measure(Gtk.Orientation.HORIZONTAL, -1,
						out play_min, out play_nat, null, null);
					var play_w = play_nat > 0 ? play_nat : play_min;
					var avail = this.get_width() - play_w
						- this.text_view.left_margin - this.text_view.right_margin;
					if (avail > 0) {
						var layout = this.text_view.create_pango_layout(text);
						var text_w = 0;
						var text_h = 0;
						layout.get_pixel_size(out text_w, out text_h);
						want_expanded = text_w > avail;
					}
				}
				if (want_expanded == this.is_expanded) {
					return;
				}
				this.is_expanded = want_expanded;
				this.inline_play.visible = !want_expanded;
				this.remove_css_class("is-expanded");
				if (want_expanded) {
					this.add_css_class("is-expanded");
				}
				this.expanded_changed(want_expanded);
			});

			var keys = new Gtk.EventControllerKey();
			keys.key_pressed.connect((keyval, keycode, state) => {
				if (keyval != Gdk.Key.Return && keyval != Gdk.Key.KP_Enter) {
					return false;
				}
				if ((state & Gdk.ModifierType.CONTROL_MASK) == 0) {
					return false;
				}
				if (this.text().length > 0) {
					this.send_clicked(this.text());
				}
				return true;
			});
			this.text_view.add_controller(keys);
		}

		/** Stripped composer text for send. */
		public string text()
		{
			Gtk.TextIter start_iter;
			Gtk.TextIter end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			return this.buffer.get_text(start_iter, end_iter, false).strip();
		}

		public void editable(bool editable)
		{
			this.text_view.editable = editable;
		}

		/**
		 * Apply text and sync compact/expanded chrome from the value.
		 * Recursion: returns if syncing; holds syncing across buffer writes.
		 * On programmatic set: Idle.add({@link focus_idle}).
		 * Does not steal focus on typing — only this path schedules focus_idle.
		 *
		 * @param text Full composer text
		 */
		public void update_entry(string text)
		{
			if (this.syncing) {
				return;
			}

			Gtk.TextIter cur_start;
			Gtk.TextIter cur_end;
			this.buffer.get_start_iter(out cur_start);
			this.buffer.get_end_iter(out cur_end);
			if (this.buffer.get_text(cur_start, cur_end, false) != text) {
				this.syncing = true;
				this.buffer.delete(ref cur_start, ref cur_end);
				this.buffer.insert(ref cur_start, text, -1);
				this.syncing = false;
			}
			this.placeholder.visible = text.length == 0;

			var want_expanded = text.contains("\n");
			if (!want_expanded && this.get_width() > 0) {
				var play_min = 0;
				var play_nat = 0;
				this.inline_play.measure(Gtk.Orientation.HORIZONTAL, -1,
					out play_min, out play_nat, null, null);
				var play_w = play_nat > 0 ? play_nat : play_min;
				var avail = this.get_width() - play_w
					- this.text_view.left_margin - this.text_view.right_margin;
				if (avail > 0) {
					var layout = this.text_view.create_pango_layout(text);
					var text_w = 0;
					var text_h = 0;
					layout.get_pixel_size(out text_w, out text_h);
					want_expanded = text_w > avail;
				}
			}
			if (want_expanded != this.is_expanded) {
				this.is_expanded = want_expanded;
				this.inline_play.visible = !want_expanded;
				this.remove_css_class("is-expanded");
				if (want_expanded) {
					this.add_css_class("is-expanded");
				}
				this.expanded_changed(want_expanded);
			}
			GLib.Idle.add(this.focus_idle);
		}

		/** Idle callback: wait until mapped, then focus TextView and caret at end. */
		public bool focus_idle()
		{
			if (!this.text_view.get_mapped()) {
				return true;
			}
			if (this.scrolled.get_width() <= 0) {
				return true;
			}
			this.text_view.grab_focus();
			Gtk.TextIter end_iter;
			this.buffer.get_end_iter(out end_iter);
			this.buffer.place_cursor(end_iter);
			this.text_view.scroll_to_mark(this.buffer.get_insert(), 0.0, true, 0.0, 1.0);
			this.scrolled.queue_fit();
			return false;
		}
	}
}
