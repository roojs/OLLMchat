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

namespace OLLMcoder.Task
{
	/**
	 * Read-only task progress strip: {@link Gtk.ScrolledWindow} plus
	 * {@link Gtk.ColumnView} (title and stage columns). Root {@link GLib.ListModel}
	 * is wrapped in {@link Gtk.TreeListModel} with auto-expand so
	 * {@link ProgressItem.children} (e.g. {@link Tool} under {@link Details}) stay
	 * visible while tasks run without manual expand. Built with a placeholder model;
	 * call {@link #set_runner} to attach {@link Skill.Runner.progress}.
	 */
	public class ProgressView : Gtk.Box
	{
		private Gtk.SingleSelection progress_selection;
		private Gtk.ColumnView column_view;
		private Gtk.ScrolledWindow scrolled;

		public weak OLLMchat.ChatUserInterface? window;
		private Gtk.GestureClick click_gesture;
		private Gtk.EventControllerKey key_controller;

		/**
		 * Creates the column view with an empty placeholder list. Call
		 * {@link #set_runner} before expecting rows.
		 */
		public ProgressView()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.add_css_class("oc-task-progress");
			var placeholder = new GLib.ListStore(typeof(ProgressItem));
			this.progress_selection = new Gtk.SingleSelection(
				new Gtk.TreeListModel(placeholder, false, true,
					(item) => {
						var pi = (ProgressItem) item;
						if (pi.children.get_n_items() == 0) {
							return null;
						}
						return pi.children;
					}));
			this.column_view = new Gtk.ColumnView(this.progress_selection) {
				vexpand = true,
				hexpand = true,
				show_row_separators = true,
				single_click_activate = false,
				enable_rubberband = false
			};

