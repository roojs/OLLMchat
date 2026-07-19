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
 * Owns the Gtk.Stack and primary {@link Browser} for one chat (Snappr BrowserStack).
 *
 * v1 uses primary only (no crawl pool). Globe / Cloudflare promote use {@link promote}.
 *
 * == Example ==
 *
 * {{{
 * var stack = new OLLMwebkit.BrowserStack();
 * window.set_child(stack);
 * yield stack.primary.load("https://example.com/");
 * }}}
 */
public class OLLMwebkit.BrowserStack : Gtk.Box
{
	/**
	 * Stack holding the primary browser (and future pages if needed).
	 */
	public Gtk.Stack stack { get; private set; }

	/**
	 * Foreground browser for tool calls and the globe view.
	 */
	public OLLMwebkit.Browser primary { get; private set; }

	public BrowserStack()
	{
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
		this.stack = new Gtk.Stack();
		this.stack.hexpand = true;
		this.stack.vexpand = true;
		this.primary = new OLLMwebkit.Browser();
		this.stack.add_named(this.primary, "primary");
		this.stack.visible_child = this.primary;
		this.append(this.stack);
	}

	/**
	 * Make the primary browser the visible stack child (CF / globe handoff).
	 */
	public void promote()
	{
		this.stack.visible_child = this.primary;
	}
}
