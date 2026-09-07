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

		public signal void file_index_changed(int index);

		private OLLMcoder.SourceView source_view;
		private HunkList hunks { get; set; default = new HunkList(); }
		private int active = -1;
		private int file_count = 1;
		private int file_index = 0;
		private bool mock_inactive = false;
		private int map_height = 28;
		private int map_width = 0;
		private double map_gap_width = 0.0;
		private int hunk_line_sum = 0;

		private Gtk.Button file_prev;
		private Gtk.Button file_next;
		private Gtk.Label file_nav_label;
		private Gtk.Box file_nav;
		private Gtk.Box map_host;
		private Gtk.DrawingArea map_area;
		private Gtk.Label pending_label;
		private Gtk.Button bulk_btn;
		private Gtk.PopoverMenu file_menu_popover;
		private Gtk.PopoverMenu bulk_menu_popover;
		private uint file_popover_hide_id = 0;
		private uint bulk_popover_hide_id = 0;
		private string[] file_labels = {};
		private Gtk.Button accept_btn;
		private Gtk.Button reject_btn;
		private Gtk.Button unapprove_btn;

		public ReviewBar(
			OLLMcoder.SourceView source_view,
			int file_count = 1,
			bool mock_inactive = false,
			int initial_file_index = 0,
			owned string[] file_labels = {})
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.source_view = source_view;
			this.file_count = int.max(1, file_count);
			this.file_labels = file_labels;
			this.mock_inactive = mock_inactive;
			this.file_index = initial_file_index;
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
				this.file_index = (this.file_index - 1 + this.file_count) % this.file_count;
				this.file_nav_label.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
				this.file_index_changed(this.file_index);
			});
			this.file_next = new Gtk.Button() {
				icon_name = "go-next-symbolic",
				tooltip_text = "Next pending file",
			};
			this.file_next.clicked.connect(() => {
				this.file_index = (this.file_index + 1) % this.file_count;
				this.file_nav_label.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
				this.file_index_changed(this.file_index);
			});
			this.file_nav_label = new Gtk.Label("") {
				xalign = 0.5f,
			};
			if (this.file_count > 1) {
				this.file_nav_label.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
			}
			this.file_nav = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
			this.file_nav.append(this.file_prev);
			this.file_nav.append(this.file_nav_label);
			this.file_nav.append(this.file_next);
			this.file_nav.visible = this.file_count > 1;

			var file_menu = new GLib.Menu();
			var file_actions = new GLib.SimpleActionGroup();
			for (var fi = 0; fi < this.file_labels.length; fi++) {
				var pick = fi;
				var action_name = "pick-%u".printf(fi);
				var pick_action = new GLib.SimpleAction(action_name, null);
				pick_action.activate.connect(() => {
					if (this.file_index != pick) {
						this.file_index = pick;
						this.file_nav_label.label = "File %d of %d".printf(
							pick + 1, this.file_count);
						this.file_index_changed(pick);
					}
					((Gtk.Popover) this.file_menu_popover).popdown();
				});
				file_actions.add_action(pick_action);
				file_menu.append(this.file_labels[fi], "file.%s".printf(action_name));
			}
			this.insert_action_group("file", file_actions);
			this.file_menu_popover = new Gtk.PopoverMenu.from_model(file_menu);
			this.file_menu_popover.set_parent(this.file_nav_label);
			((Gtk.Popover) this.file_menu_popover).autohide = false;
			var file_anchor_motion = new Gtk.EventControllerMotion();
			file_anchor_motion.enter.connect(() => {
				if (this.file_count < 2 || this.file_labels.length < 1) {
					return;
				}
				if (this.file_popover_hide_id != 0) {
					GLib.Source.remove(this.file_popover_hide_id);
					this.file_popover_hide_id = 0;
				}
				this.file_menu_popover.popup();
			});
			file_anchor_motion.leave.connect(() => {
				if (this.file_popover_hide_id != 0) {
					GLib.Source.remove(this.file_popover_hide_id);
				}
				this.file_popover_hide_id = GLib.Timeout.add_seconds(3, () => {
					((Gtk.Popover) this.file_menu_popover).popdown();
					this.file_popover_hide_id = 0;
					return false;
				});
			});
			this.file_nav_label.add_controller(file_anchor_motion);
			var file_popover_motion = new Gtk.EventControllerMotion();
			file_popover_motion.enter.connect(() => {
				if (this.file_popover_hide_id != 0) {
					GLib.Source.remove(this.file_popover_hide_id);
					this.file_popover_hide_id = 0;
				}
			});
			file_popover_motion.leave.connect(() => {
				if (this.file_popover_hide_id != 0) {
					GLib.Source.remove(this.file_popover_hide_id);
				}
				this.file_popover_hide_id = GLib.Timeout.add_seconds(3, () => {
					((Gtk.Popover) this.file_menu_popover).popdown();
					this.file_popover_hide_id = 0;
					return false;
				});
			});
			(this.file_menu_popover as Gtk.Widget).add_controller(file_popover_motion);

			this.map_host = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
				vexpand = false,
				height_request = this.map_height,
			};
			this.map_area = new Gtk.DrawingArea() {
				hexpand = true,
				vexpand = false,
				content_height = this.map_height,
				css_classes = { "oc-diff-hunk-map" },
			};
			this.map_area.set_draw_func((area, cr, w, h) => {
				this.draw_hunk_band(cr, w, h);
			});
			var map_click = new Gtk.GestureClick();
			map_click.pressed.connect((n, x, y) => {
				this.on_map_clicked(x);
			});
			this.map_area.add_controller(map_click);
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
				this.file_index = 0;
				this.file_nav.visible = this.file_count > 1;
				this.pending_label.visible = false;
				this.map_area.visible = true;
				this.active = this.hunks.pending_after(-1);
				this.active = this.active < 0 && this.hunks.size > 0 ? 0 : this.active;
				if (this.active >= 0) {
					this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
				}
				var pending = this.active >= 0
					&& this.hunks.get(this.active).decision == HunkDecision.PENDING;
				this.accept_btn.visible = pending;
				this.reject_btn.visible = pending;
				this.unapprove_btn.visible = false;
				this.map_width = 0;
				this.file_index_changed(0);
				GLib.Idle.add_once(() => {
					this.on_width();
				});
			});
			this.pending_label.add_controller(pending_click);
			this.map_host.append(this.map_area);
			this.map_host.append(this.pending_label);
			this.map_host.notify["width"].connect(() => {
				this.on_width();
			});
			this.map_host.notify["allocated-width"].connect(() => {
				this.on_width();
			});
			this.map_host.realize.connect(() => {
				this.map_width = 0;
				this.on_width();
			});

			var bulk_menu = new GLib.Menu();
			bulk_menu.append("Accept all this file", "bulk.accept-all");
			var bulk_actions = new GLib.SimpleActionGroup();
			var accept_all = new GLib.SimpleAction("accept-all", null);
			accept_all.activate.connect(() => {
				foreach (var hunk in this.hunks) {
					hunk.decision = HunkDecision.ACCEPTED;
				}
				this.active = -1;
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.map_area.queue_draw();
			});
			bulk_actions.add_action(accept_all);
			this.insert_action_group("bulk", bulk_actions);
			this.bulk_menu_popover = new Gtk.PopoverMenu.from_model(bulk_menu);
			this.bulk_btn = new Gtk.Button.with_label("Bulk actions") {
				tooltip_text = "Bulk review actions",
			};
			this.bulk_menu_popover.set_parent(this.bulk_btn);
			((Gtk.Popover) this.bulk_menu_popover).autohide = false;
			var bulk_anchor_motion = new Gtk.EventControllerMotion();
			bulk_anchor_motion.enter.connect(() => {
				if (this.bulk_popover_hide_id != 0) {
					GLib.Source.remove(this.bulk_popover_hide_id);
					this.bulk_popover_hide_id = 0;
				}
				this.bulk_menu_popover.popup();
			});
			bulk_anchor_motion.leave.connect(() => {
				if (this.bulk_popover_hide_id != 0) {
					GLib.Source.remove(this.bulk_popover_hide_id);
				}
				this.bulk_popover_hide_id = GLib.Timeout.add_seconds(3, () => {
					((Gtk.Popover) this.bulk_menu_popover).popdown();
					this.bulk_popover_hide_id = 0;
					return false;
				});
			});
			this.bulk_btn.add_controller(bulk_anchor_motion);
			var bulk_popover_motion = new Gtk.EventControllerMotion();
			bulk_popover_motion.enter.connect(() => {
				if (this.bulk_popover_hide_id != 0) {
					GLib.Source.remove(this.bulk_popover_hide_id);
					this.bulk_popover_hide_id = 0;
				}
			});
			bulk_popover_motion.leave.connect(() => {
				if (this.bulk_popover_hide_id != 0) {
					GLib.Source.remove(this.bulk_popover_hide_id);
				}
				this.bulk_popover_hide_id = GLib.Timeout.add_seconds(3, () => {
					((Gtk.Popover) this.bulk_menu_popover).popdown();
					this.bulk_popover_hide_id = 0;
					return false;
				});
			});
			(this.bulk_menu_popover as Gtk.Widget).add_controller(bulk_popover_motion);

			footer.append(this.file_nav);
			footer.append(this.map_host);
			footer.append(this.bulk_btn);
			this.append(footer);

			this.review_overlay = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.END,
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
				if (this.hunks.get(this.active).decision == HunkDecision.PENDING) {
					return;
				}
				this.hunks.get(this.active).decision = HunkDecision.PENDING;
				this.accept_btn.visible = true;
				this.reject_btn.visible = true;
				this.unapprove_btn.visible = false;
				this.map_area.queue_draw();
			});
			this.review_overlay.append(this.accept_btn);
			this.review_overlay.append(this.reject_btn);
			this.review_overlay.append(this.unapprove_btn);
		}

		/**
		 * Owner calls after {@link OLLMcoder.SourceView.show_diff} when the differ changes.
		 *
		 * @param differ current diff (patches only — ReviewBar does not apply hunks)
		 * @param file_index optional footer file index (-1 = keep current)
		 */
		public void update_diff(
			OLLMfiles.Diff.Differ differ,
			int file_index = -1)
		{
			this.file_index = file_index >= 0 ? file_index : this.file_index;
			this.hunks.clear();
			this.hunk_line_sum = 0;
			differ.diff();
			var bi = 0;
			foreach (var patch in differ.patches) {
				var band = new HunkBand(patch) {
					band_index = bi,
				};
				this.hunks.add(band);
				this.hunk_line_sum += band.line_count;
				bi++;
			}
			this.file_nav.visible = this.file_count > 1;
			if (this.file_count > 1) {
				this.file_nav_label.label = "File %d of %d".printf(
					this.file_index + 1, this.file_count);
			}
			if (this.mock_inactive) {
				this.pending_label.visible = true;
				this.map_area.visible = false;
				this.pending_label.label = "%d changes pending review".printf(
					this.file_count);
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				return;
			}
			this.pending_label.visible = false;
			this.map_area.visible = true;
			this.active = this.hunks.pending_after(-1);
			this.active = this.active < 0 && this.hunks.size > 0 ? 0 : this.active;
			if (this.active >= 0) {
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
			}
			var pending = this.active >= 0
				&& this.hunks.get(this.active).decision == HunkDecision.PENDING;
			this.accept_btn.visible = pending;
			this.reject_btn.visible = pending;
			this.unapprove_btn.visible = false;
			this.map_width = 0;
			GLib.Idle.add_once(() => {
				this.on_width();
			});
		}

		private void on_width()
		{
			var w = this.map_area.get_allocated_width();
			if (w < 1) {
				w = this.map_host.get_allocated_width();
			}
			if (w < 1 || (w == this.map_width && this.map_width > 0)) {
				return;
			}
			if (this.mock_inactive || this.hunks.size < 1) {
				return;
			}
			this.map_width = w;
			var sq = (double) this.map_height;
			this.map_gap_width = sq;
			var weight_sum = int.max(1, this.hunk_line_sum);
			var gap_count = this.hunks.size > 1 ? this.hunks.size - 1 : 0;
			var gap_total_sq = (double) gap_count * sq;
			var band_total_sq = (double) weight_sum * sq;
			var square_fits = band_total_sq + gap_total_sq <= (double) w;
			var avail = double.max((double) w - gap_total_sq, sq);
			var pos = 0.0;
			foreach (var hunk in this.hunks) {
				pos += hunk.band_index > 0 ? sq : 0.0;
				hunk.map_start = pos;
				hunk.map_width = square_fits
					? (double) hunk.line_count * sq
					: avail * (double) hunk.line_count / (double) weight_sum;
				pos += hunk.map_width;
			}
			this.map_area.queue_draw();
		}

		private void draw_hunk_band(Cairo.Context cr, int w, int h)
		{
			if (w < 1 || h < 1) {
				return;
			}
			if (!this.mock_inactive && this.hunks.size > 0 && this.map_width != w) {
				this.on_width();
			}
			foreach (var hunk in this.hunks) {
				if (hunk.band_index > 0 && this.map_gap_width > 0.0) {
					cr.set_source_rgb(1.0, 1.0, 1.0);
					cr.rectangle(hunk.map_start - this.map_gap_width, 0.0,
						this.map_gap_width, (double) h);
					cr.fill();
				}
				var bw = (int) hunk.map_width;
				var index = hunk.band_index;
				if (bw < 1 || index < 0 || index >= this.hunks.size) {
					continue;
				}
				cr.save();
				cr.translate(hunk.map_start, 0.0);
				if (hunk.decision != HunkDecision.PENDING) {
					cr.set_source_rgba(0.424, 0.459, 0.490, 0.85);
					cr.rectangle(0.0, 0.0, (double) bw, (double) h);
					cr.fill();
					if (index == this.active) {
						cr.set_source_rgb(0.0, 0.0, 0.0);
						cr.set_line_width(2.0);
						cr.rectangle(1.0, 1.0, (double) bw - 2.0, (double) h - 2.0);
						cr.stroke();
					}
					cr.restore();
					continue;
				}
				switch (hunk.operation) {
					case OLLMfiles.Diff.PatchOperation.ADD:
						cr.set_source_rgba(0.024, 0.839, 0.627, 1.0);
						cr.rectangle(0.0, 0.0, (double) bw, (double) h);
						cr.fill();
						break;

					case OLLMfiles.Diff.PatchOperation.REMOVE:
						cr.set_source_rgba(0.902, 0.322, 0.322, 1.0);
						cr.rectangle(0.0, 0.0, (double) bw, (double) h);
						cr.fill();
						break;

					default:
						cr.set_source_rgba(0.902, 0.322, 0.322, 1.0);
						cr.rectangle(0.0, 0.0, (double) bw * 0.5, (double) h);
						cr.fill();
						cr.set_source_rgba(0.024, 0.839, 0.627, 1.0);
						cr.rectangle((double) bw * 0.5, 0.0, (double) bw * 0.5, (double) h);
						cr.fill();
						break;
				}
				if (index == this.active) {
					cr.set_source_rgb(0.0, 0.0, 0.0);
					cr.set_line_width(2.0);
					cr.rectangle(1.0, 1.0, (double) bw - 2.0, (double) h - 2.0);
					cr.stroke();
				}
				cr.restore();
			}
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
			if (this.active == i) {
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
			this.map_area.queue_draw();
		}

		private void on_accept_clicked()
		{
			if (this.active < 0 || this.active >= this.hunks.size) {
				return;
			}
			if (this.hunks.get(this.active).decision != HunkDecision.PENDING) {
				return;
			}
			var decided = this.active;
			this.hunks.get(decided).decision = HunkDecision.ACCEPTED;
			this.active = this.hunks.pending_after(decided);
			if (this.active >= 0) {
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
			}
			var pending = this.active >= 0;
			this.accept_btn.visible = pending;
			this.reject_btn.visible = pending;
			this.unapprove_btn.visible = false;
			this.map_area.queue_draw();
		}

		private void on_reject_clicked()
		{
			if (this.active < 0 || this.active >= this.hunks.size) {
				return;
			}
			if (this.hunks.get(this.active).decision != HunkDecision.PENDING) {
				return;
			}
			var decided = this.active;
			this.hunks.get(decided).decision = HunkDecision.REJECTED;
			this.active = this.hunks.pending_after(decided);
			if (this.active >= 0) {
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
			}
			var pending = this.active >= 0;
			this.accept_btn.visible = pending;
			this.reject_btn.visible = pending;
			this.unapprove_btn.visible = false;
			this.map_area.queue_draw();
		}
	}
}
