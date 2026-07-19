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
 * One WebView browser session for a chat (load, settle, a11y dump, fill, press).
 *
 * Phase 2 scaffold: load + fixed settle delay; dump / fill / press stubs for Phase 3.
 *
 * == Example ==
 *
 * {{{
 * var browser = new OLLMwebkit.Browser();
 * yield browser.load("https://example.com/");
 * var md = yield browser.dump("a11y");
 * }}}
 */
public class OLLMwebkit.Browser : Gtk.Box
{
	/**
	 * Live WebKit view for this session.
	 */
	public WebKit.WebView web_view { get; private set; }

	/**
	 * Per-host Cookie header map (Snappr site_cookies pattern). Empty until Phase 4.
	 */
	public Gee.HashMap<string, string> site_cookies {
		get;
		private set;
		default = new Gee.HashMap<string, string>();
	}

	public Browser()
	{
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
		this.web_view = new WebKit.WebView();
		this.web_view.hexpand = true;
		this.web_view.vexpand = true;
		this.append(this.web_view);
	}

	/**
	 * Load ''url'' and wait the v1 settle delay (~2 seconds).
	 *
	 * @param url absolute http(s) URL
	 * @throws GLib.Error on load failure (Phase 3+)
	 */
	public async void load(string url) throws GLib.Error
	{
		this.web_view.load_uri(url);
		GLib.Timeout.add(2000, () => {
			GLib.Idle.add(this.load.callback);
			return GLib.Source.REMOVE;
		});
		yield;
	}

	/**
	 * Return page content for ''format'' (a11y / html / markdown). Stub until Phase 3.
	 *
	 * @param format output format string
	 * @return page dump text
	 * @throws GLib.Error when format is unsupported or dump fails
	 */
	public async string dump(string format) throws GLib.Error
	{
		yield;
		if (format != "a11y" && format != "html" && format != "markdown") {
			throw new GLib.IOError.INVALID_ARGUMENT("Unsupported format: %s", format);
		}
		var uri = this.web_view.uri != null ? this.web_view.uri : "";
		var title = this.web_view.title != null ? this.web_view.title : "";
		return
@"# Page
- URL: $(uri)
- Title: $(title)

## Content
(a11y dump — Phase 3)

## References
";
	}

	/**
	 * Apply fill map via accessibility. Stub until Phase 3.
	 *
	 * @param fields press-ref id (string key) → text to type
	 * @throws GLib.Error when fill is not yet implemented or fails
	 */
	public async void fill(Gee.HashMap<string, string> fields) throws GLib.Error
	{
		yield;
		throw new GLib.IOError.NOT_SUPPORTED("fill (%d entries) — Phase 3", fields.size);
	}

	/**
	 * Activate press-ref ''id''. Stub until Phase 3.
	 *
	 * @param id press id from the last a11y dump
	 * @throws GLib.Error when press is not yet implemented or fails
	 */
	public async void press(int id) throws GLib.Error
	{
		yield;
		throw new GLib.IOError.NOT_SUPPORTED("press %d — Phase 3", id);
	}
}
