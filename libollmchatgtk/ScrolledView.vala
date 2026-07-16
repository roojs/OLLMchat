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
	 * vertical scrollbar when `vadjustment.upper > page_size`.
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
			this.vadjustment.changed.connect(() => {
				var need = this.vadjustment.upper > this.vadjustment.page_size + 0.5;
				if (need == this.vbar_visible) {
					return;
				}
				this.vbar_visible = need;
				this.vscrollbar.set_child_visible(need);
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
			Gtk.TextIter size_end;
			this.text_view.buffer.get_end_iter(out size_end);
			var y = 0;
			var line_h = 0;
			this.text_view.get_line_yrange(size_end, out y, out line_h);
			var yrange_h = y + line_h + this.text_view.top_margin + this.text_view.bottom_margin;
			var target = yrange_h;
			if (target < 1) {
				target = 1;
			}
			if (this.max_height > 0 && yrange_h > this.max_height) {
				target = this.max_height;
			}
			Gtk.TextIter ins;
			Gtk.TextIter end;
			this.text_view.buffer.get_iter_at_mark(out ins, this.text_view.buffer.get_insert());
			this.text_view.buffer.get_end_iter(out end);
			this.pin_end = ins.get_offset() >= end.get_offset();
			this.content_height = target;
			if (yrange_h <= target) {
				this.vadjustment.value = 0;
				this.pin_end = false;
			}
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
			var need = this.vadjustment.upper > this.vadjustment.page_size + 0.5;
			if (need != this.vbar_visible) {
				this.vbar_visible = need;
				this.vscrollbar.set_child_visible(need);
			}
			var sb_w = 0;
			if (this.vbar_visible) {
				var sb_min = 0;
				var sb_nat = 0;
				this.vscrollbar.measure(Gtk.Orientation.HORIZONTAL, height, out sb_min, out sb_nat, null, null);
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
			if (this.pin_end) {
				this.pin_end = false;
				var max = this.vadjustment.upper - this.vadjustment.page_size;
				if (max > 0.0) {
					this.vadjustment.value = max;
				}
			}
			if (!this.vbar_visible || sb_w < 1) {
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
