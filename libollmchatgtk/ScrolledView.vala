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
	 * App-owned vertical scroll shell (GTK {@link Gtk.ScrolledWindow} model,
	 * without fighting measure).
	 *
	 * Based on GTK `gtkscrolledwindow.c` allocate/measure: viewport size is
	 * independent of content; a {@link Gtk.Scrollable} child gets the
	 * viewport allocation and scrolls via shared adjustments.
	 *
	 * Vertical size is exactly {@link content_height} (min = nat). Classic
	 * vertical scrollbar only when at {@link max_height} and
	 * `vadjustment.upper > page_size` (hidden while the viewport still grows).
	 *
	 * When the child is a {@link Gtk.TextView}, {@link set_child} binds
	 * `buffer.changed` (one Idle) to set {@link content_height} from line
	 * yrange (capped by {@link max_height}). Scroll-to-end is applied in
	 * {@link size_allocate} after the TextView updates its adjustment.
	 *
	 * == Usage Examples ==
	 *
	 * === Composer TextView ===
	 *
	 * {{{
	 *   var scroll = new OLLMchatGtk.ScrolledView();
	 *   scroll.max_height = half_chat;
	 *   scroll.set_child(text_view); // auto-sizes on buffer.changed
	 * }}}
	 *
	 * @since 1.0
	 */
	public class ScrolledView : Gtk.Widget
	{
		private Gtk.Widget? child_widget = null;
		private Gtk.TextView? text_view = null;
		private ulong buffer_changed_id = 0;
		private Gtk.Scrollbar vscrollbar;
		private bool vbar_visible = false;
		/** After TextView fit: pin vadjustment to bottom in next size_allocate. */
		private bool pin_end = false;
		/** True until yrange fit succeeds after programmatic / pending layout. */
		private bool need_fit = false;
		/** Last TextView allocate width — wrap height must refit when this changes. */
		private int fit_width = 0;

		/** Shared with scrollable child (horizontal — usually unused). */
		public Gtk.Adjustment hadjustment { get; private set; }

		/** Shared with scrollable child; drives classic scrollbar. */
		public Gtk.Adjustment vadjustment { get; private set; }

		/**
		 * Viewport height we report and allocate (pixels).
		 * For a TextView child this is driven from buffer.changed.
		 */
		public int content_height { get; set; default = 0; }

		/** Cap for TextView auto-height; 0 = uncapped. */
		public int max_height { get; set; default = 0; }

		/**
		 * When set, empty / one visual line height matches this widget's
		 * natural height (composer play button). Multi-line uses yrange.
		 */
		public Gtk.Widget? line_peer { get; set; default = null; }

		/**
		 * After TextView yrange fit: {@link content_height} updated.
		 * ''lines'': 0 empty, 1 one visual line, 2 more than one.
		 */
		public signal void lines_changed(int lines);

		static construct
		{
			set_css_name("scrolledview");
		}

		public ScrolledView()
		{
			Object();
			this.hadjustment = new Gtk.Adjustment(0, 0, 0, 0, 0, 0);
			this.vadjustment = new Gtk.Adjustment(0, 0, 0, 0, 0, 0);
			this.vscrollbar = new Gtk.Scrollbar(Gtk.Orientation.VERTICAL, this.vadjustment);
			this.vscrollbar.set_parent(this);
			this.vscrollbar.set_child_visible(false);
			this.notify["content-height"].connect(() => {
				this.queue_resize();
			});
			this.notify["max-height"].connect(() => {
				if (this.text_view == null) {
					return;
				}
				GLib.Idle.add(this.buffer_change);
			});
			this.notify["line-peer"].connect(() => {
				GLib.Idle.add(this.buffer_change);
			});
			/* Empty buffer never fires changed — fit once mapped. */
			this.map.connect(() => {
				GLib.Idle.add(this.buffer_change);
			});
			this.vadjustment.changed.connect(() => {
				if (this.need_fit) {
					this.buffer_change();
				}
				var over_cap = this.max_height > 0 && this.content_height >= this.max_height;
				var need = over_cap
					&& this.vadjustment.upper > this.vadjustment.page_size + 0.5;
				if (need == this.vbar_visible) {
					return;
				}
				/* child_visible only in size_allocate (GTK scrolledwindow) — map before allocate snapshots. */
				this.queue_allocate();
			});
			var scroll = new Gtk.EventControllerScroll(
				Gtk.EventControllerScrollFlags.VERTICAL | Gtk.EventControllerScrollFlags.DISCRETE);
			scroll.scroll.connect((dx, dy) => {
				if (this.vadjustment.page_size <= 0) {
					return false;
				}
				if (this.vadjustment.upper <= this.vadjustment.page_size) {
					return false;
				}
				var next = this.vadjustment.value + dy * this.vadjustment.step_increment;
				if (next < this.vadjustment.lower) {
					next = this.vadjustment.lower;
				}
				var max = this.vadjustment.upper - this.vadjustment.page_size;
				if (next > max) {
					next = max;
				}
				this.vadjustment.value = next;
				return true;
			});
			this.add_controller(scroll);
		}

		/** Set or replace the scrollable (or plain) child. */
		public void set_child(Gtk.Widget? child)
		{
			if (this.child_widget == child) {
				return;
			}
			if (this.text_view != null && this.buffer_changed_id != 0) {
				this.text_view.buffer.disconnect(this.buffer_changed_id);
				this.buffer_changed_id = 0;
				this.text_view = null;
			}
			if (this.child_widget != null) {
				var old_scrollable = this.child_widget as Gtk.Scrollable;
				if (old_scrollable != null) {
					old_scrollable.hadjustment = null;
					old_scrollable.vadjustment = null;
				}
				this.child_widget.unparent();
				this.child_widget = null;
			}
			if (child == null) {
				this.queue_resize();
				return;
			}
			this.child_widget = child;
			child.set_parent(this);
			var scrollable = child as Gtk.Scrollable;
			if (scrollable != null) {
				scrollable.hadjustment = this.hadjustment;
				scrollable.vadjustment = this.vadjustment;
			}
			var tv = child as Gtk.TextView;
			if (tv == null) {
				this.queue_resize();
				return;
			}
			this.text_view = tv;
			this.buffer_changed_id = tv.buffer.changed.connect(() => {
				GLib.Idle.add(this.buffer_change);
			});
			this.queue_resize();
		}

		/**
		 * Schedule {@link buffer_change} on Idle (e.g. after expand when mapped).
		 */
		public void queue_fit()
		{
			GLib.Idle.add(this.buffer_change);
		}

		/**
		 * Idle after TextView buffer.changed: set {@link content_height} from
		 * line yrange; request bottom pin on next allocate when caret is at end.
		 *
		 * @return true to wait for map/width, false when done
		 */
		private bool buffer_change()
		{
			if (this.text_view == null) {
				return false;
			}
			if (!this.text_view.get_mapped()) {
				return true;
			}
			if (this.get_width() <= 0) {
				return true;
			}
			var peer_h = 0;
			if (this.line_peer != null) {
				var peer_min = 0;
				var peer_nat = 0;
				this.line_peer.measure(Gtk.Orientation.VERTICAL, -1,
					out peer_min, out peer_nat, null, null);
				peer_h = peer_nat > 0 ? peer_nat : peer_min;
			}
			/* Offsets survive mutation; do not hold TextIters across any call that may re-enter. */
			var end_off = this.text_view.buffer.get_char_count();
			Gtk.TextIter size_start;
			Gtk.TextIter size_end;
			this.text_view.buffer.get_start_iter(out size_start);
			this.text_view.buffer.get_iter_at_offset(out size_end, end_off);
			var y0 = 0;
			var h0 = 0;
			var y = 0;
			var line_h = 0;
			this.text_view.get_line_yrange(size_start, out y0, out h0);
			this.text_view.get_line_yrange(size_end, out y, out line_h);
			/* Layout not ready: peer interim; content waits for vadjustment (TextView validate). */
			if (h0 < 1 || line_h < 1) {
				if (peer_h > 0) {
					this.content_height = peer_h;
					this.pin_end = false;
					this.vadjustment.value = 0;
				}
				if (end_off > 0) {
					this.need_fit = true;
					return false;
				}
				this.need_fit = false;
				this.lines_changed(0);
				if (peer_h > 0) {
					return false;
				}
				return true;
			}
			this.need_fit = false;
			var content_h = y + line_h;
			Gdk.Rectangle glyph;
			this.text_view.get_iter_location(size_start, out glyph);
			/* yrange is paragraph height (GTK); peer only when content fits the play-button row. */
			var use_peer = peer_h > 0 && content_h <= peer_h;
			GLib.message(
				"scrolledview fit end_off=%d content_h=%d peer_h=%d glyph_h=%d use_peer=%s → lines=%d",
				end_off, content_h, peer_h, glyph.height, use_peer.to_string(),
				end_off == 0 ? 0 : (use_peer ? 1 : 2));
			if (use_peer) {
				var extra = peer_h - content_h;
				if (extra < 0) {
					extra = 0;
				}
				var top = extra / 2;
				this.text_view.top_margin = top;
				this.text_view.bottom_margin = extra - top;
			}
			if (!use_peer) {
				this.text_view.top_margin = 4;
				this.text_view.bottom_margin = 4;
			}
			var yrange_h = content_h + this.text_view.top_margin + this.text_view.bottom_margin;
			var target = use_peer ? peer_h : yrange_h;
			if (target < 1) {
				target = 1;
			}
			if (this.max_height > 0 && target > this.max_height) {
				target = this.max_height;
			}
			this.pin_end = this.text_view.buffer.cursor_position >= this.text_view.buffer.get_char_count();
			this.content_height = target;
			if (yrange_h <= target) {
				this.vadjustment.value = 0;
				this.pin_end = false;
			}
			this.lines_changed(end_off == 0 ? 0 : (use_peer ? 1 : 2));
			return false;
		}

		public override void dispose()
		{
			if (this.text_view != null && this.buffer_changed_id != 0) {
				this.text_view.buffer.disconnect(this.buffer_changed_id);
				this.buffer_changed_id = 0;
				this.text_view = null;
			}
			if (this.child_widget != null) {
				this.child_widget.unparent();
				this.child_widget = null;
			}
			if (this.vscrollbar != null) {
				this.vscrollbar.unparent();
			}
			base.dispose();
		}

		public override void measure(Gtk.Orientation orientation, int for_size,
			out int minimum, out int natural, out int minimum_baseline, out int natural_baseline)
		{
			minimum_baseline = -1;
			natural_baseline = -1;
			if (orientation == Gtk.Orientation.VERTICAL) {
				var h = this.content_height;
				if (h < 0) {
					h = 0;
				}
				minimum = h;
				natural = h;
				return;
			}
			minimum = 0;
			natural = 0;
			if (this.child_widget == null || !this.child_widget.visible) {
				return;
			}
			this.child_widget.measure(Gtk.Orientation.HORIZONTAL, for_size,
				out minimum, out natural, null, null);
		}

		public override void size_allocate(int width, int height, int baseline)
		{
			/* Under max_height the shell grows to fit — no bar until capped and still overflowing. */
			var over_cap = this.max_height > 0 && this.content_height >= this.max_height;
			var need = over_cap
				&& this.vadjustment.upper > this.vadjustment.page_size + 0.5;
			this.vbar_visible = need;
			this.vscrollbar.set_child_visible(need);
			var sb_w = 0;
			if (need && height > 0) {
				var sb_min = 0;
				var sb_nat = 0;
				/* for_size=-1: GTK scrolledwindow; height-for-width warns if height < bar min (~58). */
				this.vscrollbar.measure(Gtk.Orientation.HORIZONTAL, -1, out sb_min, out sb_nat, null, null);
				sb_w = sb_nat;
				if (sb_w < 1) {
					sb_w = sb_min;
				}
			}
			var child_w = width - sb_w;
			if (child_w < 1) {
				child_w = 1;
			}
			if (this.child_widget != null && this.child_widget.visible) {
				this.child_widget.allocate(child_w, height, baseline, null);
			}
			if (this.text_view != null && child_w != this.fit_width) {
				this.fit_width = child_w;
				GLib.Idle.add(this.buffer_change);
			}
			if (this.pin_end) {
				this.pin_end = false;
				var max = this.vadjustment.upper - this.vadjustment.page_size;
				if (max > 0.0) {
					this.vadjustment.value = max;
				}
			}
			if (!need || sb_w < 1 || height < 1) {
				return;
			}
			var sb_point = Graphene.Point() {
				x = (float) (width - sb_w),
				y = 0.0f
			};
			var t = new Gsk.Transform();
			t = t.translate(sb_point);
			this.vscrollbar.allocate(sb_w, height, -1, t);
		}
	}
}
