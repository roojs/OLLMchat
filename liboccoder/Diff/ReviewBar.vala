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

namespace OLLMcoder.Diff
{
	public enum HunkDecision {
		PENDING,
		ACCEPTED,
		REJECTED
	}

	public class HunkBand : Object
	{
		public OLLMfiles.Diff.PatchOperation operation { get; construct; }
		public int line_count { get; construct; }
		public int scroll_line { get; construct; }
		public int line_start { get; construct; }
		public int line_end { get; construct; }
		public HunkDecision decision = HunkDecision.PENDING;
		public int band_index = 0;
		public double map_start = 0.0;
		public double map_width = 0.0;

		public HunkBand(OLLMfiles.Diff.Patch patch)
		{
			var lc = 0;
			var sl = 0;
			var ls = 0;
			var le = 0;
			switch (patch.operation) {
				case OLLMfiles.Diff.PatchOperation.ADD:
					lc = patch.new_line_end - patch.new_line_start + 1;
					sl = patch.new_line_start - 1;
					ls = patch.new_line_start;
					le = patch.new_line_end;
					break;

				case OLLMfiles.Diff.PatchOperation.REMOVE:
					lc = patch.old_line_end - patch.old_line_start + 1;
					sl = patch.old_line_start - 1;
					ls = patch.old_line_start;
					le = patch.old_line_end;
					break;

				default:
					lc = (patch.new_line_end - patch.new_line_start + 1)
						+ (patch.old_line_end - patch.old_line_start + 1);
					sl = patch.new_line_start - 1;
					ls = patch.new_line_start;
					le = patch.new_line_end;
					break;
			}
			Object(
				operation: patch.operation,
				line_count: lc,
				scroll_line: sl,
				line_start: ls,
				line_end: le
			);
		}
	}

	public class HunkList : Gee.ArrayList<HunkBand>
	{
		public int index_at(double x)
		{
			if (this.size < 1) {
				return -1;
			}
			var work = new Gee.ArrayList<HunkBand>();
			work.add_all(this);
			work.sort((a, b) => {
				var da = x < a.map_start ? a.map_start - x
					: (x >= a.map_start + a.map_width ? x - a.map_start - a.map_width : 0.0);
				var db = x < b.map_start ? b.map_start - x
					: (x >= b.map_start + b.map_width ? x - b.map_start - b.map_width : 0.0);
				return da < db ? -1 : (da > db ? 1 : 0);
			});
			var best = work.get(0);
			var d = x < best.map_start ? best.map_start - x
				: (x >= best.map_start + best.map_width ? x - best.map_start - best.map_width : 0.0);
			return d > 0 ? -1 : best.band_index;
		}

		public int pending_after(int after_index)
		{
			var work = new Gee.ArrayList<HunkBand>();
			work.add_all(this);
			work.sort((a, b) => {
				var pa = a.decision == HunkDecision.PENDING ? 0 : 1;
				var pb = b.decision == HunkDecision.PENDING ? 0 : 1;
				if (pa != pb) {
					return pa < pb ? -1 : 1;
				}
				var da = after_index < 0 ? a.band_index
					: (a.band_index - after_index + this.size) % this.size;
				var db = after_index < 0 ? b.band_index
					: (b.band_index - after_index + this.size) % this.size;
				da = after_index >= 0 && da < 1 ? this.size : da;
				db = after_index >= 0 && db < 1 ? this.size : db;
				return da < db ? -1 : (da > db ? 1 : 0);
			});
			return work.get(0).decision != HunkDecision.PENDING ? -1 : work.get(0).band_index;
		}
	}

	/**
	 * Footer diff review bar + centre Accept/Reject overlay (Phase A mock).
	 */
	public class ReviewBar : Gtk.Box
	{
		public Gtk.Box review_overlay;

		private OLLMcoder.SourceView source_view;
		private HunkList hunks { get; set; default = new HunkList(); }
		private Gee.ArrayList<Gtk.DrawingArea> band_areas {
			get; set; default = new Gee.ArrayList<Gtk.DrawingArea>();
		}
		private int active = -1;
		private int mock_files = 1;
		private int mock_index = 0;
		private bool mock_inactive = false;
		private int map_height = 28;
		private int map_width = 0;

