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
		/** Bumps so superseded height Idles do not apply a stale measure. */
		private uint size_serial = 0;
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
					GLib.debug("composer buf skip syncing");
					return;
				}
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				this.buffer.get_start_iter(out start_iter);
				this.buffer.get_end_iter(out end_iter);
				var text = this.buffer.get_text(start_iter, end_iter, false);
				var n_nl = text.split("\n").length - 1;
				GLib.debug("composer buf len=%d nl=%d ends_nl=%d expanded=%d alloc_w=%d alloc_h=%d min=%d max=%d cap=%d",
					text.length, n_nl, text.has_suffix("\n") ? 1 : 0, this.is_expanded ? 1 : 0,
					this.scrolled.get_allocated_width(), this.scrolled.get_allocated_height(),
					this.scrolled.min_content_height, this.scrolled.max_content_height,
					this.expanded_max_height);
				this.update_entry(text);
				if (!this.is_expanded) {
					return;
				}
				/*
				 * B6: default-priority Idle runs after GTK_TEXT_VIEW_PRIORITY_VALIDATE,
				 * so get_line_yrange is not stale (unlike Timeout / sync measure).
				 */
				this.size_serial++;
				var serial = this.size_serial;
				GLib.debug("composer size schedule serial=%u from=buf", serial);
				GLib.Idle.add(() => {
					if (serial != this.size_serial) {
						GLib.debug("composer size skip stale serial=%u now=%u", serial, this.size_serial);
						return false;
					}
					if (!this.is_expanded || !this.text_view.get_mapped()) {
						GLib.debug("composer size skip expanded=%d mapped=%d serial=%u",
							this.is_expanded ? 1 : 0, this.text_view.get_mapped() ? 1 : 0, serial);
						return false;
					}
					if (this.scrolled.get_allocated_width() <= 0) {
						GLib.debug("composer size retry width=0 serial=%u", serial);
						return true;
					}
					Gtk.TextIter size_end;
					this.buffer.get_end_iter(out size_end);
					var y = 0;
					var line_h = 0;
					this.text_view.get_line_yrange(size_end, out y, out line_h);
					var h = y + line_h + this.text_view.top_margin + this.text_view.bottom_margin;
					var cap = this.expanded_max_height;
					var adj = this.scrolled.get_vadjustment();
					var upper = (int) adj.upper;
					var page = (int) adj.page_size;
					var value = (int) adj.value;
					var want_min = h;
					var want_max = h;
					if (cap > 0) {
						want_min = h > cap ? cap : h;
						want_max = cap;
					}
					GLib.debug("composer size apply serial=%u y=%d line_h=%d h=%d upper=%d page=%d value=%d want_min=%d want_max=%d was_min=%d was_max=%d tv_h=%d sw_h=%d",
						serial, y, line_h, h, upper, page, value, want_min, want_max,
						this.scrolled.min_content_height, this.scrolled.max_content_height,
						this.text_view.get_allocated_height(), this.scrolled.get_allocated_height());
					this.scrolled.min_content_height = want_min;
					this.scrolled.max_content_height = want_max;
					this.scrolled.queue_resize();
					GLib.Idle.add(() => {
						var adj2 = this.scrolled.get_vadjustment();
						GLib.debug("composer size after serial=%u sw_h=%d tv_h=%d upper=%d page=%d value=%d min=%d max=%d",
							serial, this.scrolled.get_allocated_height(), this.text_view.get_allocated_height(),
							(int) adj2.upper, (int) adj2.page_size, (int) adj2.value,
							this.scrolled.min_content_height, this.scrolled.max_content_height);
						return false;
					});
					return false;
				});
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
				GLib.debug("composer flip to expanded len=%d", text.length);
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

			GLib.debug("composer flip to compact len=%d", text.length);
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
					GLib.debug("composer focus_idle wait mapped");
					return true;
				}
				if (this.scrolled.get_allocated_width() <= 0) {
					GLib.debug("composer focus_idle wait width");
					return true;
				}
				this.text_view.grab_focus();
				Gtk.TextIter end_iter;
				this.buffer.get_end_iter(out end_iter);
				this.buffer.place_cursor(end_iter);
				this.text_view.scroll_to_mark(this.buffer.get_insert(), 0.0, true, 0.0, 1.0);
				/* B6 height after validate (expand path skips buffer.changed while syncing). */
				this.size_serial++;
				var serial = this.size_serial;
				GLib.debug("composer size schedule serial=%u from=focus", serial);
				GLib.Idle.add(() => {
					if (serial != this.size_serial) {
						GLib.debug("composer size skip stale serial=%u now=%u", serial, this.size_serial);
						return false;
					}
					if (!this.is_expanded || !this.text_view.get_mapped()) {
						GLib.debug("composer size skip expanded=%d mapped=%d serial=%u",
							this.is_expanded ? 1 : 0, this.text_view.get_mapped() ? 1 : 0, serial);
						return false;
					}
					if (this.scrolled.get_allocated_width() <= 0) {
						GLib.debug("composer size retry width=0 serial=%u", serial);
						return true;
					}
					Gtk.TextIter size_end;
					this.buffer.get_end_iter(out size_end);
					var y = 0;
					var line_h = 0;
					this.text_view.get_line_yrange(size_end, out y, out line_h);
					var h = y + line_h + this.text_view.top_margin + this.text_view.bottom_margin;
					var cap = this.expanded_max_height;
					var adj = this.scrolled.get_vadjustment();
					var upper = (int) adj.upper;
					var page = (int) adj.page_size;
					var value = (int) adj.value;
					var want_min = h;
					var want_max = h;
					if (cap > 0) {
						want_min = h > cap ? cap : h;
						want_max = cap;
					}
					GLib.debug("composer size apply serial=%u y=%d line_h=%d h=%d upper=%d page=%d value=%d want_min=%d want_max=%d was_min=%d was_max=%d tv_h=%d sw_h=%d",
						serial, y, line_h, h, upper, page, value, want_min, want_max,
						this.scrolled.min_content_height, this.scrolled.max_content_height,
						this.text_view.get_allocated_height(), this.scrolled.get_allocated_height());
					this.scrolled.min_content_height = want_min;
					this.scrolled.max_content_height = want_max;
					this.scrolled.queue_resize();
					GLib.Idle.add(() => {
						var adj2 = this.scrolled.get_vadjustment();
						GLib.debug("composer size after serial=%u sw_h=%d tv_h=%d upper=%d page=%d value=%d min=%d max=%d",
							serial, this.scrolled.get_allocated_height(), this.text_view.get_allocated_height(),
							(int) adj2.upper, (int) adj2.page_size, (int) adj2.value,
							this.scrolled.min_content_height, this.scrolled.max_content_height);
						return false;
					});
					return false;
				});
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
