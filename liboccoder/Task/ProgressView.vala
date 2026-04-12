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
	 * {@link Gtk.ColumnView} (title and stage columns). Built with an empty
	 * placeholder model; call {@link #set_runner} to attach {@link Skill.Runner.progress}.
	 */
	public class ProgressView : Gtk.Box
	{
		private Gtk.SingleSelection progress_selection;
		private Gtk.ColumnView column_view;
		private Gtk.ScrolledWindow scrolled;

		/**
		 * Creates the column view with an empty placeholder list. Call
		 * {@link #set_runner} before expecting rows.
		 */
		public ProgressView()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			var placeholder = new GLib.ListStore(typeof(ProgressItem));
			this.progress_selection = new Gtk.SingleSelection(placeholder);
			this.column_view = new Gtk.ColumnView(this.progress_selection) {
				vexpand = true,
				hexpand = true,
				show_row_separators = true,
				single_click_activate = false,
				enable_rubberband = false
			};

			var title_factory = new Gtk.SignalListItemFactory();
			title_factory.setup.connect((obj) => {
				((Gtk.ListItem) obj).set_child(new Gtk.Label("") {
					halign = Gtk.Align.START,
					hexpand = true,
					xalign = 0,
					ellipsize = Pango.EllipsizeMode.END,
					single_line_mode = true
				});
			});
			title_factory.bind.connect((obj) => {
				var li = (Gtk.ListItem) obj;
				((Gtk.Label) li.child).set_data<GLib.Binding>(
					"ollm-column-bind",
					((ProgressItem) li.item).bind_property(
						"title",
						(Gtk.Label) li.child,
						"label",
						GLib.BindingFlags.SYNC_CREATE));
			});
			title_factory.unbind.connect((obj) => {
				var b = ((Gtk.Label) ((Gtk.ListItem) obj).child).get_data<GLib.Binding>(
					"ollm-column-bind");
				if (b == null) {
					return;
				}
				b.unbind();
				((Gtk.Label) ((Gtk.ListItem) obj).child).set_data<GLib.Binding>(
					"ollm-column-bind",
					null);
			});

			var stage_factory = new Gtk.SignalListItemFactory();
			stage_factory.setup.connect((obj) => {
				((Gtk.ListItem) obj).set_child(new Gtk.Label("") {
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
				((Gtk.Label) li.child).set_data<GLib.Binding>(
					"ollm-column-bind",
					((ProgressItem) li.item).bind_property(
						"status_str",
						(Gtk.Label) li.child,
						"label",
						GLib.BindingFlags.SYNC_CREATE));
			});
			stage_factory.unbind.connect((obj) => {
				var b = ((Gtk.Label) ((Gtk.ListItem) obj).child).get_data<GLib.Binding>(
					"ollm-column-bind");
				if (b == null) {
					return;
				}
				b.unbind();
				((Gtk.Label) ((Gtk.ListItem) obj).child).set_data<GLib.Binding>(
					"ollm-column-bind",
					null);
			});

			this.column_view.append_column(new Gtk.ColumnViewColumn("Title", title_factory));
			this.column_view.append_column(new Gtk.ColumnViewColumn("Stage", stage_factory));

			this.scrolled = new Gtk.ScrolledWindow() {
				vexpand = false,
				hexpand = true,
				has_frame = true
			};
			this.scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
			this.scrolled.set_min_content_height(48);
			this.scrolled.set_child(this.column_view);
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
			this.progress_selection = new Gtk.SingleSelection(runner.progress);
			this.column_view.model = this.progress_selection;
		}
	}
}
