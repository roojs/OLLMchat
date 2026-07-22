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

#if ANDROID
using AndroidAtspi;
#elif WINDOWS
using Win32Atspi;
#else
using Atspi;
#endif

/**
 * Accessibility dump / fill / press for {@link Browser}.
 *
 * Platform tree via ''using'' ({@link Atspi} / {@link Win32Atspi} /
 * {@link AndroidAtspi}) — same shape as {@link A11yParse}. Linux runs the
 * walk on a worker thread (main-thread AT-SPI deadlocks; set
 * ''GTK_A11Y=atspi'' before GTK init). Windows / Android stay on the UI
 * thread (COM / JNI). No page JavaScript.
 *
 * == Example ==
 *
 * {{{
 * var a11y = new OLLMwebkit.A11y();
 * var md = yield a11y.dump(uri, title);
 * yield a11y.fill(fields);
 * yield a11y.press(3);
 * }}}
 */
public class OLLMwebkit.A11y : GLib.Object
{
	/**
	 * Press-ref id → child-index route from the AT-SPI application root.
	 */
	public Gee.HashMap<int, Gee.ArrayList<int>> press_routes {
		get;
		private set;
		default = new Gee.HashMap<int, Gee.ArrayList<int>>();
	}

	/**
	 * Press-ref id → a11y label from the last dump (permission questions).
	 */
	public Gee.HashMap<int, string> press_labels {
		get;
		private set;
		default = new Gee.HashMap<int, string>();
	}

	/**
	 * Host widget whose toplevel is presented before keyboard fill.
	 */
	public Gtk.Widget host { get; set; }

	static bool atspi_ready = false;

	/**
	 * Project the page accessibility tree to a11y markdown.
	 *
	 * @param url current page URL
	 * @param title document title hint (may be empty)
	 * @return Content + References markdown
	 * @throws GLib.Error when the a11y tree cannot be read
	 */
	public async string dump(string url, string title) throws GLib.Error
	{
#if ANDROID || WINDOWS
		return this.dump_sync(url, title);
#else
		GLib.SourceFunc callback = dump.callback;
		GLib.Error? thread_error = null;
		var result = "";
		new GLib.Thread<bool>("ocwebkit-a11y-dump", () => {
			try {
				result = this.dump_sync(url, title);
			} catch (GLib.Error e) {
				thread_error = e;
			}
			Idle.add((owned) callback);
			return true;
		});
		yield;
		if (thread_error != null) {
			throw thread_error;
		}
		return result;
#endif
	}

	/**
	 * Fill press-refs (set_text_contents when available, else focus + keyboard).
	 *
	 * @param fields press-ref id (string key) → text
	 * @throws GLib.Error when a ref is missing or input fails
	 */
	public async void fill(Gee.HashMap<string, string> fields) throws GLib.Error
	{
		if (this.host.get_root() is Gtk.Window) {
			((Gtk.Window) this.host.get_root()).present();
		}
#if ANDROID || WINDOWS
		this.fill_sync(fields);
#else
		GLib.SourceFunc callback = fill.callback;
		GLib.Error? thread_error = null;
		new GLib.Thread<bool>("ocwebkit-a11y-fill", () => {
			try {
				this.fill_sync(fields);
			} catch (GLib.Error e) {
				thread_error = e;
			}
			Idle.add((owned) callback);
			return true;
		});
		yield;
		if (thread_error != null) {
			throw thread_error;
		}
#endif
	}

	/**
	 * Activate a press-ref via the platform Action / Invoke path.
	 *
	 * @param id press id from the last dump
	 * @throws GLib.Error when the ref is missing or action fails
	 */
	public async void press(int id) throws GLib.Error
	{
#if ANDROID || WINDOWS
		this.press_sync(id);
#else
		GLib.SourceFunc callback = press.callback;
		GLib.Error? thread_error = null;
		new GLib.Thread<bool>("ocwebkit-a11y-press", () => {
			try {
				this.press_sync(id);
			} catch (GLib.Error e) {
				thread_error = e;
			}
			Idle.add((owned) callback);
			return true;
		});
		yield;
		if (thread_error != null) {
			throw thread_error;
		}
#endif
	}