		private Gtk.Button file_prev;
		private Gtk.Button file_next;
		private Gtk.Label file_nav_label;
		private Gtk.Box map_host;
		private Gtk.Box map_row;
		private Gtk.Label pending_label;
		private Gtk.Button bulk_btn;
		private Gtk.Button accept_btn;
		private Gtk.Button reject_btn;
		private Gtk.Button unapprove_btn;

		public ReviewBar(
			OLLMcoder.SourceView source_view,
			OLLMfiles.Diff.Differ differ,
			int mock_files = 1,
			bool mock_inactive = false)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.source_view = source_view;
			if (mock_files < 1) {
				mock_files = 1;
			}
			this.mock_files = mock_files;
			this.mock_inactive = mock_inactive;
			this.add_css_class("oc-diff-review-bar");

			var footer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				margin_top = 4,
				margin_bottom = 4,
				margin_start = 6,
				margin_end = 6,
				hexpand = true,
			};
			this.file_prev = new Gtk.Button() {
				icon_name = "go-previous-symbolic",
				tooltip_text = "Previous pending file",
			};
			this.file_prev.clicked.connect(() => {
				this.mock_index--;
				if (this.mock_index < 0) {
					this.mock_index = this.mock_files - 1;
				}
				this.file_nav_label.label = "%d / %d".printf(
					this.mock_index + 1, this.mock_files);
			});
			this.file_next = new Gtk.Button() {
				icon_name = "go-next-symbolic",
				tooltip_text = "Next pending file",
			};
			this.file_next.clicked.connect(() => {
				this.mock_index++;
				if (this.mock_index >= this.mock_files) {
					this.mock_index = 0;
				}
				this.file_nav_label.label = "%d / %d".printf(
					this.mock_index + 1, this.mock_files);
			});
			this.file_nav_label = new Gtk.Label("") {
				xalign = 0.5f,
				label = "1 / %d".printf(this.mock_files),
			};
			var file_nav = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
			file_nav.append(this.file_prev);
			file_nav.append(this.file_nav_label);
			file_nav.append(this.file_next);

