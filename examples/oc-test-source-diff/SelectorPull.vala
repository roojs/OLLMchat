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

namespace OLLMapp
{
	/**
	 * Phone and tablet pull-over shared by {@link ProjectSelector}
	 * and {@link FilePullout}.
	 *
	 * Back arrow, title, the current selection, a page stack, and
	 * search at the bottom. The phone file page adds a close button
	 * and hides the arrow at the project root. Opening it does not
	 * focus search, so the keyboard stays down. Which edge it uses
	 * is still open.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var pull = new SelectorPull(Form.TABLET);
	 * cover.add_overlay(pull);
	 * }}}
	 */
	class SelectorPull : Gtk.Box
	{
		/**
		 * Which page search applies to: ''project'' or ''file''.
		 */
		public string kind = "project";

		/**
		 * Title in the top bar. The host sets this when a page opens.
		 */
		public Gtk.Label heading { get; private set; }

		/**
		 * Line under the top bar. The project page shows the current
		 * selection. The phone file page shows the path relative to
		 * the project, and hides this line at the project root.
		 */
		public Gtk.Label current { get; private set; }

		/**
		 * Left arrow. Hidden on the phone file page at the project
		 * root. Shown again below that root, and on the project page.
		 */
		public Gtk.Button previous { get; private set; }

		/**
		 * Closes the pull-over. The phone file page shows it. The
		 * project page hides it.
		 */
		public Gtk.Button close { get; private set; }

		/**
		 * Search entry along the bottom edge.
		 */
		public Gtk.SearchEntry search { get; private set; }

		/**
		 * Project page and file page. Each selector adds its own list.
		 */
		public Gtk.Stack pages { get; private set; }

		/**
		 * Back arrow. A handler that returns true keeps the pull-over
		 * open. Otherwise the pull-over closes.
		 */
		public signal bool back();

		/**
		 * Build the pull-over chrome for one layout.
		 *
		 * @param form Phone or tablet. Desktop does not show this.
		 */
		public SelectorPull(Form form)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.add_css_class("selector-pull");
			this.vexpand = true;
			this.visible = false;
			switch (form) {
				case Form.PHONE:
					this.hexpand = true;
					break;

				case Form.TABLET:
					this.halign = Gtk.Align.START;
					this.width_request = 420;
					break;

				default:
					break;
			}
			var pull_top = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				margin_start = 6,
				margin_end = 6,
				margin_top = 6,
			};
			this.previous = new Gtk.Button.from_icon_name("go-previous-symbolic") {
				can_focus = false,
				valign = Gtk.Align.CENTER,
				css_classes = { "flat" },
			};
			this.close = new Gtk.Button.from_icon_name("window-close-symbolic") {
				tooltip_text = "Close",
				can_focus = false,
				valign = Gtk.Align.CENTER,
				visible = false,
				css_classes = { "flat" },
			};
			this.heading = new Gtk.Label("") {
				hexpand = true,
				xalign = 0,
			};
			this.heading.add_css_class("title-2");
			pull_top.append(this.previous);
			pull_top.append(this.heading);
			pull_top.append(this.close);
			this.current = new Gtk.Label("Select project") {
				xalign = 0,
				ellipsize = Pango.EllipsizeMode.START,
				margin_start = 12,
				margin_end = 12,
				margin_top = 6,
				margin_bottom = 6,
			};
			this.current.add_css_class("caption");
			this.current.add_css_class("dim-label");
			this.pages = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				hhomogeneous = true,
				vhomogeneous = true,
			};
			this.search = new Gtk.SearchEntry() {
				placeholder_text = "Search",
				hexpand = true,
				margin_start = 8,
				margin_end = 8,
				margin_bottom = 8,
				margin_top = 8,
			};
			this.append(pull_top);
			this.append(this.current);
			this.append(this.pages);
			this.append(this.search);
			this.previous.clicked.connect(() => {
				if (this.back()) {
					return;
				}
				this.visible = false;
			});
			this.close.clicked.connect(() => {
				this.visible = false;
			});
		}
	}
}