			var title_factory = new Gtk.SignalListItemFactory();
			title_factory.setup.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				li.activatable = false;
				var expander = new Gtk.TreeExpander();
				var label = new Gtk.Label("") {
					halign = Gtk.Align.START,
					hexpand = true,
					xalign = 0,
					ellipsize = Pango.EllipsizeMode.END,
					single_line_mode = true
				};
				expander.set_child(label);
				li.set_child(expander);
			});
			title_factory.bind.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				var expander = (Gtk.TreeExpander) li.child;
				var label = (Gtk.Label) expander.child;
				var row = (Gtk.TreeListRow) li.item;
				expander.set_list_row(row);
				var pi = (ProgressItem) row.get_item();
				pi.bind_property(
					"title",
					label,
					"label",
					GLib.BindingFlags.SYNC_CREATE);
				pi.bind_property(
					"tooltip_text",
					label,
					"tooltip-text",
					GLib.BindingFlags.SYNC_CREATE);
			});
			title_factory.unbind.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				var expander = (Gtk.TreeExpander) li.child;
				expander.set_list_row(null);
			});

			var stage_factory = new Gtk.SignalListItemFactory();
			stage_factory.setup.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				li.activatable = false;
				li.set_child(new Gtk.Label("") {
					halign = Gtk.Align.START,
					hexpand = true,
					xalign = 0,
					ellipsize = Pango.EllipsizeMode.END,
					single_line_mode = true,
					use_markup = true
				});
			});
			stage_factory.bind.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				var row = (Gtk.TreeListRow) li.item;
				var cell = (Gtk.Label) li.child;
				cell.set_data<Gtk.TreeListRow>("progress-row", row);
				var pi = (ProgressItem) row.get_item();
				pi.bind_property(
					"status_str",
					cell,
					"label",
					GLib.BindingFlags.SYNC_CREATE);
			});
			var title_column = new Gtk.ColumnViewColumn("Title", title_factory);
			title_column.expand = true;
			this.column_view.append_column(title_column);
			var stage_column = new Gtk.ColumnViewColumn("Stage", stage_factory);
			this.column_view.append_column(stage_column);

			this.scrolled = new Gtk.ScrolledWindow() {
				vexpand = false,
				hexpand = true,
				has_frame = true
			};
			this.scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
			// Interim: ~3× prior testing height; policy in docs/plans/done/7.14.4-DONE-chatview-integration.md.
			this.scrolled.set_min_content_height(288);
			this.scrolled.set_child(this.column_view);
			this.click_gesture = new Gtk.GestureClick();
			this.column_view.add_controller(this.click_gesture);
			this.click_gesture.released.connect((n_press, x, y) => {
				this.column_view.grab_focus();
				var picked = this.column_view.pick((float) x, (float) y, Gtk.PickFlags.DEFAULT);
				if (picked == null) {
					GLib.debug("pick miss");
					return;
				}
				GLib.debug("pick type=%s", picked.get_type().name());
				while (picked != null && !(picked is Gtk.ColumnView)) {
					Gtk.TreeListRow? row = null;
					var expander_hit = picked as Gtk.TreeExpander;
					if (expander_hit != null) {
						row = expander_hit.get_list_row();
					}
					if (row == null) {
						row = ((GLib.Object) picked).get_data<Gtk.TreeListRow>("progress-row");
					}
					if (row == null) {
						GLib.debug("walk type=%s progress-row=no", picked.get_type().name());
						picked = picked.get_parent();
						continue;
					}
					GLib.debug("select position=%u", row.get_position());
					this.select_row(row.get_position());
					break;
				}
				if (picked != null && picked is Gtk.ColumnView) {
					GLib.debug("walk stopped at ColumnView without row");
				}
			});

			this.key_controller = new Gtk.EventControllerKey();
			this.key_controller.propagation_phase = Gtk.PropagationPhase.CAPTURE;
			this.column_view.add_controller(this.key_controller);
			this.key_controller.key_pressed.connect((keyval, keycode, state) => {
				var up = keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up;
				var down = keyval == Gdk.Key.Down || keyval == Gdk.Key.KP_Down;
				if (!up && !down) {
					return false;
				}
				var m = this.progress_selection.model;
				var n = m.get_n_items();
				var pos = this.progress_selection.selected;
				if (up) {
					if (pos == Gtk.INVALID_LIST_POSITION || pos == 0) {
						return true;
					}
					var row = (Gtk.TreeListRow) m.get_item(pos);
					if (row.get_depth() > 0) {
						this.select_row(row.get_parent().get_position());
					} else {
						this.select_row(pos - 1);
					}
					return true;
				}
				if (pos == Gtk.INVALID_LIST_POSITION) {
					this.select_row(0);
					return true;
				}
				var row = (Gtk.TreeListRow) m.get_item(pos);
				var pi = (ProgressItem) row.get_item();
				if (pi.children.get_n_items() > 0) {
					row.expanded = true;
				}
				if (pos + 1 < n) {
					this.select_row(pos + 1);
				}
				return true;
			});

			this.append(this.scrolled);
		}

		/**
		 * Binds the column view to {@link Skill.Runner.progress} (first activation
		 * and every re-activation, e.g. new session).
		 *
		 * @param runner the active skill runner
		 */
		public void set_runner(OLLMcoder.Skill.Runner runner)
		{
			this.progress_selection = new Gtk.SingleSelection(
				new Gtk.TreeListModel(runner.progress, false, true,
					(item) => {
						var pi = (ProgressItem) item;
						if (pi.children.get_n_items() == 0) {
							return null;
						}
						return pi.children;
					}));
			this.column_view.model = this.progress_selection;
		}

		private void select_row(uint pos)
		{
			var m = this.progress_selection.model;
			if (pos >= m.get_n_items()) {
				return;
			}
			this.progress_selection.selected = pos;
			var pi = (ProgressItem) ((Gtk.TreeListRow) m.get_item(pos)).get_item();
			if (this.window != null) {
				GLib.debug("select_row scroll msg_idx=%d", pi.msg_idx);
				this.window.scroll_to_message(pi.msg_idx);
			}
		}
	}
}