			this.map_host = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				vexpand = false,
			};
			this.map_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				vexpand = false,
			};
			var map_click = new Gtk.GestureClick();
			map_click.pressed.connect((n, x, y) => {
				this.on_map_clicked(x);
			});
			this.map_row.add_controller(map_click);
			this.pending_label = new Gtk.Label("") {
				hexpand = true,
				xalign = 0.5f,
				css_classes = { "oc-diff-pending-label" },
				visible = false,
			};
			var pending_click = new Gtk.GestureClick();
			pending_click.pressed.connect(() => {
				if (!this.mock_inactive) {
					return;
				}
				this.mock_inactive = false;
				this.mock_index = 0;
				this.file_nav_label.label = "1 / %d".printf(this.mock_files);
				this.pending_label.visible = false;
				this.map_row.visible = true;
				this.active = this.hunks.pending_after(-1);
				if (this.active < 0 && this.hunks.size > 0) {
					this.active = 0;
				}
				if (this.active >= 0) {
					this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
				}
				this.map_width = 0;
				GLib.Idle.add_once(() => {
					var w = this.map_host.get_width();
					if (w > 0) {
						this.map_host.queue_allocate();
					}
				});
			});
			this.pending_label.add_controller(pending_click);
			this.map_host.append(this.map_row);
			this.map_host.append(this.pending_label);
			this.map_host.notify["width"].connect(() => {
				this.on_width();
			});

			this.bulk_btn = new Gtk.Button.with_label("Bulk actions") {
				tooltip_text = "Bulk review actions (stub)",
			};
			this.bulk_btn.clicked.connect(() => {
				foreach (var hunk in this.hunks) {
					hunk.decision = HunkDecision.ACCEPTED;
				}
				this.active = -1;
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				foreach (var area in this.band_areas) {
					area.queue_draw();
				}
			});
			footer.append(file_nav);
			footer.append(this.map_host);
			footer.append(this.bulk_btn);
			this.append(footer);

			this.review_overlay = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				vexpand = true,
				hexpand = true,
				spacing = 8,
				css_classes = { "oc-diff-review-overlay" },
			};
			this.accept_btn = new Gtk.Button.with_label("Accept") {
				css_classes = { "suggested-action" },
				visible = false,
			};
			this.accept_btn.clicked.connect(() => {
				this.on_accept_clicked();
			});
			this.reject_btn = new Gtk.Button.with_label("Reject") {
				visible = false,
			};
			this.reject_btn.clicked.connect(() => {
				this.on_reject_clicked();
			});
			this.unapprove_btn = new Gtk.Button.with_label("Unapprove") {
				visible = false,
			};
			this.unapprove_btn.clicked.connect(() => {
				if (this.active < 0 || this.active >= this.hunks.size) {
					return;
				}
				this.hunks.get(this.active).decision = HunkDecision.PENDING;
				this.accept_btn.visible = true;
				this.reject_btn.visible = true;
				this.unapprove_btn.visible = false;
				this.band_areas.get(this.active).queue_draw();
			});
			this.review_overlay.append(this.accept_btn);
			this.review_overlay.append(this.reject_btn);
			this.review_overlay.append(this.unapprove_btn);

			this.hunks.clear();
			differ.diff();
			var bi = 0;
			foreach (var patch in differ.patches) {
				this.hunks.add(new HunkBand(patch) {
					band_index = bi,
				});
				bi++;
			}
			if (this.mock_inactive) {
				this.pending_label.visible = true;
				this.map_row.visible = false;
				this.pending_label.label = "%d changes pending review".printf(
					this.mock_files);
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				return;
			}
			this.pending_label.visible = false;
			this.map_row.visible = true;
			this.active = this.hunks.pending_after(-1);
			if (this.active < 0 && this.hunks.size > 0) {
				this.active = 0;
			}
			if (this.active >= 0) {
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
			}
			if (this.active < 0 || this.hunks.get(this.active).decision != HunkDecision.PENDING) {
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
			}
			if (this.active >= 0 && this.hunks.get(this.active).decision == HunkDecision.PENDING) {
				this.accept_btn.visible = true;
				this.reject_btn.visible = true;
				this.unapprove_btn.visible = false;
			}
			GLib.Idle.add_once(() => {
				this.map_width = 0;
				var w = this.map_host.get_width();
				if (w > 0) {
					this.map_host.queue_allocate();
				}
			});
		}

		private void on_width()
		{
			var w = this.map_host.get_width();
			if (w < 1 || (w == this.map_width && this.map_width > 0)) {
				return;
			}
			if (this.mock_inactive || this.hunks.size < 1) {
				return;
			}
			this.map_width = w;
			var min_w = (double) this.map_height * 0.5;
			var gap_w = min_w;
			var weight_sum = 0;
			foreach (var hunk in this.hunks) {
				weight_sum += hunk.line_count;
			}
			if (weight_sum < 1) {
				weight_sum = 1;
			}
			var gap_total = this.hunks.size > 1
				? (this.hunks.size - 1) * gap_w
				: 0.0;
			var avail = (double) w - gap_total;
			if (avail < min_w) {
				avail = min_w;
			}
			var pos = 0.0;
			foreach (var hunk in this.hunks) {
				if (hunk.band_index > 0) {
					pos += gap_w;
				}
				var band_w = avail * (double) hunk.line_count / (double) weight_sum;
				if (band_w < min_w) {
					band_w = min_w;
				}
				hunk.map_start = pos;
				hunk.map_width = band_w;
				pos += band_w;
			}
			this.band_areas.clear();
			while (true) {
				var child = this.map_row.get_first_child();
				if (child == null) {
					break;
				}
				this.map_row.remove(child);
			}
			foreach (var hunk_band in this.hunks) {
				if (hunk_band.band_index > 0) {
					this.map_row.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
						width_request = (int) gap_w,
						css_classes = { "oc-diff-hunk-gap" },
					});
				}
				var index = hunk_band.band_index;
				var band = new Gtk.DrawingArea() {
					width_request = (int) hunk_band.map_width,
					content_height = this.map_height,
					tooltip_text = "%d–%d".printf(
						hunk_band.line_start,
						hunk_band.line_end
					),
					css_classes = { "oc-diff-hunk-map" },
				};
				band.set_draw_func((area, cr, bw, bh) => {
					this.draw_hunk_band(cr, bw, bh, index);
				});
				this.band_areas.add(band);
				this.map_row.append(band);
			}
		}

		private void draw_hunk_band(Cairo.Context cr, int bw, int bh, int index)
		{
			if (bw < 1 || bh < 1 || index < 0 || index >= this.hunks.size) {
				return;
			}
			var hunk = this.hunks.get(index);
			if (hunk.decision != HunkDecision.PENDING) {
				cr.set_source_rgba(0.424, 0.459, 0.490, 0.85);
				cr.rectangle(0.0, 0.0, (double) bw, (double) bh);
				cr.fill();
				if (index != this.active) {
					return;
				}
				cr.set_source_rgb(0.0, 0.0, 0.0);
				cr.set_line_width(2.0);
				cr.rectangle(1.0, 1.0, (double) bw - 2.0, (double) bh - 2.0);
				cr.stroke();
				return;
			}
			switch (hunk.operation) {
				case OLLMfiles.Diff.PatchOperation.ADD:
					cr.set_source_rgba(0.024, 0.839, 0.627, 1.0);
					cr.rectangle(0.0, 0.0, (double) bw, (double) bh);
					cr.fill();
					break;

				case OLLMfiles.Diff.PatchOperation.REMOVE:
					cr.set_source_rgba(0.902, 0.322, 0.322, 1.0);
					cr.rectangle(0.0, 0.0, (double) bw, (double) bh);
					cr.fill();
					break;

				default:
					cr.set_source_rgba(0.902, 0.322, 0.322, 1.0);
					cr.rectangle(0.0, 0.0, (double) bw * 0.5, (double) bh);
					cr.fill();
					cr.set_source_rgba(0.024, 0.839, 0.627, 1.0);
					cr.rectangle((double) bw * 0.5, 0.0, (double) bw * 0.5, (double) bh);
					cr.fill();
					break;
			}
			if (index != this.active) {
				return;
			}
			cr.set_source_rgb(0.0, 0.0, 0.0);
			cr.set_line_width(2.0);
			cr.rectangle(1.0, 1.0, (double) bw - 2.0, (double) bh - 2.0);
			cr.stroke();
		}

		private void on_map_clicked(double x)
		{
			if (this.mock_inactive || this.hunks.size < 1) {
				return;
			}
			var i = this.hunks.index_at(x);
			if (i < 0) {
				return;
			}
			var prev = this.active;
			if (prev == i) {
				return;
			}
			this.active = i;
			this.source_view.navigate_to_line(this.hunks.get(i).scroll_line);
			switch (this.hunks.get(i).decision) {
				case HunkDecision.PENDING:
					this.accept_btn.visible = true;
					this.reject_btn.visible = true;
					this.unapprove_btn.visible = false;
					break;

				default:
					this.accept_btn.visible = false;
					this.reject_btn.visible = false;
					this.unapprove_btn.visible = true;
					break;
			}
			if (prev >= 0 && prev < this.band_areas.size) {
				this.band_areas.get(prev).queue_draw();
			}
			if (i < this.band_areas.size) {
				this.band_areas.get(i).queue_draw();
			}
		}

		private void on_accept_clicked()
		{
			if (this.active < 0 || this.active >= this.hunks.size) {
				return;
			}
			var prev = this.active;
			this.hunks.get(prev).decision = HunkDecision.ACCEPTED;
			var next = this.hunks.pending_after(prev);
			this.active = next;
			if (this.active >= 0) {
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
			}
			if (this.active < 0 || this.hunks.get(this.active).decision != HunkDecision.PENDING) {
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
			}
			if (this.active >= 0 && this.hunks.get(this.active).decision == HunkDecision.PENDING) {
				this.accept_btn.visible = true;
				this.reject_btn.visible = true;
				this.unapprove_btn.visible = false;
			}
			if (prev < this.band_areas.size) {
				this.band_areas.get(prev).queue_draw();
			}
			if (next >= 0 && next != prev && next < this.band_areas.size) {
				this.band_areas.get(next).queue_draw();
			}
		}

		private void on_reject_clicked()
		{
			if (this.active < 0 || this.active >= this.hunks.size) {
				return;
			}
			var prev = this.active;
			this.hunks.get(prev).decision = HunkDecision.REJECTED;
			var next = this.hunks.pending_after(prev);
			this.active = next;
			if (this.active >= 0) {
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
			}
			if (this.active < 0 || this.hunks.get(this.active).decision != HunkDecision.PENDING) {
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
			}
			if (this.active >= 0 && this.hunks.get(this.active).decision == HunkDecision.PENDING) {
				this.accept_btn.visible = true;
				this.reject_btn.visible = true;
				this.unapprove_btn.visible = false;
			}
			if (prev < this.band_areas.size) {
				this.band_areas.get(prev).queue_draw();
			}
			if (next >= 0 && next != prev && next < this.band_areas.size) {
				this.band_areas.get(next).queue_draw();
			}
		}
	}
}
