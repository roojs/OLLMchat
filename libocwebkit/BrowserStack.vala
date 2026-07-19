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
 * WebView host — primary browser in a {@link Gtk.Stack} (Snappr BrowserStack).
 *
 * v1 uses primary only (no crawl pool). Owns construction of {@link Browser}.
 * Session {@link site_cookies} are shared with {@link Browser.primary}.
 * Cloudflare block → {@link promote} + {@link cloudflare_blocked}; clear →
 * {@link cloudflare_cleared}.
 *
 * == Example ==
 *
 * {{{
 * var stack = new OLLMwebkit.BrowserStack();
 * window.set_child(stack);
 * yield stack.primary.load("https://example.com/");
 * stack.promote();
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

	/**
	 * Shared per-host cookies for this chat session (Snappr stack map).
	 */
	public Gee.HashMap<string, string> site_cookies {
		get;
		private set;
		default = new Gee.HashMap<string, string>();
	}

	/**
	 * URI of the visible browser changed (load or promote).
	 */
	public signal void visible_uri_changed(string uri);

	/**
	 * Primary browser hit a Cloudflare challenge.
	 *
	 * @param browser browser that reported the block
	 */
	public signal void cloudflare_blocked(OLLMwebkit.Browser browser);

	/**
	 * Cloudflare challenge cleared on the primary browser.
	 */
	public signal void cloudflare_cleared();

	public BrowserStack()
	{
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true, vexpand: true);
		this.stack = new Gtk.Stack() {
			hexpand = true,
			vexpand = true,
		};
		this.append(this.stack);
		this.primary = new OLLMwebkit.Browser(this);
		this.stack.add_named(this.primary, "primary");
		this.stack.visible_child = this.primary;
		this.primary.uri_changed.connect((uri) => {
			if (this.stack.visible_child != this.primary) {
				return;
			}
			this.visible_uri_changed(uri);
		});
		this.primary.cloudflare.notify["is-blocked"].connect(() => {
			if (!this.primary.cloudflare.is_blocked) {
				return;
			}
			this.promote();
			this.cloudflare_blocked(this.primary);
		});
		this.primary.cloudflare.cleared.connect(() => {
			this.cloudflare_cleared();
		});
	}

	/**
	 * Make the primary browser the visible stack child (CF / globe handoff).
	 */
	public void promote()
	{
		this.stack.visible_child = this.primary;
		this.visible_uri_changed(this.primary.current_uri);
	}
}
