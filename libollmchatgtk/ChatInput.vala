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
	 * Chat composer: compact single-line entry + expanded multiline TextView.
	 * Flips visibility (does not resize one widget). ChatWidget wires send / ChatBar.
	 *
	 * @since 1.0
	 */
	public class ChatInput : Gtk.Box
	{
		private Gtk.Box compact_row;
		private Gtk.Entry compact_entry;
		private Gtk.Button compact_play;
		private Gtk.ScrolledWindow scrolled;
		private Gtk.TextView text_view;
		private Gtk.TextBuffer buffer;
		private bool is_expanded = false;
		private bool syncing = false;
		/** Cap for expanded scrolled height; ChatWidget sets from chat_view allocation / 2. */
		public int expanded_max_height { get; set; default = 0; }

		/** Emitted when the user submits (Ctrl+Enter or play) with the message text. */
		public signal void send_clicked(string text);

		/** Emitted when compact/expanded visibility flips. */
		public signal void expanded_changed(bool expanded);

		public ChatInput()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			hexpand = true;
			vexpand = false;
			this.add_css_class("chat-composer");

			this.compact_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				vexpand = false
			};
			this.compact_row.add_css_class("chat-composer-compact");
			/* Adwaita linked Entry+Button; focus ring via CSS :focus-within on the row. */
			this.compact_row.add_css_class("linked");
			this.compact_entry = new Gtk.Entry() {
				hexpand = true,
				placeholder_text = "Give me a task",
				tooltip_text = "Ctrl+Enter to send, Enter adds new lines"
			};
			this.compact_entry.add_css_class("chat-composer-entry");
			this.compact_play = new Gtk.Button.from_icon_name("media-playback-start-symbolic") {
				tooltip_text = "Send"
			};
			/* App blue #3584E4 — not suggested-action (follows desktop accent, often orange). */
			this.compact_play.add_css_class("chat-composer-send");
			this.compact_play.clicked.connect(() => {
				if (this.text().length > 0) {
					this.send_clicked(this.text());
				}
			});
			this.compact_row.append(this.compact_entry);
			this.compact_row.append(this.compact_play);
			this.append(this.compact_row);

			this.scrolled = new Gtk.ScrolledWindow() {
				hexpand = true,
				vexpand = false,
				visible = false,
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				propagate_natural_height = true
			};
			this.scrolled.add_css_class("chat-composer-expanded");
			this.buffer = new Gtk.TextBuffer(null);
			this.text_view = new Gtk.TextView.with_buffer(this.buffer) {
				wrap_mode = Gtk.WrapMode.WORD_CHAR,
				hexpand = true,
				vexpand = false,
				valign = Gtk.Align.START,
				top_margin = 4,
				bottom_margin = 4,
				left_margin = 6,
				right_margin = 6,
				tooltip_text = "Ctrl+Enter to send, Enter adds new lines"
			};
			this.text_view.add_css_class("chat-composer-entry");
			this.text_view.add_css_class("chat-input-text");
			this.scrolled.set_child(this.text_view);
			this.append(this.scrolled);

			/* Mode from value (paste/type/programmatic) — not from key handlers. */
			this.compact_entry.changed.connect(() => {
				if (this.syncing) {
					return;
				}
				this.update_entry(this.compact_entry.text);
			});
			this.buffer.changed.connect(() => {
				if (this.syncing) {
					return;
				}
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				this.buffer.get_start_iter(out start_iter);
				this.buffer.get_end_iter(out end_iter);
				var text = this.buffer.get_text(start_iter, end_iter, false);
				this.update_entry(text);
				if (!this.is_expanded) {
					return;
				}
				/* B5: height from Pango (content), not get_line_yrange (stale until validate idle). */
				var content_width = this.scrolled.get_allocated_width() - this.text_view.left_margin - this.text_view.right_margin;
				if (content_width <= 0) {
					return;
				}
				var layout = this.text_view.create_pango_layout(text);
				layout.set_width(content_width * Pango.SCALE);
				layout.set_wrap(Pango.WrapMode.WORD_CHAR);
				var layout_w = 0;
				var layout_h = 0;
				layout.get_pixel_size(out layout_w, out layout_h);
				var h = layout_h + this.text_view.top_margin + this.text_view.bottom_margin;
				GLib.debug("composer pango h=%d layout_h=%d width=%d max=%d",
					h, layout_h, content_width, this.expanded_max_height);
				if (this.expanded_max_height > 0 && h > this.expanded_max_height) {
					this.scrolled.min_content_height = this.expanded_max_height;
					this.scrolled.max_content_height = this.expanded_max_height;
				} else {
					this.scrolled.min_content_height = h;
					this.scrolled.max_content_height = h;
				}
				this.scrolled.queue_resize();
			});

			var compact_keys = new Gtk.EventControllerKey();
			compact_keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
			compact_keys.key_pressed.connect((keyval, keycode, state) => {
				if (keyval != Gdk.Key.Return && keyval != Gdk.Key.KP_Enter) {
					return false;
				}
				if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
					if (this.text().length > 0) {
						this.send_clicked(this.text());
					}
					return true;
				}
				/* Entry cannot store \n — write the new value; mode decided in update_entry. */
				this.update_entry(this.compact_entry.text + "\n");
				return true;
			});
			this.compact_entry.add_controller(compact_keys);

			var expanded_keys = new Gtk.EventControllerKey();
			expanded_keys.key_pressed.connect((keyval, keycode, state) => {
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
			this.text_view.add_controller(expanded_keys);
		}

		/** Stripped composer text for send. */
		public string text()
		{
			if (!this.is_expanded) {
				return this.compact_entry.text.strip();
			}
			Gtk.TextIter start_iter;
			Gtk.TextIter end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			return this.buffer.get_text(start_iter, end_iter, false).strip();
		}

		public void editable(bool editable)
		{
			this.compact_entry.editable = editable;
			this.text_view.editable = editable;
		}

		/**
		 * Apply text; stay or flip compact/expanded from the value.
		 * Recursion: returns if syncing; holds syncing across all widget writes.
		 * On mode change: Idle.add({@link focus_idle}).
		 *
		 * @param text Full composer text
		 */
		public void update_entry(string text)
		{
			if (this.syncing) {
				return;
			}

			var want_expanded = text.contains("\n");
			if (!want_expanded && this.compact_entry.get_allocated_width() > 0) {
				/* Measure only — do not assign Entry.text (fights user action / undo). */
				var layout = this.compact_entry.create_pango_layout(text);
				Pango.Rectangle ink;
				Pango.Rectangle logical;
				layout.get_pixel_extents(out ink, out logical);
				want_expanded = logical.width > this.compact_entry.get_allocated_width();
			}

			if (want_expanded && this.is_expanded) {
				Gtk.TextIter cur_start;
				Gtk.TextIter cur_end;
				this.buffer.get_start_iter(out cur_start);
				this.buffer.get_end_iter(out cur_end);
				if (this.buffer.get_text(cur_start, cur_end, false) == text) {
					return;
				}
				this.syncing = true;
				this.buffer.delete(ref cur_start, ref cur_end);
				this.buffer.insert(ref cur_start, text, -1);
				this.syncing = false;
				GLib.Idle.add(this.focus_idle);
				return;
			}
			if (!want_expanded && !this.is_expanded) {
				if (this.compact_entry.text == text) {
					return;
				}
				this.syncing = true;
				this.compact_entry.text = text;
				this.syncing = false;
				return;
			}

			if (want_expanded) {
				this.syncing = true;
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				this.buffer.get_start_iter(out start_iter);
				this.buffer.get_end_iter(out end_iter);
				this.buffer.delete(ref start_iter, ref end_iter);
				this.buffer.insert(ref start_iter, text, -1);
				this.compact_row.visible = false;
				this.scrolled.visible = true;
				this.is_expanded = true;
				this.syncing = false;
				this.expanded_changed(true);
				GLib.Idle.add(this.focus_idle);
				return;
			}

			this.syncing = true;
			this.compact_entry.text = text;
			Gtk.TextIter start_iter;
			Gtk.TextIter end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			this.buffer.delete(ref start_iter, ref end_iter);
			this.scrolled.visible = false;
			this.compact_row.visible = true;
			this.is_expanded = false;
			this.syncing = false;
			this.expanded_changed(false);
			GLib.Idle.add(this.focus_idle);
		}

		/** Idle callback: wait until mapped, then focus active control and caret at end. */
		public bool focus_idle()
		{
			if (this.is_expanded) {
				if (!this.text_view.get_mapped()) {
					return true;
				}
				var content_width = this.scrolled.get_allocated_width() - this.text_view.left_margin - this.text_view.right_margin;
				if (content_width <= 0) {
					return true;
				}
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				this.buffer.get_start_iter(out start_iter);
				this.buffer.get_end_iter(out end_iter);
				var text = this.buffer.get_text(start_iter, end_iter, false);
				var layout = this.text_view.create_pango_layout(text);
				layout.set_width(content_width * Pango.SCALE);
				layout.set_wrap(Pango.WrapMode.WORD_CHAR);
				var layout_w = 0;
				var layout_h = 0;
				layout.get_pixel_size(out layout_w, out layout_h);
				var h = layout_h + this.text_view.top_margin + this.text_view.bottom_margin;
				GLib.debug("composer pango focus h=%d layout_h=%d width=%d max=%d",
					h, layout_h, content_width, this.expanded_max_height);
				if (this.expanded_max_height > 0 && h > this.expanded_max_height) {
					this.scrolled.min_content_height = this.expanded_max_height;
					this.scrolled.max_content_height = this.expanded_max_height;
				} else {
					this.scrolled.min_content_height = h;
					this.scrolled.max_content_height = h;
				}
				this.scrolled.queue_resize();
				this.text_view.grab_focus();
				this.buffer.place_cursor(end_iter);
				/* scroll_to_mark waits for line validation — not scroll_to_iter. */
				this.text_view.scroll_to_mark(this.buffer.get_insert(), 0.0, true, 0.0, 1.0);
				return false;
			}
			if (!this.compact_entry.get_mapped()) {
				return true;
			}
			this.compact_entry.grab_focus();
			this.compact_entry.set_position(-1);
			return false;
		}
	}
}