	/**
	 * Worker / UI-thread body for {@link dump}.
	 *
	 * @param url current page URL
	 * @param title document title hint
	 * @return a11y markdown
	 * @throws GLib.Error when the tree cannot be read
	 */
	private string dump_sync(string url, string title) throws GLib.Error
	{
		if (!A11y.atspi_ready) {
			init();
			A11y.atspi_ready = true;
		}

		Accessible? app = null;
		var desktop = get_desktop(0);
		for (var i = 0; i < desktop.get_child_count(); i++) {
			var candidate = desktop.get_child_at_index(i);
			if (candidate.get_process_id() != (uint) Posix.getpid()) {
				continue;
			}
			app = candidate;
			break;
		}
		if (app == null) {
			throw new GLib.IOError.FAILED("a11y: no application for pid %u", (uint) Posix.getpid());
		}

		var walk_root = app;
		var walk_route = new Gee.ArrayList<int>();
		var find_acc = new Gee.ArrayList<Accessible>();
		var find_route = new Gee.ArrayList<Gee.ArrayList<int>>();
		find_acc.add(app);
		find_route.add(walk_route);
		while (find_acc.size > 0) {
			var cur = find_acc.remove_at(find_acc.size - 1);
			var cur_route = find_route.remove_at(find_route.size - 1);
			var role_name = cur.get_role_name();
			if (role_name == "document text" || role_name == "document frame") {
				walk_root = cur;
				walk_route = cur_route;
				break;
			}
			var child_count = cur.get_child_count();
			if (child_count <= 0) {
				continue;
			}
			for (var j = 0; j < child_count; j++) {
				find_acc.add(cur.get_child_at_index(j));
				var next_route = new Gee.ArrayList<int>();
				foreach (var part in cur_route) {
					next_route.add(part);
				}
				next_route.add(j);
				find_route.add(next_route);
			}
		}

		var parse = new A11yParse(walk_root, walk_route);
		parse.walk();
		this.press_routes = parse.press_routes;
		this.press_labels = parse.press_labels;

		if (title == "") {
			title = walk_root.get_name() != null ? walk_root.get_name() : "";
		}
		return "# Page\n- URL: " + url + "\n- Title: " + title
			+ "\n\n## Content\n" + parse.content
			+ "\n## References\n" + parse.refs;
	}

	/**
	 * Worker / UI-thread body for {@link fill}.
	 *
	 * @param fields press-ref id → text
	 * @throws GLib.Error when a ref is missing or input fails
	 */
	private void fill_sync(Gee.HashMap<string, string> fields) throws GLib.Error
	{
		if (!A11y.atspi_ready) {
			init();
			A11y.atspi_ready = true;
		}

		Accessible? app = null;
		var desktop = get_desktop(0);
		for (var i = 0; i < desktop.get_child_count(); i++) {
			var candidate = desktop.get_child_at_index(i);
			if (candidate.get_process_id() != (uint) Posix.getpid()) {
				continue;
			}
			app = candidate;
			break;
		}
		if (app == null) {
			throw new GLib.IOError.FAILED("a11y: no application for pid %u", (uint) Posix.getpid());
		}

		var frame = app.get_child_at_index(0);
		for (var ai = 0; ai < frame.get_n_actions(); ai++) {
			if (frame.get_action_name(ai) != "default.activate") {
				continue;
			}
			frame.do_action(ai);
			break;
		}
		// Window present + frame activate need a beat before key synth lands.
		GLib.Thread.usleep(100000);

		foreach (var key in fields.keys) {
			var press_id = int.parse(key);
			if (press_id <= 0 || !this.press_routes.has_key(press_id)) {
				throw new GLib.IOError.INVALID_ARGUMENT("Unknown fill press-ref %s", key);
			}
			var acc = app;
			foreach (var index in this.press_routes.get(press_id)) {
				acc = acc.get_child_at_index(index);
			}
			if (acc.get_n_actions() > 0) {
				acc.do_action(0);
			}
			acc.grab_focus();
			var filled = false;
			try {
				filled = acc.set_text_contents(fields.get(key));
			} catch (GLib.Error e) {
			}
			if (filled) {
				continue;
			}
			var nchars = 0;
			var ifaces = acc.get_interfaces();
			if (ifaces != null) {
				for (var ii = 0; ii < ifaces.length; ii++) {
					if (ifaces.index(ii) != "Text") {
						continue;
					}
					nchars = acc.get_text_iface().get_character_count();
					break;
				}
			}
			for (var b = 0; b < nchars + 2; b++) {
				generate_keyboard_event(0xff08, null, KeySynthType.PRESSRELEASE);
			}
			generate_keyboard_event(0, fields.get(key), KeySynthType.STRING);
		}
	}

	/**
	 * Worker / UI-thread body for {@link press}.
	 *
	 * @param id press id from the last dump
	 * @throws GLib.Error when the ref is missing or action fails
	 */
	private void press_sync(int id) throws GLib.Error
	{
		if (!this.press_routes.has_key(id)) {
			throw new GLib.IOError.INVALID_ARGUMENT("Unknown press-ref %d", id);
		}
		if (!A11y.atspi_ready) {
			init();
			A11y.atspi_ready = true;
		}

		Accessible? app = null;
		var desktop = get_desktop(0);
		for (var i = 0; i < desktop.get_child_count(); i++) {
			var candidate = desktop.get_child_at_index(i);
			if (candidate.get_process_id() != (uint) Posix.getpid()) {
				continue;
			}
			app = candidate;
			break;
		}
		if (app == null) {
			throw new GLib.IOError.FAILED("a11y: no application for pid %u", (uint) Posix.getpid());
		}

		var acc = app;
		foreach (var index in this.press_routes.get(id)) {
			acc = acc.get_child_at_index(index);
		}
		if (acc.get_n_actions() < 1) {
			throw new GLib.IOError.FAILED("Press-ref %d has no a11y action", id);
		}
		acc.do_action(0);
	}
}
