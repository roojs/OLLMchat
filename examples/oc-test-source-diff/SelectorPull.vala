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

/**
 * Phone and tablet pull-over shared by {@link ProjectSelector}
 * and {@link FileSelector}.
 *
 * Back arrow, title, the current selection, a page stack, and
 * search at the bottom. Opening it does not focus search, so the
 * keyboard stays down. Which edge it uses is still open.
 *
 * == Example ==
 *
 * {{{
 * var pull = new SelectorPull("tablet");
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
	 * Current selection under the top bar.
	 */
	public Gtk.Label current { get; private set; }

	/**
	 * Search entry along the bottom edge.
	 */
	public Gtk.SearchEntry search { get; private set; }

	/**
	 * Project page and file page. Each selector adds its own list.
	 */
	public Gtk.Stack pages { get; private set; }

	/**
	 * Build the pull-over chrome for one layout.
	 *
	 * @param form ''phone'' or ''tablet''. Desktop does not show this.
	 */
	public SelectorPull(string form)
	{
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
		this.add_css_class("selector-pull");
		this.vexpand = true;
		this.visible = false;
		switch (form) {
			case "phone":
				this.hexpand = true;
				break;

			case "tablet":
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
		var back = new Gtk.Button.from_icon_name("go-previous-symbolic");
		back.add_css_class("flat");
		this.heading = new Gtk.Label("") {
			hexpand = true,
			xalign = 0,
		};
		this.heading.add_css_class("title-2");
		pull_top.append(back);
		pull_top.append(this.heading);
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
		back.clicked.connect(() => {
			this.visible = false;
		});
	}
}
