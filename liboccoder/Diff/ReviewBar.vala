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

	/**
	 * Programmable quick-review feedback to the LLM (label, tooltip, prompt text).
	 * Does not change hunk or file review state — consumer sends prompt to the LLM.
	 */
	public class ReviewResponse : Object
	{
		public string label { get; set; default = ""; }
		public string tooltip { get; set; default = ""; }
		public string prompt { get; set; default = ""; }
		public bool is_bulk { get; set; default = false; }
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
		public signal void accept_all_files();
		public signal void reject_all_files();

		public signal void review_response(ReviewResponse response, int file_index, int hunk_index);

		private OLLMcoder.SourceView source_view;
		private HunkList hunks { get; set; default = new HunkList(); }
		private int active = -1;
		private int file_count = 1;
		private int file_index = 0;
		private bool mock_inactive = false;
		private HunkDecision[] file_bulk = {};
		private int map_height = 28;
		private int map_width = 0;
		private double map_gap_width = 0.0;
		private int hunk_line_sum = 0;
		private bool map_scroll_mode = false;
		private double map_scroll_x = 0.0;
		private double map_content_width = 0.0;
		private double map_drag_scroll_start = 0.0;

		private Gtk.Button file_prev;
		private Gtk.Button file_next;
		private Gtk.Label file_nav_label;
		private Gtk.Box file_nav;
		private Gtk.Box map_host;
		private Gtk.DrawingArea map_area;
		private Gtk.Button map_scroll_left;
		private Gtk.Button map_scroll_right;
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
		private Gtk.Button feedback_btn;
		private Gtk.PopoverMenu feedback_menu_popover;
		private GLib.Menu feedback_menu;
		private GLib.MenuItem[] feedback_menu_items = {};
		private uint feedback_popover_hide_id = 0;
		private Gtk.Box review_decision_box;
		private Gee.ArrayList<ReviewResponse> review_responses {
			get; set; default = new Gee.ArrayList<ReviewResponse>();
		}
		private GLib.SimpleActionGroup feedback_response_actions {
			get; set; default = new GLib.SimpleActionGroup();
		}

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
			this.file_bulk = new HunkDecision[this.file_count];
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
			this.map_scroll_left = new Gtk.Button() {
				icon_name = "go-previous-symbolic",
				tooltip_text = "Previous change",
				css_classes = { "oc-diff-map-scroll-btn" },
				visible = false,
			};
			this.map_scroll_left.clicked.connect(() => {
				if (this.hunks.size < 1) {
					return;
				}
				this.active = this.active < 1 ? this.hunks.size - 1 : this.active - 1;
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
				switch (this.hunks.get(this.active).decision) {
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
				if (this.map_scroll_mode) {
					var ah = this.hunks.get(this.active);
					var vw = (double) this.map_area.get_allocated_width();
					var max_scroll = this.map_content_width - vw;
					if (max_scroll < 0) {
						max_scroll = 0;
					}
					this.map_scroll_x = ah.map_start + ah.map_width * 0.5 - vw * 0.5;
					if (this.map_scroll_x < 0) {
						this.map_scroll_x = 0;
					}
					if (this.map_scroll_x > max_scroll) {
						this.map_scroll_x = max_scroll;
					}
					this.map_scroll_left.sensitive = this.map_scroll_x > 0.5;
					this.map_scroll_right.sensitive = this.map_scroll_x < max_scroll - 0.5;
				}
				this.map_area.queue_draw();
			});
			this.map_scroll_right = new Gtk.Button() {
				icon_name = "go-next-symbolic",
				tooltip_text = "Next change",
				css_classes = { "oc-diff-map-scroll-btn" },
				visible = false,
			};
			this.map_scroll_right.clicked.connect(() => {
				if (this.hunks.size < 1) {
					return;
				}
				this.active = (this.active + 1) % this.hunks.size;
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
				switch (this.hunks.get(this.active).decision) {
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
				if (this.map_scroll_mode) {
					var ah = this.hunks.get(this.active);
					var vw = (double) this.map_area.get_allocated_width();
					var max_scroll = this.map_content_width - vw;
					if (max_scroll < 0) {
						max_scroll = 0;
					}
					this.map_scroll_x = ah.map_start + ah.map_width * 0.5 - vw * 0.5;
					if (this.map_scroll_x < 0) {
						this.map_scroll_x = 0;
					}
					if (this.map_scroll_x > max_scroll) {
						this.map_scroll_x = max_scroll;
					}
					this.map_scroll_left.sensitive = this.map_scroll_x > 0.5;
					this.map_scroll_right.sensitive = this.map_scroll_x < max_scroll - 0.5;
				}
				this.map_area.queue_draw();
			});
			var map_click = new Gtk.GestureClick();
			map_click.pressed.connect((n, x, y) => {
				this.on_map_clicked(x);
			});
			this.map_area.add_controller(map_click);
			var map_drag = new Gtk.GestureDrag();
			map_drag.drag_begin.connect((start_x, start_y) => {
				this.map_drag_scroll_start = this.map_scroll_x;
			});
			map_drag.drag_update.connect((offset_x, offset_y) => {
				if (!this.map_scroll_mode) {
					return;
				}
				var vw = (double) this.map_area.get_allocated_width();
				var max_scroll = this.map_content_width - vw;
				if (max_scroll < 0) {
					max_scroll = 0;
				}
				this.map_scroll_x = this.map_drag_scroll_start - offset_x;
				if (this.map_scroll_x < 0) {
					this.map_scroll_x = 0;
				}
				if (this.map_scroll_x > max_scroll) {
					this.map_scroll_x = max_scroll;
				}
				this.map_scroll_left.sensitive = this.map_scroll_x > 0.5;
				this.map_scroll_right.sensitive = this.map_scroll_x < max_scroll - 0.5;
				this.map_area.queue_draw();
			});
			this.map_area.add_controller(map_drag);
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
			this.map_host.append(this.map_scroll_left);
			this.map_host.append(this.map_area);
			this.map_host.append(this.map_scroll_right);
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
			var file_section = new GLib.Menu();
			var accept_file = new GLib.MenuItem("Accept file changes", "bulk.accept-file");
			accept_file.set_icon(new GLib.ThemedIcon("emblem-ok-symbolic"));
			file_section.append_item(accept_file);
			var reject_file = new GLib.MenuItem("Reject file changes", "bulk.reject-file");
			reject_file.set_icon(new GLib.ThemedIcon("dialog-cancel-symbolic"));
			file_section.append_item(reject_file);
			var reset_file = new GLib.MenuItem("Reset", "bulk.reset-file");
			reset_file.set_icon(new GLib.ThemedIcon("edit-undo-symbolic"));
			file_section.append_item(reset_file);
			bulk_menu.append_section(null, file_section);
			if (this.file_count > 1) {
				var all_section = new GLib.Menu();
				var accept_all_files = new GLib.MenuItem(
					"Accept changes to all files", "bulk.accept-all-files");
				accept_all_files.set_icon(new GLib.ThemedIcon("emblem-ok-symbolic"));
				all_section.append_item(accept_all_files);
				var reject_all_files = new GLib.MenuItem(
					"Reject changes to all files", "bulk.reject-all-files");
				reject_all_files.set_icon(new GLib.ThemedIcon("dialog-cancel-symbolic"));
				all_section.append_item(reject_all_files);
				bulk_menu.append_section(null, all_section);
			}
			var bulk_actions = new GLib.SimpleActionGroup();
			var accept_file_action = new GLib.SimpleAction("accept-file", null);
			accept_file_action.activate.connect(() => {
				foreach (var hunk in this.hunks) {
					hunk.decision = HunkDecision.ACCEPTED;
				}
				if (this.file_index < this.file_bulk.length) {
					this.file_bulk[this.file_index] = HunkDecision.ACCEPTED;
				}
				this.active = -1;
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.map_area.queue_draw();
			});
			var reject_file_action = new GLib.SimpleAction("reject-file", null);
			reject_file_action.activate.connect(() => {
				foreach (var hunk in this.hunks) {
					hunk.decision = HunkDecision.REJECTED;
				}
				if (this.file_index < this.file_bulk.length) {
					this.file_bulk[this.file_index] = HunkDecision.REJECTED;
				}
				this.active = -1;
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.map_area.queue_draw();
			});
			var reset_file_action = new GLib.SimpleAction("reset-file", null);
			reset_file_action.activate.connect(() => {
				foreach (var hunk in this.hunks) {
					hunk.decision = HunkDecision.PENDING;
				}
				if (this.file_index < this.file_bulk.length) {
					this.file_bulk[this.file_index] = HunkDecision.PENDING;
				}
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
				((Gtk.Popover) this.bulk_menu_popover).popdown();
				this.map_area.queue_draw();
			});
			bulk_actions.add_action(accept_file_action);
			bulk_actions.add_action(reject_file_action);
			bulk_actions.add_action(reset_file_action);
			if (this.file_count > 1) {
				var accept_all_files_action = new GLib.SimpleAction("accept-all-files", null);
				accept_all_files_action.activate.connect(() => {
					for (var fi = 0; fi < this.file_bulk.length; fi++) {
						this.file_bulk[fi] = HunkDecision.ACCEPTED;
					}
					foreach (var hunk in this.hunks) {
						hunk.decision = HunkDecision.ACCEPTED;
					}
					this.active = -1;
					this.accept_btn.visible = false;
					this.reject_btn.visible = false;
					this.unapprove_btn.visible = false;
					((Gtk.Popover) this.bulk_menu_popover).popdown();
					this.map_area.queue_draw();
					this.accept_all_files();
				});
				var reject_all_files_action = new GLib.SimpleAction("reject-all-files", null);
				reject_all_files_action.activate.connect(() => {
					for (var fi = 0; fi < this.file_bulk.length; fi++) {
						this.file_bulk[fi] = HunkDecision.REJECTED;
					}
					foreach (var hunk in this.hunks) {
						hunk.decision = HunkDecision.REJECTED;
					}
					this.active = -1;
					this.accept_btn.visible = false;
					this.reject_btn.visible = false;
					this.unapprove_btn.visible = false;
					((Gtk.Popover) this.bulk_menu_popover).popdown();
					this.map_area.queue_draw();
					this.reject_all_files();
				});
				bulk_actions.add_action(accept_all_files_action);
				bulk_actions.add_action(reject_all_files_action);
			}
			this.insert_action_group("bulk", bulk_actions);
			this.bulk_menu_popover = new Gtk.PopoverMenu.from_model(bulk_menu);
			this.bulk_btn = new Gtk.Button() {
				icon_name = "open-menu-symbolic",
				tooltip_text = "Bulk review actions",
			};
			this.bulk_menu_popover.set_parent(this.bulk_btn);
			((Gtk.Popover) this.bulk_menu_popover).autohide = false;
			((Gtk.Popover) this.bulk_menu_popover).set_position(Gtk.PositionType.TOP);
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
				halign = Gtk.Align.FILL,
				valign = Gtk.Align.END,
				vexpand = true,
				hexpand = true,
				spacing = 8,
				css_classes = { "oc-diff-review-overlay" },
			};
			this.feedback_btn = new Gtk.Button.with_label("Feedback") {
				visible = false,
				tooltip_text = "Quick review feedback to the LLM",
			};
			var feedback_anchor_motion = new Gtk.EventControllerMotion();
			feedback_anchor_motion.enter.connect(() => {
				if (this.feedback_menu_popover == null || this.review_responses.size < 1) {
					return;
				}
				if (this.feedback_popover_hide_id != 0) {
					GLib.Source.remove(this.feedback_popover_hide_id);
					this.feedback_popover_hide_id = 0;
				}
				var hunk_ok = this.active >= 0 && this.active < this.hunks.size
					&& this.hunks.get(this.active).decision == HunkDecision.PENDING;
				for (var ri = 0; ri < this.review_responses.size; ri++) {
					var menu_action = this.feedback_response_actions.lookup(
						"response-%u".printf(ri)) as GLib.SimpleAction;
					if (menu_action == null) {
						continue;
					}
					var resp = this.review_responses.get(ri);
					if (resp.is_bulk) {
						menu_action.set_enabled(true);
						this.feedback_menu_items[ri].set_attribute(
							"tooltip", "s", resp.tooltip);
						continue;
					}
					menu_action.set_enabled(hunk_ok);
					this.feedback_menu_items[ri].set_attribute(
						"tooltip", "s",
						hunk_ok ? resp.tooltip : "Select a pending change");
				}
				this.feedback_menu_popover.popup();
			});
			feedback_anchor_motion.leave.connect(() => {
				if (this.feedback_menu_popover == null) {
					return;
				}
				if (this.feedback_popover_hide_id != 0) {
					GLib.Source.remove(this.feedback_popover_hide_id);
				}
				this.feedback_popover_hide_id = GLib.Timeout.add_seconds(3, () => {
					((Gtk.Popover) this.feedback_menu_popover).popdown();
					this.feedback_popover_hide_id = 0;
					return false;
				});
			});
			this.feedback_btn.add_controller(feedback_anchor_motion);
			this.review_decision_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				halign = Gtk.Align.END,
				spacing = 8,
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
			this.review_decision_box.append(this.accept_btn);
			this.review_decision_box.append(this.reject_btn);
			this.review_decision_box.append(this.unapprove_btn);
			var overlay_spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true,
			};
			this.review_overlay.append(this.feedback_btn);
			this.review_overlay.append(overlay_spacer);
			this.review_overlay.append(this.review_decision_box);
		}

		/**
		 * Programmable review-response menu (Feedback popover).
		 * Emits {@link review_response} only — does not accept/reject/revert.
		 *
		 * @param items quick-review actions supplied by the owner
		 */
		public void responses(Gee.ArrayList<ReviewResponse> items)
		{
			this.review_responses.clear();
			this.feedback_menu_items = {};
			for (var ri = 0; ri < items.size; ri++) {
				this.review_responses.add(items.get(ri));
			}
			var menu = new GLib.Menu();
			this.feedback_menu = menu;
			for (var ri = 0; ri < this.review_responses.size; ri++) {
				var resp_action = new GLib.SimpleAction("response-%u".printf(ri), null);
				resp_action.set_data<ReviewResponse>(
					"review-response", this.review_responses.get(ri));
				resp_action.set_enabled(this.review_responses.get(ri).is_bulk);
				resp_action.activate.connect(() => {
					var resp = resp_action.get_data<ReviewResponse>("review-response");
					if (resp.is_bulk) {
						this.review_response(resp, this.file_index, -1);
						((Gtk.Popover) this.feedback_menu_popover).popdown();
						return;
					}
					if (this.active < 0 || this.active >= this.hunks.size) {
						return;
					}
					if (this.hunks.get(this.active).decision != HunkDecision.PENDING) {
						return;
					}
					this.review_response(resp, this.file_index, this.active);
					this.next();
					((Gtk.Popover) this.feedback_menu_popover).popdown();
				});
				this.feedback_response_actions.add_action(resp_action);
				var resp_item = new GLib.MenuItem(
					this.review_responses.get(ri).label,
					"feedback-resp.response-%u".printf(ri));
				if (this.review_responses.get(ri).tooltip != "") {
					resp_item.set_attribute(
						"tooltip", "s", this.review_responses.get(ri).tooltip);
				}
				menu.append_item(resp_item);
				this.feedback_menu_items += resp_item;
			}
			this.feedback_btn.insert_action_group("feedback-resp", this.feedback_response_actions);
			this.feedback_menu_popover = new Gtk.PopoverMenu.from_model(menu);
			this.feedback_menu_popover.set_parent(this.feedback_btn);
			((Gtk.Popover) this.feedback_menu_popover).autohide = false;
			((Gtk.Popover) this.feedback_menu_popover).set_position(Gtk.PositionType.TOP);
			var feedback_popover_motion = new Gtk.EventControllerMotion();
			feedback_popover_motion.enter.connect(() => {
				if (this.feedback_popover_hide_id != 0) {
					GLib.Source.remove(this.feedback_popover_hide_id);
					this.feedback_popover_hide_id = 0;
				}
			});
			feedback_popover_motion.leave.connect(() => {
				if (this.feedback_popover_hide_id != 0) {
					GLib.Source.remove(this.feedback_popover_hide_id);
				}
				this.feedback_popover_hide_id = GLib.Timeout.add_seconds(3, () => {
					((Gtk.Popover) this.feedback_menu_popover).popdown();
					this.feedback_popover_hide_id = 0;
					return false;
				});
			});
			(this.feedback_menu_popover as Gtk.Widget).add_controller(feedback_popover_motion);
			this.feedback_btn.visible = this.review_responses.size > 0;
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
			var bulk_decision = HunkDecision.PENDING;
			if (this.file_index < this.file_bulk.length) {
				bulk_decision = this.file_bulk[this.file_index];
			}
			foreach (var patch in differ.patches) {
				var band = new HunkBand(patch) {
					band_index = bi,
				};
				if (bulk_decision != HunkDecision.PENDING) {
					band.decision = bulk_decision;
				}
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
				this.map_scroll_left.visible = false;
				this.map_scroll_right.visible = false;
				this.pending_label.label = "%d changes pending review".printf(
					this.file_count);
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.feedback_btn.visible = false;
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
			this.feedback_btn.visible = this.review_responses.size > 0;
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
			var half_sq = sq * 0.5;
			var weight_sum = int.max(1, this.hunk_line_sum);
			var gap_count = this.hunks.size > 1 ? this.hunks.size - 1 : 0;
			var pad_slots = gap_count + 2;
			var band_total_sq = (double) weight_sum * sq;
			var width = (double) w;
			var gap = sq;
			if (band_total_sq + (double) pad_slots * sq > width) {
				gap = half_sq;
			}
			var fits_square = band_total_sq + (double) pad_slots * gap <= width;
			var needs_scroll = !fits_square
				&& (width - (double) pad_slots * half_sq) / (double) weight_sum < half_sq;
			this.map_scroll_mode = needs_scroll;
			this.map_gap_width = needs_scroll ? half_sq : gap;
			this.map_scroll_left.visible = needs_scroll;
			this.map_scroll_right.visible = needs_scroll;
			if (!needs_scroll) {
				this.map_scroll_x = 0.0;
			}
			var layout_gap = this.map_gap_width;
			var avail = needs_scroll
				? 0.0
				: double.max(width - (double) pad_slots * layout_gap, half_sq);
			var pos = layout_gap;
			foreach (var hunk in this.hunks) {
				pos += hunk.band_index > 0 ? layout_gap : 0.0;
				hunk.map_start = pos;
				hunk.map_width = needs_scroll
					? (double) hunk.line_count * half_sq
					: (fits_square
						? (double) hunk.line_count * sq
						: avail * (double) hunk.line_count / (double) weight_sum);
				pos += hunk.map_width;
			}
			if (!needs_scroll) {
				this.map_area.queue_draw();
				return;
			}
			this.map_content_width = pos + half_sq;
			var max_scroll = this.map_content_width - width;
			if (max_scroll < 0) {
				max_scroll = 0;
			}
			if (this.active >= 0 && this.active < this.hunks.size) {
				var ah = this.hunks.get(this.active);
				this.map_scroll_x = ah.map_start + ah.map_width * 0.5 - width * 0.5;
				if (this.map_scroll_x < 0) {
					this.map_scroll_x = 0;
				}
				if (this.map_scroll_x > max_scroll) {
					this.map_scroll_x = max_scroll;
				}
			}
			this.map_scroll_left.sensitive = this.map_scroll_x > 0.5;
			this.map_scroll_right.sensitive = this.map_scroll_x < max_scroll - 0.5;
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
			cr.save();
			cr.rectangle(0.0, 0.0, (double) w, (double) h);
			cr.clip();
			if (this.map_scroll_mode) {
				cr.translate(-this.map_scroll_x, 0.0);
			}
			if (this.map_gap_width > 0.0) {
				cr.set_source_rgb(1.0, 1.0, 1.0);
				cr.rectangle(0.0, 0.0, this.map_gap_width, (double) h);
				cr.fill();
				if (this.hunks.size > 0) {
					var last = this.hunks.get(this.hunks.size - 1);
					cr.rectangle(last.map_start + last.map_width, 0.0,
						this.map_gap_width, (double) h);
					cr.fill();
				}
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
			cr.restore();
		}

		private void next()
		{
			this.active = this.hunks.pending_after(this.active);
			if (this.active >= 0) {
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
			}
			var pending = this.active >= 0;
			this.accept_btn.visible = pending;
			this.reject_btn.visible = pending;
			this.unapprove_btn.visible = false;
			if (!this.map_scroll_mode || this.active < 0) {
				this.map_area.queue_draw();
				return;
			}
			var ah = this.hunks.get(this.active);
			var vw = (double) this.map_area.get_allocated_width();
			var max_scroll = this.map_content_width - vw;
			if (max_scroll < 0) {
				max_scroll = 0;
			}
			this.map_scroll_x = ah.map_start + ah.map_width * 0.5 - vw * 0.5;
			if (this.map_scroll_x < 0) {
				this.map_scroll_x = 0;
			}
			if (this.map_scroll_x > max_scroll) {
				this.map_scroll_x = max_scroll;
			}
			this.map_scroll_left.sensitive = this.map_scroll_x > 0.5;
			this.map_scroll_right.sensitive = this.map_scroll_x < max_scroll - 0.5;
			this.map_area.queue_draw();
		}

		private void on_map_clicked(double x)
		{
			if (this.mock_inactive || this.hunks.size < 1) {
				return;
			}
			var map_x = this.map_scroll_mode ? x + this.map_scroll_x : x;
			var i = this.hunks.index_at(map_x);
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
			if (this.map_scroll_mode) {
				var ah = this.hunks.get(i);
				var vw = (double) this.map_area.get_allocated_width();
				var max_scroll = this.map_content_width - vw;
				if (max_scroll < 0) {
					max_scroll = 0;
				}
				this.map_scroll_x = ah.map_start + ah.map_width * 0.5 - vw * 0.5;
				if (this.map_scroll_x < 0) {
					this.map_scroll_x = 0;
				}
				if (this.map_scroll_x > max_scroll) {
					this.map_scroll_x = max_scroll;
				}
				this.map_scroll_left.sensitive = this.map_scroll_x > 0.5;
				this.map_scroll_right.sensitive = this.map_scroll_x < max_scroll - 0.5;
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
			this.next();
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
			this.next();
		}
	}
}
